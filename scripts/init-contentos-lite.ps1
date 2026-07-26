[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Destination,

    [string]$SourceRoot = (Split-Path -Parent $PSScriptRoot),

    [switch]$Pretty
)

$ErrorActionPreference = 'Stop'

$sourceFull = [IO.Path]::GetFullPath($SourceRoot).TrimEnd('\', '/')
$destinationFull = [IO.Path]::GetFullPath($Destination).TrimEnd('\', '/')
$sourcePrefix = $sourceFull + [IO.Path]::DirectorySeparatorChar
if (
    $destinationFull -eq $sourceFull -or
    $destinationFull.StartsWith(
        $sourcePrefix,
        [StringComparison]::OrdinalIgnoreCase
    )
) {
    throw 'Destination must be outside the release source directory'
}

$created = [Collections.Generic.List[string]]::new()
$skipped = [Collections.Generic.List[string]]::new()

function Ensure-Directory {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        [void](New-Item -ItemType Directory -Path $Path -Force)
    }
}

function Copy-NewFile {
    param(
        [string]$Source,
        [string]$Target
    )

    Ensure-Directory -Path (Split-Path -Parent $Target)
    $relativeTarget = $Target.Substring($destinationFull.Length).
        TrimStart('\', '/').Replace('\', '/')
    if (Test-Path -LiteralPath $Target) {
        $skipped.Add($relativeTarget)
        return
    }
    [IO.File]::WriteAllBytes($Target, [IO.File]::ReadAllBytes($Source))
    $created.Add($relativeTarget)
}

function Copy-NewTree {
    param(
        [string]$SourceDirectory,
        [string]$TargetDirectory
    )

    foreach ($file in Get-ChildItem `
        -LiteralPath $SourceDirectory `
        -Recurse `
        -File `
        -Force) {
        $relative = $file.FullName.Substring(
            $SourceDirectory.Length
        ).TrimStart('\', '/')
        Copy-NewFile `
            -Source $file.FullName `
            -Target (Join-Path $TargetDirectory $relative)
    }
}

Ensure-Directory -Path $destinationFull

foreach ($name in @(
    'README.md',
    'AGENTS.md',
    '.gitattributes',
    '.gitignore',
    'LICENSE-CODE',
    'LICENSE-DOCS.md',
    'THIRD-PARTY-NOTICES.md',
    'MANIFEST.json'
)) {
    Copy-NewFile `
        -Source (Join-Path $sourceFull $name) `
        -Target (Join-Path $destinationFull $name)
}

foreach ($directory in @('core', 'templates', 'scripts', 'tests', 'docs')) {
    Copy-NewTree `
        -SourceDirectory (Join-Path $sourceFull $directory) `
        -TargetDirectory (Join-Path $destinationFull $directory)
}

Copy-NewTree `
    -SourceDirectory (Join-Path $sourceFull 'config') `
    -TargetDirectory (Join-Path $destinationFull 'config')
Copy-NewFile `
    -Source (Join-Path $sourceFull 'config\contentos.example.json') `
    -Target (Join-Path $destinationFull '.contentos\config.json')
Copy-NewTree `
    -SourceDirectory (Join-Path $sourceFull 'vault-template') `
    -TargetDirectory (Join-Path $destinationFull 'vault')

$receipt = [ordered]@{
    schema = 'contentos-lite-init-receipt-v1'
    status = 'initialized'
    destination = $destinationFull
    created_count = $created.Count
    skipped_count = $skipped.Count
    created = @($created)
    skipped = @($skipped)
    network_calls = 0
    model_installs = 0
    account_actions = 0
    publish_actions = 0
    user_content_overwritten = $false
}

if ($Pretty) {
    $receipt | ConvertTo-Json -Depth 6
}
else {
    $receipt | ConvertTo-Json -Depth 6 -Compress
}
