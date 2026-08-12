[CmdletBinding()]
param([string]$Root)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Split-Path -Parent $PSScriptRoot
}
$failures = [Collections.Generic.List[string]]::new()
$profiles = Get-Content -LiteralPath (
    Join-Path $Root 'core\profiles\task-profiles.json'
) -Raw -Encoding UTF8 | ConvertFrom-Json
$map = Get-Content -LiteralPath (
    Join-Path $Root 'core\capabilities\public-capability-map.json'
) -Raw -Encoding UTF8 | ConvertFrom-Json
$resolver = Join-Path $Root 'scripts\resolve-contentos-startup.ps1'
$liteKinds = @(
    ($profiles.install_profiles | Where-Object profile_id -eq 'lite').task_kinds |
        ForEach-Object { [string]$_ }
)

foreach ($profile in @($profiles.profiles)) {
    $kind = [string]$profile.task_kind
    $empty = & $resolver -Root $Root -Profile full -TaskKind $kind -InputsJson '{}' |
        ConvertFrom-Json
    if ([string]$empty.status -ne 'blocked_missing_inputs' -or
        $empty.generation_allowed -ne $false -or
        [string]$empty.task_execution.input_closure.status -ne 'incomplete') {
        $failures.Add("missing_input_gate_failed:$kind")
    }

    $inputObject = [ordered]@{}
    foreach ($name in @($profile.required_inputs)) {
        if ([string]$profile.implementation -eq 'public_adapter' -and
            [string]$name -eq [string]$profile.adapter_binding_input) {
            $inputObject[[string]$name] = [ordered]@{
                schema = 'contentos-adapter-binding-v1'
                adapter_id = [string]$profile.adapter_id
                version = 'fixture-1.0.0'
                task_kind = $kind
                read_scope = @('anonymous-fixture')
                write_scope = @()
                authorization = 'fixture-explicit-authority'
                retry_semantics = 'none'
                output_schema = 'fixture-output-v1'
                readback = 'fixture-readback-pointer'
            }
        }
        else {
            $inputObject[[string]$name] = "fixture-$name"
        }
    }
    $inputsJson = $inputObject | ConvertTo-Json -Compress -Depth 4
    $ready = & $resolver -Root $Root -Profile full -TaskKind $kind -InputsJson $inputsJson |
        ConvertFrom-Json
    if ([string]$ready.status -ne 'ready' -or
        $ready.generation_allowed -ne $true -or
        [string]$ready.task_execution.status -ne 'ready' -or
        [string]$ready.task_execution.input_closure.status -ne 'complete') {
        $failures.Add("full_ready_gate_failed:$kind")
        continue
    }

    $capability = @($map.capabilities | Where-Object task_kind -eq $kind)[0]
    foreach ($comparison in @(
        @('stage', [string]$ready.task.stage, [string]$profile.task_stage),
        @('track', [string]$ready.task.track, [string]$profile.track),
        @('implementation', [string]$ready.task.implementation, [string]$profile.implementation),
        @('parity', [string]$ready.task.parity, [string]$capability.parity)
    )) {
        if ($comparison[1] -ne $comparison[2]) {
            $failures.Add("startup_projection_mismatch:${kind}:$($comparison[0])")
        }
    }
    if ($null -eq $ready.generator_view -or
        @($ready.hydration.rules).Count -ne @($profile.rule_files).Count -or
        @($ready.hydration.rules | Where-Object { [string]::IsNullOrWhiteSpace([string]$_.digest) }).Count -gt 0) {
        $failures.Add("hydration_projection_invalid:$kind")
    }

    $qualityProjection = $ready.generator_view.quality_gate_interface
    $projectedGates = @($qualityProjection.mechanical_gates) + @($qualityProjection.semantic_gates)
    if ((($projectedGates | Sort-Object) -join '|') -ne
        ((@($profile.quality_gates) | Sort-Object) -join '|')) {
        $failures.Add("quality_gate_partition_mismatch:$kind")
    }
    if (@($qualityProjection.mechanical_gates | Where-Object {
        $_ -notin @($profiles.quality_gate_interface.mechanical_gates)
    }).Count -gt 0) {
        $failures.Add("unsupported_mechanical_gate_exposed:$kind")
    }

    if ([string]$profile.implementation -eq 'public_adapter') {
        if ([string]::IsNullOrWhiteSpace([string]$ready.task.adapter_id) -or
            [string]$ready.task.adapter_binding_input -ne
                [string]$profile.adapter_binding_input -or
            [string]$ready.task_execution.adapter_contract.status -ne 'valid') {
            $failures.Add("adapter_admission_not_explicit:$kind")
        }
        $badInputs = [ordered]@{}
        foreach ($name in @($profile.required_inputs)) {
            if ([string]$name -eq [string]$profile.adapter_binding_input) {
                $badInputs[[string]$name] = [ordered]@{
                    schema = 'contentos-adapter-binding-v1'
                    adapter_id = 'wrong-adapter-id'
                    version = 'fixture-1.0.0'
                    task_kind = $kind
                    read_scope = @('anonymous-fixture')
                    write_scope = @()
                    authorization = 'fixture-explicit-authority'
                    retry_semantics = 'none'
                    output_schema = 'fixture-output-v1'
                    readback = 'fixture-readback-pointer'
                }
            }
            else {
                $badInputs[[string]$name] = "fixture-$name"
            }
        }
        $badResult = & $resolver -Root $Root -Profile full -TaskKind $kind `
            -InputsJson ($badInputs | ConvertTo-Json -Compress -Depth 4) |
            ConvertFrom-Json
        if ([string]$badResult.status -ne 'blocked_adapter_contract' -or
            [string]$badResult.task_execution.adapter_contract.status -ne 'invalid' -or
            'adapter_id_mismatch' -notin @($badResult.task_execution.adapter_contract.errors)) {
            $failures.Add("malformed_adapter_not_blocked:$kind")
        }
    }

    $liteResult = & $resolver -Root $Root -Profile lite -TaskKind $kind -InputsJson $inputsJson |
        ConvertFrom-Json
    $expectedLiteStatus = if ($kind -in $liteKinds) { 'ready' } else { 'blocked_profile_scope' }
    if ([string]$liteResult.status -ne $expectedLiteStatus) {
        $failures.Add("lite_scope_mismatch:${kind}:$($liteResult.status)")
    }
}

$wrapperInputs = @{ checkpoint_pointer = 'fixture-checkpoint' } |
    ConvertTo-Json -Compress
$canonicalLite = & $resolver -Root $Root -Profile lite -TaskKind thread_recovery `
    -InputsJson $wrapperInputs | ConvertFrom-Json
$legacyLite = & (Join-Path $Root 'scripts\resolve-startup-lite.ps1') -Root $Root `
    -TaskKind thread_recovery -InputsJson $wrapperInputs | ConvertFrom-Json
if ([string]$legacyLite.status -ne [string]$canonicalLite.status -or
    [string]$legacyLite.task.kind -ne [string]$canonicalLite.task.kind -or
    [string]$legacyLite.active_profile -ne 'lite') {
    $failures.Add('legacy_lite_wrapper_not_thin_equivalent')
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { "FAIL: $_" }
    "SUMMARY: functional parity validation failed ($($failures.Count))"
    exit 1
}
"SUMMARY: functional parity validation passed (28 full contracts, 15 lite preset)"
