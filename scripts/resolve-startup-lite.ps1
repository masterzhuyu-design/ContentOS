[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$TaskKind,

    [string]$InputsJson = '{}',

    [string]$Root = (Split-Path -Parent $PSScriptRoot),

    [switch]$Pretty
)

$ErrorActionPreference = 'Stop'

function Get-ContainedPath {
    param(
        [string]$Base,
        [string]$Candidate
    )

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
        throw "Path escapes ContentOS Lite root: $Candidate"
    }
    return $candidateFull
}

function Get-TextDigest {
    param([string]$Text)

    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))
    }
    finally {
        $sha.Dispose()
    }
    return 'sha256:' + (($hash | ForEach-Object {
        $_.ToString('x2')
    }) -join '')
}

$rootFull = Get-ContainedPath -Base $Root -Candidate $Root
$profilePath = Get-ContainedPath `
    -Base $rootFull `
    -Candidate 'core/profiles/task-profiles.json'
if (-not (Test-Path -LiteralPath $profilePath -PathType Leaf)) {
    throw "Task profile manifest missing: $profilePath"
}

$manifest = Get-Content -LiteralPath $profilePath -Raw -Encoding UTF8 |
    ConvertFrom-Json
$profiles = @(
    $manifest.profiles |
        Where-Object { [string]$_.task_kind -eq $TaskKind }
)
if ($profiles.Count -ne 1) {
    throw "Unknown or duplicate TaskKind: $TaskKind"
}
$profile = $profiles[0]

try {
    $inputs = $InputsJson | ConvertFrom-Json
}
catch {
    throw "Invalid InputsJson: $($_.Exception.Message)"
}

$inputNames = @($inputs.PSObject.Properties.Name)
$missing = @(
    @($profile.required_inputs) |
        Where-Object {
            $name = [string]$_
            if ($name -notin $inputNames) {
                return $true
            }
            $value = $inputs.$name
            return (
                $null -eq $value -or
                (
                    $value -is [string] -and
                    [string]::IsNullOrWhiteSpace([string]$value)
                )
            )
        }
)

$ruleRows = [Collections.Generic.List[object]]::new()
$totalBytes = 0
foreach ($relativeRule in @($profile.rule_files)) {
    $rulePath = Get-ContainedPath `
        -Base $rootFull `
        -Candidate ([string]$relativeRule)
    if (-not (Test-Path -LiteralPath $rulePath -PathType Leaf)) {
        throw "Rule file missing: $relativeRule"
    }
    $content = [IO.File]::ReadAllText(
        $rulePath,
        [Text.Encoding]::UTF8
    )
    $bytes = [Text.Encoding]::UTF8.GetByteCount($content)
    $totalBytes += $bytes
    $ruleRows.Add([ordered]@{
        path = ([string]$relativeRule).Replace('\', '/')
        utf8_bytes = $bytes
        digest = Get-TextDigest -Text $content
        content = $content
    })
}

$softTarget = [int]$profile.budget.soft_target_utf8_bytes
$advisoryCeiling = [int]$profile.budget.advisory_ceiling_utf8_bytes
$hardCeiling = [int]$profile.budget.hard_safety_ceiling_utf8_bytes
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

$status = if ($budgetState -eq 'blocked_budget_overflow') {
    'blocked_budget_overflow'
}
elseif ($missing.Count -gt 0) {
    'blocked_missing_inputs'
}
else {
    'ready'
}

$qualityGateProjection = $null
$profileQualityGates = @($profile.quality_gates)
if ($profileQualityGates.Count -gt 0) {
    if ($null -eq $manifest.quality_gate_interface) {
        throw 'Quality gate interface missing from task profile manifest'
    }
    $qualityGateTool = Get-ContainedPath `
        -Base $rootFull `
        -Candidate ([string]$manifest.quality_gate_interface.tool)
    if (-not (Test-Path -LiteralPath $qualityGateTool -PathType Leaf)) {
        throw "Quality gate tool missing: $qualityGateTool"
    }
    $qualityGateProjection = [ordered]@{
        tool = [string]$manifest.quality_gate_interface.tool
        input_schema =
            [string]$manifest.quality_gate_interface.input_schema
        output_schema =
            [string]$manifest.quality_gate_interface.output_schema
        gates = $profileQualityGates
        side_effects =
            [string]$manifest.quality_gate_interface.side_effects
    }
}

$generatorView = $null
if ($status -eq 'ready') {
    $generatorView = [ordered]@{
        task_kind = $TaskKind
        objective = [string]$profile.objective
        inputs = $inputs
        flexible_budget_state = $budgetState
        expansion_reason = if ('_expansion_reason' -in $inputNames) {
            [string]$inputs._expansion_reason
        }
        else {
            $null
        }
        hydrated_rules = $ruleRows
        quality_gate_interface = $qualityGateProjection
    }
}

$envelope = [ordered]@{
    schema = 'contentos-lite-startup-envelope-v1'
    profile_id = [string]$manifest.profile_id
    status = $status
    generation_allowed = ($status -eq 'ready')
    task = [ordered]@{
        kind = $TaskKind
        objective = [string]$profile.objective
        required_inputs = @($profile.required_inputs)
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
    $envelope | ConvertTo-Json -Depth 12
}
else {
    $envelope | ConvertTo-Json -Depth 12 -Compress
}
