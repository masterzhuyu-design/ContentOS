[CmdletBinding()]
param([string]$Root)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Split-Path -Parent $PSScriptRoot
}
$Root = [IO.Path]::GetFullPath($Root)
$failures = [Collections.Generic.List[string]]::new()
$profiles = Get-Content -LiteralPath (
    Join-Path $Root 'core\profiles\task-profiles.json'
) -Raw -Encoding UTF8 | ConvertFrom-Json
$map = Get-Content -LiteralPath (
    Join-Path $Root 'core\capabilities\public-capability-map.json'
) -Raw -Encoding UTF8 | ConvertFrom-Json
$resolver = Join-Path $Root 'scripts\resolve-contentos-startup.ps1'
$externalBoundary = Join-Path $Root `
    'scripts\invoke-contentos-external-client-boundary.ps1'
$liteKinds = @(
    ($profiles.install_profiles | Where-Object profile_id -eq 'lite').task_kinds |
        ForEach-Object { [string]$_ }
)

function Get-FileDigest {
    param([string]$Path)
    return 'sha256:' + (
        Get-FileHash -LiteralPath $Path -Algorithm SHA256
    ).Hash.ToLowerInvariant()
}

function New-AdapterBinding {
    param([object]$Profile, [switch]$Bad)

    return [ordered]@{
        schema = 'contentos-adapter-binding-v1'
        adapter_id = if ($Bad) { 'wrong-adapter-id' } else {
            [string]$Profile.adapter_id
        }
        version = 'fixture-1.0.0'
        task_kind = [string]$Profile.task_kind
        read_scope = @('anonymous-fixture')
        write_scope = @()
        authorization = 'fixture-explicit-authority'
        retry_semantics = 'none'
        output_schema = 'fixture-output-v1'
        readback = 'fixture-readback-pointer'
    }
}

function New-TaskExecutionInputJson {
    param(
        [object]$Profile,
        [string[]]$OmitRoles = @(),
        [switch]$BadAdapter
    )

    $kind = [string]$Profile.task_kind
    $turn = "functional-$kind"
    $workspaceRoles = @(
        $Profile.workspace_required_inputs |
            Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
            ForEach-Object { [string]$_ }
    )
    $bindings = [Collections.Generic.List[object]]::new()
    foreach ($roleObject in @($Profile.required_inputs)) {
        $role = [string]$roleObject
        if ($role -in $OmitRoles) { continue }
        if ($role -in $workspaceRoles) {
            $relative = switch ($role) {
                'checkpoint_pointer' { 'tests/fixtures/valid-checkpoint.md' }
                'current_learning_record' {
                    'tests/fixtures/current-learning-record.md'
                }
                default { throw "No workspace fixture for role: $role" }
            }
            $path = Join-Path $Root $relative
            $bindings.Add([ordered]@{
                role = $role
                adapter = 'workspace_artifact'
                source_pointer = $relative
                expected_digest = Get-FileDigest -Path $path
            })
            continue
        }
        $value = if (
            [string]$Profile.implementation -eq 'public_adapter' -and
            $role -eq [string]$Profile.adapter_binding_input
        ) {
            New-AdapterBinding -Profile $Profile -Bad:$BadAdapter
        }
        else { "fixture-$role" }
        if ($role -in @(
            'affected_rule_files', 'affected_tests', 'current_round_answers',
            'user_locks'
        )) {
            $value = [string[]]@("fixture-$role-item")
        }
        $bindings.Add([ordered]@{
            role = $role
            adapter = 'current_turn_inline'
            source_pointer = "current_turn:${turn}:$role"
            value = $value
        })
    }
    return [ordered]@{
        schema = 'contentos-task-execution-input-v1'
        scope_id = "functional-$kind"
        current_turn_id = $turn
        task_kind = $kind
        task_stage = [string]$Profile.task_stage
        bindings = @($bindings)
    } | ConvertTo-Json -Compress -Depth 14
}

foreach ($profile in @($profiles.profiles)) {
    $kind = [string]$profile.task_kind
    $emptyInput = [ordered]@{
        schema = 'contentos-task-execution-input-v1'
        scope_id = "missing-$kind"
        current_turn_id = "missing-$kind"
        task_kind = $kind
        task_stage = [string]$profile.task_stage
        bindings = @()
    } | ConvertTo-Json -Compress -Depth 5
    $empty = & $resolver -Root $Root -Profile full -TaskKind $kind `
        -TaskExecutionInputJson $emptyInput | ConvertFrom-Json
    if ([string]$empty.status -ne 'blocked_missing_inputs' -or
        $empty.generation_allowed -ne $false -or
        [string]$empty.task_execution.input_closure.status -ne 'incomplete') {
        $failures.Add("missing_input_gate_failed:$kind")
    }

    $inputJson = New-TaskExecutionInputJson -Profile $profile
    $ready = & $resolver -Root $Root -Profile full -TaskKind $kind `
        -TaskExecutionInputJson $inputJson | ConvertFrom-Json
    $adapterBacked = [string]$profile.implementation -eq 'public_adapter'
    if ($adapterBacked) {
        if ([string]$ready.status -ne 'ready_adapter_pending_host_authority' -or
            $ready.generation_allowed -ne $false -or
            [string]$ready.task_execution.status -ne 'waiting_host_authority' -or
            [string]$ready.task_execution.input_closure.status -ne 'complete' -or
            [string]$ready.task_execution.adapter_contract.status -ne
                'structurally_valid_untrusted') {
            $failures.Add("adapter_authority_gate_failed:${kind}:$($ready.status)")
        }
    }
    elseif ([string]$ready.status -ne 'ready' -or
        $ready.generation_allowed -ne $true -or
        [string]$ready.task_execution.status -ne 'ready' -or
        [string]$ready.task_execution.input_closure.status -ne 'complete') {
        $failures.Add("native_ready_gate_failed:${kind}:$($ready.status)")
        continue
    }

    $capability = @($map.capabilities | Where-Object task_kind -eq $kind)[0]
    foreach ($comparison in @(
        @('stage', [string]$ready.task.stage, [string]$profile.task_stage),
        @('track', [string]$ready.task.track, [string]$profile.track),
        @('implementation', [string]$ready.task.implementation,
            [string]$profile.implementation),
        @('parity', [string]$ready.task.parity, [string]$capability.parity)
    )) {
        if ($comparison[1] -ne $comparison[2]) {
            $failures.Add("startup_projection_mismatch:${kind}:$($comparison[0])")
        }
    }
    if ((-not $adapterBacked -and $null -eq $ready.generator_view) -or
        @($ready.hydration.rules).Count -ne @($profile.rule_files).Count -or
        @($ready.task_execution.input_closure.bindings |
            Where-Object status -ne 'covered').Count -gt 0) {
        $failures.Add("hydration_or_binding_projection_invalid:$kind")
    }

    $qualityProjection = if ($adapterBacked) {
        $ready.admission_view.quality_gate_interface
    }
    else { $ready.generator_view.quality_gate_interface }
    $projectedGates = @($qualityProjection.mechanical_gates) +
        @($qualityProjection.semantic_gates)
    if ((($projectedGates | Sort-Object) -join '|') -ne
        ((@($profile.quality_gates) | Sort-Object) -join '|')) {
        $failures.Add("quality_gate_partition_mismatch:$kind")
    }

    if ($adapterBacked) {
        $badJson = New-TaskExecutionInputJson -Profile $profile -BadAdapter
        $bad = & $resolver -Root $Root -Profile full -TaskKind $kind `
            -TaskExecutionInputJson $badJson | ConvertFrom-Json
        if ([string]$bad.status -ne 'blocked_adapter_contract' -or
            'adapter_id_mismatch' -notin
                @($bad.task_execution.adapter_contract.errors)) {
            $failures.Add("malformed_adapter_not_blocked:$kind")
        }
    }

    $lite = & $resolver -Root $Root -Profile lite -TaskKind $kind `
        -TaskExecutionInputJson $inputJson | ConvertFrom-Json
    $expectedLiteStatus = if ($kind -in $liteKinds) {
        if ($adapterBacked) { 'ready_adapter_pending_host_authority' }
        else { 'ready' }
    }
    else { 'blocked_profile_scope' }
    if ([string]$lite.status -ne $expectedLiteStatus) {
        $failures.Add("lite_scope_mismatch:${kind}:$($lite.status)")
    }
}

$recoveryProfile = @(
    $profiles.profiles | Where-Object task_kind -eq 'thread_recovery'
)[0]
$recoveryInput = New-TaskExecutionInputJson -Profile $recoveryProfile
$canonicalLite = & $resolver -Root $Root -Profile lite `
    -TaskKind thread_recovery -TaskExecutionInputJson $recoveryInput |
    ConvertFrom-Json
$wrapperLite = & (Join-Path $Root 'scripts\resolve-startup-lite.ps1') `
    -Root $Root -TaskKind thread_recovery `
    -TaskExecutionInputJson $recoveryInput | ConvertFrom-Json
if ([string]$wrapperLite.status -ne [string]$canonicalLite.status -or
    [string]$wrapperLite.recovery.status -ne 'resumable' -or
    [string]$wrapperLite.active_profile -ne 'lite') {
    $failures.Add('lite_wrapper_not_thin_equivalent')
}

$legacy = & $resolver -Root $Root -Profile full -TaskKind knowledge_query `
    -InputsJson '{"query":"invented","source_scope":"invented"}' |
    ConvertFrom-Json
if ([string]$legacy.status -ne 'blocked_legacy_input_interface' -or
    [bool]$legacy.generation_allowed) {
    $failures.Add('legacy_inputs_json_remained_authoritative')
}

$queryProfile = @(
    $profiles.profiles | Where-Object task_kind -eq 'knowledge_query'
)[0]
$wrongPointerObject = New-TaskExecutionInputJson -Profile $queryProfile |
    ConvertFrom-Json
$wrongPointerObject.bindings[0].source_pointer =
    'current_turn:different-turn:query'
$wrongPointer = & $resolver -Root $Root -Profile full -TaskKind knowledge_query `
    -TaskExecutionInputJson (
        $wrongPointerObject | ConvertTo-Json -Compress -Depth 14
    ) | ConvertFrom-Json
if ([string]$wrongPointer.status -ne 'blocked_input_contract') {
    $failures.Add('wrong_current_turn_pointer_not_blocked')
}

$staleObject = $recoveryInput | ConvertFrom-Json
$staleObject.bindings[0].expected_digest = 'sha256:' + ('0' * 64)
$stale = & $resolver -Root $Root -Profile full -TaskKind thread_recovery `
    -TaskExecutionInputJson ($staleObject | ConvertTo-Json -Compress -Depth 14) |
    ConvertFrom-Json
if ([string]$stale.status -ne 'blocked_stale_inputs') {
    $failures.Add('stale_workspace_digest_not_blocked')
}

$missingCheckpointObject = $recoveryInput | ConvertFrom-Json
$missingCheckpointObject.bindings[0].source_pointer =
    'tests/fixtures/does-not-exist.md'
$missingCheckpoint = & $resolver -Root $Root -Profile full `
    -TaskKind thread_recovery -TaskExecutionInputJson (
        $missingCheckpointObject | ConvertTo-Json -Compress -Depth 14
    ) | ConvertFrom-Json
if ([string]$missingCheckpoint.status -ne 'blocked_input_contract') {
    $failures.Add('missing_checkpoint_path_not_blocked')
}

$invalidCheckpointObject = $recoveryInput | ConvertFrom-Json
$invalidCheckpointPath = Join-Path $Root 'templates\checkpoint.md'
$invalidCheckpointObject.bindings[0].source_pointer = 'templates/checkpoint.md'
$invalidCheckpointObject.bindings[0].expected_digest =
    Get-FileDigest -Path $invalidCheckpointPath
$invalidCheckpoint = & $resolver -Root $Root -Profile full `
    -TaskKind thread_recovery -TaskExecutionInputJson (
        $invalidCheckpointObject | ConvertTo-Json -Compress -Depth 14
    ) | ConvertFrom-Json
if ([string]$invalidCheckpoint.status -ne 'blocked_checkpoint_contract') {
    $failures.Add('invalid_checkpoint_contract_not_blocked')
}

$firstRoundProfile = @(
    $profiles.profiles | Where-Object task_kind -eq 'fixed_learning_first_round'
)[0]
$noAnswerJson = New-TaskExecutionInputJson -Profile $firstRoundProfile `
    -OmitRoles @('current_round_answers')
$noAnswer = & $resolver -Root $Root -Profile full `
    -TaskKind fixed_learning_first_round `
    -TaskExecutionInputJson $noAnswerJson | ConvertFrom-Json
if ([string]$noAnswer.status -ne 'blocked_missing_inputs') {
    $failures.Add('first_round_without_current_answers_not_blocked')
}

$blankAnswersObject = New-TaskExecutionInputJson -Profile $firstRoundProfile |
    ConvertFrom-Json
@($blankAnswersObject.bindings | Where-Object role -eq 'current_round_answers')[0].value =
    @('   ')
$blankAnswers = & $resolver -Root $Root -Profile full `
    -TaskKind fixed_learning_first_round -TaskExecutionInputJson (
        $blankAnswersObject | ConvertTo-Json -Compress -Depth 14
    ) | ConvertFrom-Json
if ([string]$blankAnswers.status -ne 'blocked_input_contract' -or
    'binding_value_missing:current_round_answers' -notin
        @($blankAnswers.task_execution.input_closure.errors)) {
    $failures.Add('blank_answer_array_not_blocked')
}

$extraBindingFieldObject = New-TaskExecutionInputJson -Profile $queryProfile |
    ConvertFrom-Json
$extraBindingFieldObject.bindings[0] | Add-Member -NotePropertyName unexpected `
    -NotePropertyValue 'not-in-schema'
$extraBindingField = & $resolver -Root $Root -Profile full `
    -TaskKind knowledge_query -TaskExecutionInputJson (
        $extraBindingFieldObject | ConvertTo-Json -Compress -Depth 14
    ) | ConvertFrom-Json
if ([string]$extraBindingField.status -ne 'blocked_input_contract' -or
    'binding_field_not_allowed:query:unexpected' -notin
        @($extraBindingField.task_execution.input_closure.errors)) {
    $failures.Add('binding_additional_property_not_blocked')
}

$largeInputObject = New-TaskExecutionInputJson -Profile $queryProfile |
    ConvertFrom-Json
@($largeInputObject.bindings | Where-Object role -eq 'query')[0].value =
    ('x' * 300000)
$largeInput = & $resolver -Root $Root -Profile full `
    -TaskKind knowledge_query -TaskExecutionInputJson (
        $largeInputObject | ConvertTo-Json -Compress -Depth 14
    ) | ConvertFrom-Json
if ([string]$largeInput.status -ne 'blocked_input_budget' -or
    'binding_input_budget_exceeded:query' -notin
        @($largeInput.task_execution.input_closure.errors)) {
    $failures.Add('oversized_binding_not_blocked')
}

$adapterProfile = @(
    $profiles.profiles | Where-Object task_kind -eq 'restricted_information_collection'
)[0]
$extraAdapterFieldObject = New-TaskExecutionInputJson -Profile $adapterProfile |
    ConvertFrom-Json
$adapterRole = [string]$adapterProfile.adapter_binding_input
$adapterValue = @(
    $extraAdapterFieldObject.bindings | Where-Object role -eq $adapterRole
)[0].value
$adapterValue | Add-Member -NotePropertyName unexpected `
    -NotePropertyValue 'not-in-schema'
$extraAdapterField = & $resolver -Root $Root -Profile full `
    -TaskKind restricted_information_collection -TaskExecutionInputJson (
        $extraAdapterFieldObject | ConvertTo-Json -Compress -Depth 14
    ) | ConvertFrom-Json
if ([string]$extraAdapterField.status -ne 'blocked_adapter_contract' -or
    'adapter_field_not_allowed:unexpected' -notin
        @($extraAdapterField.task_execution.adapter_contract.errors)) {
    $failures.Add('adapter_additional_property_not_blocked')
}

$junction = $null
$outside = Join-Path ([IO.Path]::GetTempPath()) (
    'contentos-reparse-target-' + [guid]::NewGuid().ToString('N')
)
try {
    [void](New-Item -ItemType Directory -Path $outside -Force)
    Copy-Item -LiteralPath (Join-Path $Root 'tests\fixtures\valid-checkpoint.md') `
        -Destination (Join-Path $outside 'checkpoint.md')
    $junction = Join-Path $Root (
        'tests\fixtures\reparse-' + [guid]::NewGuid().ToString('N')
    )
    [void](New-Item -ItemType Junction -Path $junction -Target $outside)
    $relativeJunction = $junction.Substring($Root.Length).TrimStart('\', '/')
    $reparseObject = New-TaskExecutionInputJson -Profile $recoveryProfile |
        ConvertFrom-Json
    $reparseObject.bindings[0].source_pointer = (
        $relativeJunction + '\checkpoint.md'
    )
    $reparseObject.bindings[0].expected_digest = Get-FileDigest -Path (
        Join-Path $outside 'checkpoint.md'
    )
    $reparse = & $resolver -Root $Root -Profile full `
        -TaskKind thread_recovery -TaskExecutionInputJson (
            $reparseObject | ConvertTo-Json -Compress -Depth 14
        ) | ConvertFrom-Json
    if ([string]$reparse.status -ne 'blocked_input_contract' -or
        'workspace_pointer_reparse_point:checkpoint_pointer' -notin
            @($reparse.task_execution.input_closure.errors)) {
        $failures.Add('workspace_reparse_point_not_blocked')
    }
}
catch {
    $failures.Add('workspace_reparse_test_unavailable')
}
finally {
    if ($null -ne $junction -and (Test-Path -LiteralPath $junction)) {
        $junctionFull = [IO.Path]::GetFullPath($junction)
        $fixtureRoot = [IO.Path]::GetFullPath(
            (Join-Path $Root 'tests\fixtures')
        ).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
        $junctionItem = Get-Item -LiteralPath $junctionFull -Force
        if ($junctionFull.StartsWith(
            $fixtureRoot,
            [StringComparison]::OrdinalIgnoreCase
        ) -and ($junctionItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            [IO.Directory]::Delete($junctionFull)
        }
    }
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\', '/')
    $outsideFull = [IO.Path]::GetFullPath($outside)
    if ($outsideFull.StartsWith(
        $tempRoot + [IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase
    ) -and (Test-Path -LiteralPath $outsideFull)) {
        Remove-Item -LiteralPath $outsideFull -Recurse -Force
    }
}

$validQueryInput = New-TaskExecutionInputJson -Profile $queryProfile
$hostTurnMismatchBlocked = $false
try {
    $null = & $externalBoundary -Root $Root -Profile full `
        -ClaimedClientId 'functional-test' `
        -ExternalSessionId 'functional-session-0001' `
        -CurrentHostTurnId 'different-host-turn' `
        -TaskKind knowledge_query `
        -TaskExecutionInputJson $validQueryInput
}
catch { $hostTurnMismatchBlocked = $true }
if (-not $hostTurnMismatchBlocked) {
    $failures.Add('external_host_turn_mismatch_not_blocked')
}
$validQueryObject = $validQueryInput | ConvertFrom-Json
$proposal = & $externalBoundary -Root $Root -Profile full `
    -ClaimedClientId 'functional-test' `
    -ExternalSessionId 'functional-session-0001' `
    -CurrentHostTurnId ([string]$validQueryObject.current_turn_id) `
    -TaskKind knowledge_query `
    -TaskExecutionInputJson $validQueryInput | ConvertFrom-Json
if ([string]$proposal.status -ne 'ready' -or
    [string]$proposal.mode -ne 'proposal_only' -or
    [bool]$proposal.external_access.write_authority -or
    [bool]$proposal.external_access.adoption_authority -or
    [bool]$proposal.external_access.domain_action_allowed) {
    $failures.Add('external_proposal_boundary_invalid')
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { "FAIL: $_" }
    "SUMMARY: contract admission validation failed ($($failures.Count))"
    exit 1
}
"SUMMARY: contract admission validation passed (28 structured contracts, 15 lite preset, fail-closed regressions)"
