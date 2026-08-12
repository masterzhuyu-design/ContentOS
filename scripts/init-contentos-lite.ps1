[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Destination,
    [string]$SourceRoot,
    [switch]$Pretty
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($SourceRoot)) {
    $SourceRoot = Split-Path -Parent $PSScriptRoot
}

$arguments = @{
    Destination = $Destination
    SourceRoot = $SourceRoot
    Profile = 'lite'
    Pretty = $Pretty
}
& (Join-Path $PSScriptRoot 'init-contentos.ps1') @arguments
