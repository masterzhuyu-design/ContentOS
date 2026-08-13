[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$TaskKind,

    [string]$TaskExecutionInputJson = '',

    [string]$InputsJson = '',

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
    if ($candidateFull -ne $baseFull) {
        $relative = $candidateFull.Substring($baseFull.Length).
            TrimStart('\', '/')
        $cursor = $baseFull
        foreach ($segment in @($relative -split '[\\/]')) {
            if ([string]::IsNullOrWhiteSpace($segment)) { continue }
            $cursor = Join-Path $cursor $segment
            if (Test-Path -LiteralPath $cursor) {
                $item = Get-Item -LiteralPath $cursor -Force
                if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                    throw "ContentOS path contains reparse point: $cursor"
                }
            }
        }
    }
    return $candidateFull
}

function Get-TextDigest {
    param([AllowNull()][string]$Text)

    if ($null -eq $Text) { $Text = '' }
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha.ComputeHash(
            [Text.UTF8Encoding]::new($false).GetBytes($Text)
        )
    }
    finally {
        $sha.Dispose()
    }
    return 'sha256:' + (($hash | ForEach-Object { $_.ToString('x2') }) -join '')
}

function Get-FileDigest {
    param([string]$Path)

    return 'sha256:' + (
        Get-FileHash -LiteralPath $Path -Algorithm SHA256
    ).Hash.ToLowerInvariant()
}

function Get-ValueText {
    param([AllowNull()][object]$Value)

    if ($Value -is [string]) { return [string]$Value }
    return ($Value | ConvertTo-Json -Compress -Depth 30)
}

function Test-ContentValuePresent {
    param([AllowNull()][object]$Value)

    if ($null -eq $Value) { return $false }
    if ($Value -is [string]) {
        return -not [string]::IsNullOrWhiteSpace([string]$Value)
    }
    if ($Value -is [array] -or (
        $Value -is [System.Collections.IEnumerable] -and
        $Value -isnot [string] -and
        $Value -isnot [psobject]
    )) {
        $items = @($Value)
        if ($items.Count -eq 0) { return $false }
        foreach ($item in $items) {
            if (-not (Test-ContentValuePresent -Value $item)) { return $false }
        }
        return $true
    }
    if ($Value -is [psobject] -and $Value -isnot [ValueType]) {
        $properties = @($Value.PSObject.Properties)
        if ($properties.Count -eq 0) { return $false }
        return @(
            $properties | Where-Object {
                Test-ContentValuePresent -Value $_.Value
            }
        ).Count -gt 0
    }
    return $true
}

function Test-RoleValueContract {
    param(
        [string]$Role,
        [AllowNull()][object]$Value,
        [AllowNull()][object]$Contract
    )

    if ($null -eq $Contract) { return $true }
    switch ([string]$Contract.type) {
        'nonblank_string_array' {
            if ($Value -isnot [array]) { return $false }
            $items = @($Value)
            if ($items.Count -lt [int]$Contract.min_items) { return $false }
            foreach ($item in $items) {
                if ($item -isnot [string] -or
                    [string]::IsNullOrWhiteSpace([string]$item)) {
                    return $false
                }
            }
            return $true
        }
        default { throw "Unsupported input role contract for ${Role}: $($Contract.type)" }
    }
}

function Get-CheckpointProjection {
    param([string]$Text)

    $fields = [ordered]@{}
    $normalized = $Text.Replace("`r`n", "`n").Replace("`r", "`n")
    $lines = @($normalized -split "`n")
    if ($lines.Count -lt 3 -or $lines[0].Trim() -ne '---') {
        return [pscustomobject]@{ valid = $false; fields = $fields }
    }
    $closed = $false
    for ($index = 1; $index -lt $lines.Count; $index++) {
        if ($lines[$index].Trim() -eq '---') {
            $closed = $true
            break
        }
        if ($lines[$index] -match '^([A-Za-z0-9_]+):\s*(.*)$') {
            $value = [string]$Matches[2]
            $value = $value.Trim()
            if ($value.Length -ge 2 -and (
                ($value.StartsWith('"') -and $value.EndsWith('"')) -or
                ($value.StartsWith("'") -and $value.EndsWith("'"))
            )) {
                $value = $value.Substring(1, $value.Length - 2)
            }
            $fields[[string]$Matches[1]] = $value
        }
    }
    return [pscustomobject]@{ valid = $closed; fields = $fields }
}

$rootFull = Get-ContainedPath -Base $Root -Candidate $Root
$profilePath = Get-ContainedPath -Base $rootFull -Candidate 'core/profiles/task-profiles.json'
$capabilityPath = Get-ContainedPath -Base $rootFull -Candidate 'core/capabilities/public-capability-map.json'
foreach ($requiredPath in @($profilePath, $capabilityPath)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "ContentOS contract missing: $requiredPath"
    }
}

$manifest = Get-Content -LiteralPath $profilePath -Raw -Encoding UTF8 |
    ConvertFrom-Json
$capabilityMap = Get-Content -LiteralPath $capabilityPath -Raw -Encoding UTF8 |
    ConvertFrom-Json

if ([string]::IsNullOrWhiteSpace($Profile)) {
    $instanceConfig = Join-Path $rootFull '.contentos\config.json'
    $defaultConfig = Join-Path $rootFull 'config\contentos.example.json'
    $configPath = if (Test-Path -LiteralPath $instanceConfig -PathType Leaf) {
        $instanceConfig
    }
    else {
        $defaultConfig
    }
    $config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 |
        ConvertFrom-Json
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
$inputContract = $manifest.input_contract
$maxTaskInputBytes = [int64]$inputContract.max_task_execution_input_utf8_bytes
$maxBindingBytes = [int64]$inputContract.max_binding_utf8_bytes
$maxTotalBindingBytes = [int64]$inputContract.max_total_binding_utf8_bytes
$maxBindingCount = [int]$inputContract.max_binding_count
$requiredRoles = @($taskProfile.required_inputs | ForEach-Object { [string]$_ })
$workspaceRequiredRoles = @(
    $taskProfile.workspace_required_inputs |
        Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
        ForEach-Object { [string]$_ }
)

$inputErrors = [Collections.Generic.List[string]]::new()
$staleInputs = [Collections.Generic.List[string]]::new()
$bindingRows = [Collections.Generic.List[object]]::new()
$inputValues = [ordered]@{}
$presentRoles = [Collections.Generic.List[string]]::new()
$taskExecutionInput = $null
$taskExecutionInputDigest = Get-TextDigest -Text $TaskExecutionInputJson
$taskExecutionInputBytes = [Text.UTF8Encoding]::new($false).
    GetByteCount([string]$TaskExecutionInputJson)
$totalBindingBytes = [int64]0

if (-not [string]::IsNullOrWhiteSpace($InputsJson)) {
    $inputErrors.Add('legacy_inputs_json_not_authoritative')
    if (-not [string]::IsNullOrWhiteSpace($TaskExecutionInputJson)) {
        $inputErrors.Add('multiple_input_interfaces_not_allowed')
    }
}
elseif ([string]::IsNullOrWhiteSpace($TaskExecutionInputJson)) {
    $inputErrors.Add('task_execution_input_missing')
}
elseif ($taskExecutionInputBytes -gt $maxTaskInputBytes) {
    $inputErrors.Add('task_execution_input_budget_exceeded')
}
else {
    try {
        $taskExecutionInput = $TaskExecutionInputJson | ConvertFrom-Json
    }
    catch {
        $inputErrors.Add('task_execution_input_invalid_json')
    }
}

if ($null -ne $taskExecutionInput) {
    $allowedRootFields = @(
        'schema', 'scope_id', 'current_turn_id', 'task_kind', 'task_stage',
        'bindings'
    )
    foreach ($field in @($taskExecutionInput.PSObject.Properties.Name)) {
        if ([string]$field -notin $allowedRootFields) {
            $inputErrors.Add("caller_owned_field_not_allowed:$field")
        }
    }
    foreach ($field in $allowedRootFields) {
        if ($field -notin @($taskExecutionInput.PSObject.Properties.Name)) {
            $inputErrors.Add("task_execution_field_missing:$field")
        }
    }
    if ([string]$taskExecutionInput.schema -ne
        'contentos-task-execution-input-v1') {
        $inputErrors.Add('task_execution_schema_mismatch')
    }
    if ([string]::IsNullOrWhiteSpace([string]$taskExecutionInput.scope_id)) {
        $inputErrors.Add('scope_id_missing')
    }
    $currentTurnId = [string]$taskExecutionInput.current_turn_id
    if ([string]::IsNullOrWhiteSpace($currentTurnId) -or
        $currentTurnId -notmatch '^[A-Za-z0-9][A-Za-z0-9._:@-]{0,255}$') {
        $inputErrors.Add('current_turn_id_invalid')
    }
    if ([string]$taskExecutionInput.task_kind -ne $TaskKind) {
        $inputErrors.Add('task_kind_mismatch')
    }
    if ([string]$taskExecutionInput.task_stage -ne
        [string]$taskProfile.task_stage) {
        $inputErrors.Add('task_stage_mismatch')
    }

    if ($taskExecutionInput -is [array]) {
        $inputErrors.Add('task_execution_input_must_be_object')
    }
    if ($null -eq $taskExecutionInput.PSObject.Properties['bindings'] -or
        $taskExecutionInput.bindings -isnot [array]) {
        $inputErrors.Add('bindings_must_be_array')
    }
    elseif (@($taskExecutionInput.bindings).Count -gt $maxBindingCount) {
        $inputErrors.Add('binding_count_budget_exceeded')
    }

    $seenRoles = @{}
    $seenPointers = @{}
    foreach ($binding in @($taskExecutionInput.bindings)) {
        $bindingErrorCount = $inputErrors.Count
        if ($null -eq $binding -or $binding -is [string] -or
            $binding -is [ValueType]) {
            $inputErrors.Add('binding_must_be_object')
            continue
        }
        $role = [string]$binding.role
        $adapter = [string]$binding.adapter
        $sourcePointer = [string]$binding.source_pointer
        $allowedBindingFields = @(
            'role', 'adapter', 'source_pointer', 'value', 'expected_digest'
        )
        foreach ($field in @($binding.PSObject.Properties.Name)) {
            if ([string]$field -notin $allowedBindingFields) {
                $inputErrors.Add("binding_field_not_allowed:${role}:$field")
            }
        }
        foreach ($field in @('role', 'adapter', 'source_pointer')) {
            if ($field -notin @($binding.PSObject.Properties.Name)) {
                $inputErrors.Add("binding_field_missing:${role}:$field")
            }
        }
        if ([string]::IsNullOrWhiteSpace($role)) {
            $inputErrors.Add('binding_role_missing')
            continue
        }
        if ($seenRoles.ContainsKey($role)) {
            $inputErrors.Add("binding_role_duplicate:$role")
            continue
        }
        $seenRoles[$role] = $true
        $presentRoles.Add($role)
        if ($role -notin $requiredRoles) {
            $inputErrors.Add("binding_role_not_required:$role")
        }
        if ([string]::IsNullOrWhiteSpace($sourcePointer)) {
            $inputErrors.Add("binding_source_pointer_missing:$role")
        }
        elseif ($seenPointers.ContainsKey($sourcePointer)) {
            $inputErrors.Add("binding_source_pointer_duplicate:$role")
        }
        else {
            $seenPointers[$sourcePointer] = $true
        }
        if ($adapter -notin @('current_turn_inline', 'workspace_artifact')) {
            $inputErrors.Add("binding_adapter_unsupported:$role")
        }
        if ($role -in $workspaceRequiredRoles -and
            $adapter -ne 'workspace_artifact') {
            $inputErrors.Add("workspace_artifact_required:$role")
        }

        $value = $null
        $digest = ''
        $utf8Bytes = 0
        $bindingStatus = 'invalid'
        if ($adapter -eq 'current_turn_inline') {
            $expectedPointer = "current_turn:${currentTurnId}:$role"
            if ($sourcePointer -cne $expectedPointer) {
                $inputErrors.Add("current_turn_source_pointer_mismatch:$role")
            }
            if ($null -ne $binding.PSObject.Properties['expected_digest']) {
                $inputErrors.Add("inline_expected_digest_not_allowed:$role")
            }
            if ($null -eq $binding.PSObject.Properties['value'] -or
                -not (Test-ContentValuePresent -Value $binding.value)) {
                $inputErrors.Add("binding_value_missing:$role")
            }
            else {
                $value = $binding.value
                $valueText = Get-ValueText -Value $value
                $digest = Get-TextDigest -Text $valueText
                $utf8Bytes = [Text.UTF8Encoding]::new($false).
                    GetByteCount($valueText)
                if ($utf8Bytes -gt $maxBindingBytes) {
                    $inputErrors.Add("binding_input_budget_exceeded:$role")
                }
            }
        }
        elseif ($adapter -eq 'workspace_artifact') {
            if ($null -ne $binding.PSObject.Properties['value']) {
                $inputErrors.Add("workspace_embedded_value_not_allowed:$role")
            }
            if ([IO.Path]::IsPathRooted($sourcePointer)) {
                $inputErrors.Add("workspace_pointer_must_be_relative:$role")
            }
            $artifactPath = $null
            if (-not [IO.Path]::IsPathRooted($sourcePointer) -and
                -not [string]::IsNullOrWhiteSpace($sourcePointer)) {
                try {
                    $artifactPath = Get-ContainedPath -Base $rootFull `
                        -Candidate $sourcePointer
                }
                catch {
                    if ($_.Exception.Message -match 'reparse point') {
                        $inputErrors.Add("workspace_pointer_reparse_point:$role")
                    }
                    else {
                        $inputErrors.Add("workspace_pointer_outside_root:$role")
                    }
                }
            }
            $expectedDigest = [string]$binding.expected_digest
            if ($expectedDigest -notmatch '^sha256:[0-9a-f]{64}$') {
                $inputErrors.Add("workspace_expected_digest_invalid:$role")
            }
            if ($null -ne $artifactPath -and
                -not (Test-Path -LiteralPath $artifactPath -PathType Leaf)) {
                $inputErrors.Add("workspace_artifact_missing:$role")
            }
            elseif ($null -ne $artifactPath -and
                (Get-Item -LiteralPath $artifactPath).Length -gt
                    $maxBindingBytes) {
                $utf8Bytes = [int64](Get-Item -LiteralPath $artifactPath).Length
                $inputErrors.Add("binding_input_budget_exceeded:$role")
            }
            elseif ($null -ne $artifactPath) {
                $actualDigest = Get-FileDigest -Path $artifactPath
                if ($actualDigest -cne $expectedDigest) {
                    $staleInputs.Add($role)
                }
                else {
                    $value = [IO.File]::ReadAllText(
                        $artifactPath,
                        [Text.UTF8Encoding]::new($false)
                    )
                    $digest = $actualDigest
                    $utf8Bytes = [Text.UTF8Encoding]::new($false).
                        GetByteCount([string]$value)
                }
            }
        }

        if ($null -ne $value) {
            $roleContract = $inputContract.role_contracts.PSObject.Properties |
                Where-Object Name -eq $role |
                Select-Object -ExpandProperty Value -First 1
            if ($null -ne $roleContract -and
                -not (Test-RoleValueContract -Role $role -Value $value `
                    -Contract $roleContract)) {
                $inputErrors.Add("binding_role_contract_mismatch:$role")
            }
        }
        $totalBindingBytes += [int64]$utf8Bytes

        if ($inputErrors.Count -eq $bindingErrorCount -and
            $role -notin $staleInputs) {
            $bindingStatus = 'covered'
            $inputValues[$role] = $value
        }
        elseif ($role -in $staleInputs) {
            $bindingStatus = 'stale'
        }
        $bindingRows.Add([ordered]@{
            role = $role
            adapter = $adapter
            source_pointer = $sourcePointer
            digest = $digest
            utf8_bytes = $utf8Bytes
            status = $bindingStatus
        })
    }
    if ($totalBindingBytes -gt $maxTotalBindingBytes) {
        $inputErrors.Add('total_binding_input_budget_exceeded')
    }
}

$missing = @(
    $requiredRoles | Where-Object { $_ -notin @($presentRoles) }
)
$coveredRequiredCount = @(
    $bindingRows | Where-Object {
        [string]$_.status -eq 'covered' -and
        [string]$_.role -in $requiredRoles
    }
).Count

$checkpointErrors = [Collections.Generic.List[string]]::new()
$checkpointProjection = $null
if ($TaskKind -eq 'thread_recovery' -and
    $inputValues.Contains('checkpoint_pointer')) {
    $parsedCheckpoint = Get-CheckpointProjection -Text (
        [string]$inputValues['checkpoint_pointer']
    )
    if (-not [bool]$parsedCheckpoint.valid) {
        $checkpointErrors.Add('checkpoint_frontmatter_invalid')
    }
    else {
        $checkpointFields = $parsedCheckpoint.fields
        if ([string]$checkpointFields.schema -ne 'contentos-checkpoint-v1') {
            $checkpointErrors.Add('checkpoint_schema_mismatch')
        }
        if ([string]$checkpointFields.status -notin @('active', 'resumable')) {
            $checkpointErrors.Add('checkpoint_status_not_resumable')
        }
        foreach ($field in @('task_kind', 'current_stage')) {
            if ([string]::IsNullOrWhiteSpace([string]$checkpointFields[$field])) {
                $checkpointErrors.Add("checkpoint_field_missing:$field")
            }
        }
        $checkpointProjection = [ordered]@{
            schema = [string]$checkpointFields.schema
            status = [string]$checkpointFields.status
            task_kind = [string]$checkpointFields.task_kind
            current_stage = [string]$checkpointFields.current_stage
        }
    }
}

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
        $bindingInput -notin $requiredRoles) {
        $adapterErrors.Add('profile_adapter_binding_input_invalid')
    }
    elseif (-not $inputValues.Contains($bindingInput)) {
        $adapterErrors.Add('adapter_binding_missing')
    }
    else {
        $binding = $inputValues[$bindingInput]
        $bindingProperties = if ($null -ne $binding) {
            @($binding.PSObject.Properties.Name)
        }
        else { @() }
        $allowedAdapterFields = @(
            'schema', 'adapter_id', 'version', 'task_kind', 'read_scope',
            'write_scope', 'authorization', 'retry_semantics',
            'output_schema', 'readback'
        )
        foreach ($field in $bindingProperties) {
            if ([string]$field -notin $allowedAdapterFields) {
                $adapterErrors.Add("adapter_field_not_allowed:$field")
            }
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
            'version', 'authorization', 'retry_semantics', 'output_schema',
            'readback'
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
    $adapterContract.status = if ($adapterErrors.Count -eq 0) {
        'structurally_valid_untrusted'
    }
    else { 'invalid' }
    $adapterContract.errors = @($adapterErrors)
}

$ruleRows = [Collections.Generic.List[object]]::new()
$totalBytes = 0
foreach ($relativeRule in @($taskProfile.rule_files)) {
    $rulePath = Get-ContainedPath -Base $rootFull -Candidate ([string]$relativeRule)
    if (-not (Test-Path -LiteralPath $rulePath -PathType Leaf)) {
        throw "Rule file missing: $relativeRule"
    }
    $content = [IO.File]::ReadAllText(
        $rulePath,
        [Text.UTF8Encoding]::new($false)
    )
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
elseif ('legacy_inputs_json_not_authoritative' -in $inputErrors) {
    'blocked_legacy_input_interface'
}
elseif ('task_execution_input_missing' -in $inputErrors) {
    'blocked_missing_task_execution_input'
}
elseif (@($inputErrors | Where-Object { $_ -match 'budget_exceeded' }).Count -gt 0) {
    'blocked_input_budget'
}
elseif ($missing.Count -gt 0) {
    'blocked_missing_inputs'
}
elseif ($staleInputs.Count -gt 0) {
    'blocked_stale_inputs'
}
elseif ($checkpointErrors.Count -gt 0) {
    'blocked_checkpoint_contract'
}
elseif ($inputErrors.Count -gt 0) {
    'blocked_input_contract'
}
elseif ($adapterErrors.Count -gt 0) {
    'blocked_adapter_contract'
}
elseif ([string]$taskProfile.implementation -eq 'public_adapter') {
    'ready_adapter_pending_host_authority'
}
else {
    'ready'
}

$capabilityRows = @(
    $capabilityMap.capabilities | Where-Object task_kind -eq $TaskKind
)
if ($capabilityRows.Count -ne 1) {
    throw "Capability map mismatch for TaskKind: $TaskKind"
}
$capability = $capabilityRows[0]

$qualityGateProjection = $null
if (@($taskProfile.quality_gates).Count -gt 0) {
    $qualityTool = Get-ContainedPath -Base $rootFull `
        -Candidate ([string]$manifest.quality_gate_interface.tool)
    if (-not (Test-Path -LiteralPath $qualityTool -PathType Leaf)) {
        throw "Quality gate tool missing: $qualityTool"
    }
    $allTaskGates = @(
        $taskProfile.quality_gates | ForEach-Object { [string]$_ }
    )
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
        observation_authority = [string](
            $manifest.quality_gate_interface.observation_authority
        )
        side_effects = [string]$manifest.quality_gate_interface.side_effects
    }
}

$admissionView = $null
if ($status -in @('ready', 'ready_adapter_pending_host_authority')) {
    $admissionView = [ordered]@{
        scope_id = [string]$taskExecutionInput.scope_id
        current_turn_id = [string]$taskExecutionInput.current_turn_id
        task_kind = $TaskKind
        task_stage = [string]$taskProfile.task_stage
        track = [string]$taskProfile.track
        objective = [string]$taskProfile.objective
        implementation = [string]$taskProfile.implementation
        adapter_id = if ($null -ne $taskProfile.adapter_id) {
            [string]$taskProfile.adapter_id
        }
        else { $null }
        adapter_binding_input = if ($null -ne $taskProfile.adapter_binding_input) {
            [string]$taskProfile.adapter_binding_input
        }
        else { $null }
        inputs = $inputValues
        authoritative_input_bindings = @($bindingRows)
        flexible_budget_state = $budgetState
        hydrated_rules = $ruleRows
        quality_gate_interface = $qualityGateProjection
    }
}
$generatorView = if ($status -eq 'ready') { $admissionView } else { $null }

$closureComplete = (
    $missing.Count -eq 0 -and
    $staleInputs.Count -eq 0 -and
    $inputErrors.Count -eq 0 -and
    $checkpointErrors.Count -eq 0
)
$recoveryStatus = if ($TaskKind -eq 'thread_recovery' -and
    $status -eq 'ready') {
    'resumable'
}
elseif ($TaskKind -eq 'thread_recovery') {
    'blocked'
}
else {
    'not_applicable'
}

$envelope = [ordered]@{
    schema = 'contentos-startup-envelope-v1'
    release_id = [string]$manifest.release_id
    status = $status
    generation_allowed = ($status -eq 'ready')
    generation_scope = if ($status -eq 'ready') {
        'current_task_kind_only'
    }
    else { 'none' }
    active_profile = $Profile
    recovery = [ordered]@{
        status = $recoveryStatus
        checkpoint = $checkpointProjection
        errors = @($checkpointErrors)
    }
    task_execution = [ordered]@{
        status = if ($status -eq 'ready') {
            'ready'
        }
        elseif ($status -eq 'ready_adapter_pending_host_authority') {
            'waiting_host_authority'
        }
        else { 'blocked' }
        input_closure = [ordered]@{
            status = if ($closureComplete) { 'complete' } else { 'incomplete' }
            required_count = $requiredRoles.Count
            covered_count = $coveredRequiredCount
            missing = $missing
            stale = @($staleInputs)
            errors = @($inputErrors)
            task_execution_input_digest = $taskExecutionInputDigest
            bindings = @($bindingRows)
            budget = [ordered]@{
                task_execution_input_utf8_bytes = $taskExecutionInputBytes
                total_binding_utf8_bytes = $totalBindingBytes
                max_task_execution_input_utf8_bytes = $maxTaskInputBytes
                max_binding_utf8_bytes = $maxBindingBytes
                max_total_binding_utf8_bytes = $maxTotalBindingBytes
                max_binding_count = $maxBindingCount
            }
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
        adapter_id = if ($null -ne $taskProfile.adapter_id) {
            [string]$taskProfile.adapter_id
        }
        else { $null }
        adapter_binding_input = if ($null -ne $taskProfile.adapter_binding_input) {
            [string]$taskProfile.adapter_binding_input
        }
        else { $null }
        parity = [string]$capability.parity
        required_inputs = $requiredRoles
        workspace_required_inputs = $workspaceRequiredRoles
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
    admission_view = $admissionView
    generator_view = $generatorView
}

if ($Pretty) {
    $envelope | ConvertTo-Json -Depth 30
}
else {
    $envelope | ConvertTo-Json -Depth 30 -Compress
}
