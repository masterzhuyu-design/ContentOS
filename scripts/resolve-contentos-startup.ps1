[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$TaskKind,

    [string]$InputsJson = '{}',

    [ValidateSet('full', 'lite')]
    [string]$Profile,

    [string]$Root,

    [switch]$Pretty
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Split-Path -Parent $PSScriptRoot
}

function Get-ContainedPath {
    param([string]$Base, [string]$Candidate)

    $baseFull = [IO.Path]::GetFullPath($Base).TrimEnd('\', '/')
    $candidateFull = if ([IO.Path]::IsPathRooted($Candidate)) {
        [IO.Path]::GetFullPath($Candidate)
    }
    else {
        [IO.Path]::GetFullPath((Join-Path $baseFull $Candidate))
    }
    $prefix = $baseFull + [IO.Path]::DirectorySeparatorChar
    if (
        $candidateFull -ne $baseFull -and
        -not $candidateFull.StartsWith(
            $prefix,
            [StringComparison]::OrdinalIgnoreCase
        )
    ) {
        throw "Path escapes ContentOS root: $Candidate"
    }
    return $candidateFull
}

function Get-TextDigest {
    param([string]$Text)

    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha.ComputeHash([Text.UTF8Encoding]::new($false).GetBytes($Text))
    }
    finally {
        $sha.Dispose()
    }
    return 'sha256:' + (($hash | ForEach-Object { $_.ToString('x2') }) -join '')
}

$rootFull = Get-ContainedPath -Base $Root -Candidate $Root
$profilePath = Get-ContainedPath -Base $rootFull -Candidate 'core/profiles/task-profiles.json'
$capabilityPath = Get-ContainedPath -Base $rootFull -Candidate 'core/capabilities/public-capability-map.json'
foreach ($requiredPath in @($profilePath, $capabilityPath)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "ContentOS contract missing: $requiredPath"
    }
}

$manifest = Get-Content -LiteralPath $profilePath -Raw -Encoding UTF8 | ConvertFrom-Json
$capabilityMap = Get-Content -LiteralPath $capabilityPath -Raw -Encoding UTF8 | ConvertFrom-Json

if ([string]::IsNullOrWhiteSpace($Profile)) {
    $instanceConfig = Join-Path $rootFull '.contentos\config.json'
    $defaultConfig = Join-Path $rootFull 'config\contentos.example.json'
    $configPath = if (Test-Path -LiteralPath $instanceConfig -PathType Leaf) {
        $instanceConfig
    }
    else {
        $defaultConfig
    }
    $config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $Profile = [string]$config.active_profile
}

$installRows = @($manifest.install_profiles | Where-Object profile_id -eq $Profile)
if ($installRows.Count -ne 1) {
    throw "Unknown or duplicate ContentOS profile: $Profile"
}
$installProfile = $installRows[0]

$profileRows = @($manifest.profiles | Where-Object task_kind -eq $TaskKind)
if ($profileRows.Count -ne 1) {
    throw "Unknown or duplicate TaskKind: $TaskKind"
}
$taskProfile = $profileRows[0]
$profileAllowsTask = $TaskKind -in @($installProfile.task_kinds)

try {
    $inputs = $InputsJson | ConvertFrom-Json
}
catch {
    throw "Invalid InputsJson: $($_.Exception.Message)"
}
if ($null -eq $inputs -or $inputs -isnot [psobject]) {
    throw 'InputsJson must contain a JSON object'
}

$inputNames = @($inputs.PSObject.Properties.Name)
$missing = @(
    @($taskProfile.required_inputs) | Where-Object {
        $name = [string]$_
        if ($name -notin $inputNames) {
            return $true
        }
        $value = $inputs.$name
        return (
            $null -eq $value -or
            ($value -is [string] -and [string]::IsNullOrWhiteSpace([string]$value))
        )
    }
)

$adapterErrors = [Collections.Generic.List[string]]::new()
$adapterContract = [ordered]@{
    status = 'not_applicable'
    binding_input = $null
    adapter_id = $null
    errors = @()
}
if ([string]$taskProfile.implementation -eq 'public_adapter') {
    $bindingInput = [string]$taskProfile.adapter_binding_input
    $adapterContract.binding_input = $bindingInput
    $adapterContract.adapter_id = [string]$taskProfile.adapter_id
    if ([string]::IsNullOrWhiteSpace($bindingInput) -or
        $bindingInput -notin @($taskProfile.required_inputs)) {
        $adapterErrors.Add('profile_adapter_binding_input_invalid')
    }
    elseif ($bindingInput -notin $inputNames) {
        $adapterErrors.Add('adapter_binding_missing')
    }
    else {
        $binding = $inputs.$bindingInput
        $bindingProperties = if ($null -ne $binding) {
            @($binding.PSObject.Properties.Name)
        }
        else {
            @()
        }
        foreach ($requiredBindingField in @(
            'schema', 'adapter_id', 'version', 'task_kind', 'read_scope',
            'write_scope', 'authorization', 'retry_semantics',
            'output_schema', 'readback'
        )) {
            if ($requiredBindingField -notin $bindingProperties) {
                $adapterErrors.Add("adapter_field_missing:$requiredBindingField")
            }
        }
        if ('schema' -in $bindingProperties -and
            [string]$binding.schema -ne 'contentos-adapter-binding-v1') {
            $adapterErrors.Add('adapter_schema_mismatch')
        }
        if ('adapter_id' -in $bindingProperties -and
            [string]$binding.adapter_id -ne [string]$taskProfile.adapter_id) {
            $adapterErrors.Add('adapter_id_mismatch')
        }
        if ('task_kind' -in $bindingProperties -and
            [string]$binding.task_kind -ne $TaskKind) {
            $adapterErrors.Add('adapter_task_kind_mismatch')
        }
        foreach ($textField in @(
            'version', 'authorization', 'retry_semantics', 'output_schema', 'readback'
        )) {
            if ($textField -in $bindingProperties -and
                [string]::IsNullOrWhiteSpace([string]$binding.$textField)) {
                $adapterErrors.Add("adapter_field_empty:$textField")
            }
        }
        if ('read_scope' -in $bindingProperties -and
            @($binding.read_scope).Count -eq 0) {
            $adapterErrors.Add('adapter_read_scope_empty')
        }
        if ('retry_semantics' -in $bindingProperties -and
            [string]$binding.retry_semantics -notin @(
                'none', 'idempotent', 'explicit_only'
            )) {
            $adapterErrors.Add('adapter_retry_semantics_invalid')
        }
    }
    $adapterContract.status = if ($adapterErrors.Count -eq 0) { 'valid' } else { 'invalid' }
    $adapterContract.errors = @($adapterErrors)
}

$ruleRows = [Collections.Generic.List[object]]::new()
$totalBytes = 0
foreach ($relativeRule in @($taskProfile.rule_files)) {
    $rulePath = Get-ContainedPath -Base $rootFull -Candidate ([string]$relativeRule)
    if (-not (Test-Path -LiteralPath $rulePath -PathType Leaf)) {
        throw "Rule file missing: $relativeRule"
    }
    $content = [IO.File]::ReadAllText($rulePath, [Text.UTF8Encoding]::new($false))
    $bytes = [Text.UTF8Encoding]::new($false).GetByteCount($content)
    $totalBytes += $bytes
    $ruleRows.Add([ordered]@{
        path = ([string]$relativeRule).Replace('\', '/')
        utf8_bytes = $bytes
        digest = Get-TextDigest -Text $content
        content = $content
    })
}

$softTarget = [int]$taskProfile.budget.soft_target_utf8_bytes
$advisoryCeiling = [int]$taskProfile.budget.advisory_ceiling_utf8_bytes
$hardCeiling = [int]$taskProfile.budget.hard_safety_ceiling_utf8_bytes
$budgetState = if ($totalBytes -le $softTarget) {
    'within_soft_target'
}
elseif ($totalBytes -le $advisoryCeiling) {
    'within_flexible_ceiling'
}
elseif ($totalBytes -le $hardCeiling) {
    'scope_split_advised'
}
else {
    'blocked_budget_overflow'
}

$status = if (-not $profileAllowsTask) {
    'blocked_profile_scope'
}
elseif ($budgetState -eq 'blocked_budget_overflow') {
    'blocked_budget_overflow'
}
elseif ($missing.Count -gt 0) {
    'blocked_missing_inputs'
}
elseif ($adapterErrors.Count -gt 0) {
    'blocked_adapter_contract'
}
else {
    'ready'
}

$capabilityRows = @($capabilityMap.capabilities | Where-Object task_kind -eq $TaskKind)
if ($capabilityRows.Count -ne 1) {
    throw "Capability map mismatch for TaskKind: $TaskKind"
}
$capability = $capabilityRows[0]

$qualityGateProjection = $null
if (@($taskProfile.quality_gates).Count -gt 0) {
    $qualityTool = Get-ContainedPath -Base $rootFull -Candidate ([string]$manifest.quality_gate_interface.tool)
    if (-not (Test-Path -LiteralPath $qualityTool -PathType Leaf)) {
        throw "Quality gate tool missing: $qualityTool"
    }
    $allTaskGates = @($taskProfile.quality_gates | ForEach-Object { [string]$_ })
    $supportedMechanicalGates = @(
        $manifest.quality_gate_interface.mechanical_gates |
            ForEach-Object { [string]$_ }
    )
    $qualityGateProjection = [ordered]@{
        tool = [string]$manifest.quality_gate_interface.tool
        input_schema = [string]$manifest.quality_gate_interface.input_schema
        output_schema = [string]$manifest.quality_gate_interface.output_schema
        gates = $allTaskGates
        mechanical_gates = @(
            $allTaskGates | Where-Object { $_ -in $supportedMechanicalGates }
        )
        semantic_gates = @(
            $allTaskGates | Where-Object { $_ -notin $supportedMechanicalGates }
        )
        semantic_gate_authority = [string](
            $manifest.quality_gate_interface.semantic_gate_authority
        )
        side_effects = [string]$manifest.quality_gate_interface.side_effects
    }
}

$generatorView = $null
if ($status -eq 'ready') {
    $generatorView = [ordered]@{
        task_kind = $TaskKind
        task_stage = [string]$taskProfile.task_stage
        track = [string]$taskProfile.track
        objective = [string]$taskProfile.objective
        implementation = [string]$taskProfile.implementation
        adapter_id = if ($null -ne $taskProfile.adapter_id) { [string]$taskProfile.adapter_id } else { $null }
        adapter_binding_input = if ($null -ne $taskProfile.adapter_binding_input) { [string]$taskProfile.adapter_binding_input } else { $null }
        inputs = $inputs
        flexible_budget_state = $budgetState
        hydrated_rules = $ruleRows
        quality_gate_interface = $qualityGateProjection
    }
}

$envelope = [ordered]@{
    schema = 'contentos-startup-envelope-v1'
    release_id = [string]$manifest.release_id
    status = $status
    generation_allowed = ($status -eq 'ready')
    generation_scope = if ($status -eq 'ready') { 'current_task_kind_only' } else { 'none' }
    active_profile = $Profile
    task_execution = [ordered]@{
        status = if ($status -eq 'ready') { 'ready' } else { 'blocked' }
        input_closure = [ordered]@{
            status = if ($missing.Count -eq 0) { 'complete' } else { 'incomplete' }
            required_count = @($taskProfile.required_inputs).Count
            provided_count = @($taskProfile.required_inputs).Count - $missing.Count
            missing = $missing
            input_digest = Get-TextDigest -Text $InputsJson
        }
        profile_scope = [ordered]@{
            profile_id = $Profile
            task_allowed = $profileAllowsTask
        }
        adapter_contract = $adapterContract
    }
    task = [ordered]@{
        kind = $TaskKind
        stage = [string]$taskProfile.task_stage
        track = [string]$taskProfile.track
        objective = [string]$taskProfile.objective
        implementation = [string]$taskProfile.implementation
        adapter_id = if ($null -ne $taskProfile.adapter_id) { [string]$taskProfile.adapter_id } else { $null }
        adapter_binding_input = if ($null -ne $taskProfile.adapter_binding_input) { [string]$taskProfile.adapter_binding_input } else { $null }
        parity = [string]$capability.parity
        required_inputs = @($taskProfile.required_inputs)
        missing_inputs = $missing
    }
    hydration = [ordered]@{
        status = 'complete'
        rule_count = $ruleRows.Count
        total_utf8_bytes = $totalBytes
        budget = [ordered]@{
            soft_target_utf8_bytes = $softTarget
            advisory_ceiling_utf8_bytes = $advisoryCeiling
            hard_safety_ceiling_utf8_bytes = $hardCeiling
            state = $budgetState
            semantic_truncation_forbidden = $true
        }
        rules = $ruleRows
    }
    generator_view = $generatorView
}

if ($Pretty) {
    $envelope | ConvertTo-Json -Depth 14
}
else {
    $envelope | ConvertTo-Json -Depth 14 -Compress
}
