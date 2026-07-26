[CmdletBinding()]
param(
    [string]$Root = (Split-Path -Parent $PSScriptRoot),
    [int]$MaximumMilliseconds = 3000,
    [int]$MaximumOutputCharacters = 100000
)

$ErrorActionPreference = 'Stop'
$stopwatch = [Diagnostics.Stopwatch]::StartNew()
$output = & (Join-Path $Root 'scripts\resolve-startup-lite.ps1') `
    -Root $Root `
    -TaskKind 'thread_recovery_lite'
$stopwatch.Stop()

$text = [string]$output
$failures = [Collections.Generic.List[string]]::new()
if ($stopwatch.ElapsedMilliseconds -gt $MaximumMilliseconds) {
    $failures.Add(
        "startup_too_slow:$($stopwatch.ElapsedMilliseconds)ms"
    )
}
if ($text.Length -gt $MaximumOutputCharacters) {
    $failures.Add("startup_output_too_large:$($text.Length)")
}
try {
    $parsed = $text | ConvertFrom-Json
    if ($parsed.task.kind -ne 'thread_recovery_lite') {
        $failures.Add('startup_task_kind_mismatch')
    }
}
catch {
    $failures.Add("startup_output_invalid_json:$($_.Exception.Message)")
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { "FAIL: $_" }
    "SUMMARY: startup performance validation failed"
    exit 1
}

"SUMMARY: startup performance validation passed ($($stopwatch.ElapsedMilliseconds)ms / $($text.Length) chars)"
