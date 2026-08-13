[CmdletBinding()]
param([string]$Root)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Split-Path -Parent $PSScriptRoot
}
$failures = [Collections.Generic.List[string]]::new()
$rows = [Collections.Generic.List[object]]::new()
$manifest = Get-Content -LiteralPath (
    Join-Path $Root 'core\profiles\task-profiles.json'
) -Raw -Encoding UTF8 | ConvertFrom-Json
$resolver = Join-Path $Root 'scripts\resolve-contentos-startup.ps1'

foreach ($profile in @($manifest.profiles)) {
    $result = & $resolver -Root $Root -Profile full `
        -TaskKind ([string]$profile.task_kind) |
        ConvertFrom-Json
    $bytes = [int]$result.hydration.total_utf8_bytes
    $soft = [int]$profile.budget.soft_target_utf8_bytes
    $advisory = [int]$profile.budget.advisory_ceiling_utf8_bytes
    $hard = [int]$profile.budget.hard_safety_ceiling_utf8_bytes
    $rows.Add([ordered]@{
        task_kind = [string]$profile.task_kind
        utf8_bytes = $bytes
        soft_target = $soft
        advisory_ceiling = $advisory
        hard_safety_ceiling = $hard
        state = [string]$result.hydration.budget.state
    })
    if ($bytes -gt $advisory) {
        $failures.Add("shipped_bundle_exceeds_advisory:$($profile.task_kind):$bytes")
    }
    if ($bytes -gt $hard -or [string]$result.status -eq 'blocked_budget_overflow') {
        $failures.Add("shipped_bundle_exceeds_hard:$($profile.task_kind):$bytes")
    }
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { "FAIL: $_" }
    "SUMMARY: task budget validation failed ($($failures.Count))"
    exit 1
}
"SUMMARY: task budget validation passed ($($rows.Count) profiles)"
