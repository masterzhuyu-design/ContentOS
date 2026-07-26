[CmdletBinding()]
param([string]$Root = (Split-Path -Parent $PSScriptRoot))

$ErrorActionPreference = 'Stop'
$validator = Join-Path $Root 'scripts\validate-package-sanitization.ps1'
$result = & $validator -Root $Root | ConvertFrom-Json
if ($result.status -ne 'passed' -or [int]$result.failure_count -ne 0) {
    @($result.failures) | ForEach-Object { "FAIL: $_" }
    "FAIL: sanitization did not pass"
    exit 1
}
"SUMMARY: no-private-state validation passed ($($result.file_count) files)"
