[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ObservationJson,

    [string]$Root,

    [switch]$Pretty
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Split-Path -Parent $PSScriptRoot
}

$canonical = Join-Path $PSScriptRoot 'evaluate-contentos-quality-gate.ps1'
& $canonical -ObservationJson $ObservationJson -Root $Root -Pretty:$Pretty
exit $LASTEXITCODE
