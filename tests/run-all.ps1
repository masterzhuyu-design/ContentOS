[CmdletBinding()]
param([string]$Root)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Split-Path -Parent $PSScriptRoot
}
$Root = [IO.Path]::GetFullPath($Root)
$engine = (Get-Process -Id $PID).Path
$tests = @(
    'tests\validate-powershell-syntax.ps1',
    'tests\validate-core-contract.ps1',
    'tests\validate-public-capability-coverage.ps1',
    'tests\validate-functional-parity.ps1',
    'tests\validate-problem-regression-scenarios.ps1',
    'tests\validate-task-budgets.ps1',
    'tests\validate-startup-performance.ps1',
    'tests\validate-no-private-state.ps1',
    'tests\validate-release-manifest.ps1',
    'tests\validate-clean-install.ps1'
)
$failures = [Collections.Generic.List[string]]::new()

foreach ($relative in $tests) {
    Write-Output "RUN: $relative"
    $path = Join-Path $Root $relative
    $output = & $engine -NoProfile -NonInteractive -ExecutionPolicy Bypass `
        -File $path -Root $Root 2>&1
    $exitCode = $LASTEXITCODE
    $output | ForEach-Object { Write-Output $_ }
    if ($exitCode -ne 0) {
        $failures.Add("$relative (exit $exitCode)")
    }
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { "FAIL: $_" }
    "SUMMARY: ContentOS validation suite failed ($($failures.Count) tests)"
    exit 1
}
"SUMMARY: ContentOS validation suite passed ($($tests.Count) tests)"
