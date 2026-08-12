[CmdletBinding()]
param([string]$Root)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Split-Path -Parent $PSScriptRoot
}
$validator = Join-Path $Root 'scripts\validate-package-sanitization.ps1'
$includeGitHistory = Test-Path -LiteralPath (Join-Path $Root '.git') -PathType Container
$result = & $validator -Root $Root -IncludeGitHistory:$includeGitHistory |
    ConvertFrom-Json
if ([string]$result.status -ne 'passed' -or [int]$result.failure_count -ne 0) {
    @($result.failures) | ForEach-Object { "FAIL: $_" }
    'SUMMARY: no-private-state validation failed'
    exit 1
}
$historySummary = if ($result.history_scanned -and $result.index_scanned) {
    ", $($result.index_blob_count) staged blobs, " +
        "$($result.history_blob_count) historical blobs"
}
else {
    ', no Git history in installed fixture'
}
"SUMMARY: no-private-state validation passed ($($result.file_count) files$historySummary)"
