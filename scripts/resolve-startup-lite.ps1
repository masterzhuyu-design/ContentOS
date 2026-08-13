[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$TaskKind,
    [string]$TaskExecutionInputJson = '',
    [string]$InputsJson = '',
    [string]$Root,
    [switch]$Pretty
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Split-Path -Parent $PSScriptRoot
}

$arguments = @{
    TaskKind = $TaskKind
    TaskExecutionInputJson = $TaskExecutionInputJson
    InputsJson = $InputsJson
    Profile = 'lite'
    Root = $Root
    Pretty = $Pretty
}
& (Join-Path $PSScriptRoot 'resolve-contentos-startup.ps1') @arguments
