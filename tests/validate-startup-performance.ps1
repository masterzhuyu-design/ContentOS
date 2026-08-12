[CmdletBinding()]
param([string]$Root)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Split-Path -Parent $PSScriptRoot
}
$resolver = Join-Path $Root 'scripts\resolve-contentos-startup.ps1'
$inputs = @{ query = 'fixture'; source_scope = 'anonymous-fixture' } |
    ConvertTo-Json -Compress
$durations = [Collections.Generic.List[double]]::new()

for ($index = 0; $index -lt 3; $index++) {
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $result = & $resolver -Root $Root -Profile full -TaskKind knowledge_query `
        -InputsJson $inputs | ConvertFrom-Json
    $watch.Stop()
    $durations.Add($watch.Elapsed.TotalMilliseconds)
    if ([string]$result.status -ne 'ready' -or
        @($result.hydration.rules).Count -eq 0) {
        "FAIL: startup result invalid on run $index"
        exit 1
    }
}

$max = ($durations | Measure-Object -Maximum).Maximum
$average = ($durations | Measure-Object -Average).Average
if ($max -gt 5000) {
    "FAIL: startup exceeded 5000ms ceiling ($([Math]::Round($max, 2))ms)"
    exit 1
}
"SUMMARY: startup performance passed (avg=$([Math]::Round($average, 2))ms max=$([Math]::Round($max, 2))ms)"
