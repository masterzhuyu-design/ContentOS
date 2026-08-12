[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$TaskKind,
    [string]$InputsJson = '{}',
    [string]$Root,
    [switch]$Pretty
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Split-Path -Parent $PSScriptRoot
}

$arguments = @{
    TaskKind = $TaskKind
    InputsJson = $InputsJson
    Profile = 'lite'
    Root = $Root
    Pretty = $Pretty
}
& (Join-Path $PSScriptRoot 'resolve-contentos-startup.ps1') @arguments
