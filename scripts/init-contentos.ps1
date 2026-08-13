[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Destination,

    [ValidateSet('full', 'lite')]
    [string]$Profile = 'full',

    [string]$SourceRoot,

    [switch]$Pretty
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($SourceRoot)) {
    $SourceRoot = Split-Path -Parent $PSScriptRoot
}

$sourceFull = [IO.Path]::GetFullPath($SourceRoot).TrimEnd('\', '/')
$destinationFull = [IO.Path]::GetFullPath($Destination).TrimEnd('\', '/')
$sourcePrefix = $sourceFull + [IO.Path]::DirectorySeparatorChar
if (
    $destinationFull -eq $sourceFull -or
    $destinationFull.StartsWith($sourcePrefix, [StringComparison]::OrdinalIgnoreCase)
) {
    throw 'Destination must be outside the release source directory'
}

$profiles = Get-Content -LiteralPath (Join-Path $sourceFull 'core\profiles\task-profiles.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if (@($profiles.install_profiles | Where-Object profile_id -eq $Profile).Count -ne 1) {
    throw "Unknown ContentOS install profile: $Profile"
}

$existingConfigPath = Join-Path $destinationFull '.contentos\config.json'
if (Test-Path -LiteralPath $existingConfigPath -PathType Leaf) {
    $existingConfig = Get-Content -LiteralPath $existingConfigPath -Raw `
        -Encoding UTF8 | ConvertFrom-Json
    $receipt = [ordered]@{
        schema = 'contentos-init-receipt-v1'
        status = 'existing_instance_unchanged'
        release_id = [string]$profiles.release_id
        installed_release_id = [string]$existingConfig.release_id
        update_required = (
            [string]$existingConfig.release_id -ne [string]$profiles.release_id
        )
        profile_id = [string]$existingConfig.active_profile
        requested_profile_id = $Profile
        destination = $destinationFull
        created_count = 0
        skipped_count = 0
        created = @()
        skipped = @()
        network_calls = 0
        model_installs = 0
        account_actions = 0
        publish_actions = 0
        user_content_overwritten = $false
        note = 'init is create-only; use a reviewed update workflow for existing instances'
    }
    if ($Pretty) { $receipt | ConvertTo-Json -Depth 6 }
    else { $receipt | ConvertTo-Json -Depth 6 -Compress }
    return
}

$existingIgnorePath = Join-Path $destinationFull '.gitignore'
if (Test-Path -LiteralPath $existingIgnorePath -PathType Leaf) {
    $existingIgnore = Get-Content -LiteralPath $existingIgnorePath -Raw `
        -Encoding UTF8
    if ($existingIgnore -notmatch '(?m)^/vault/$' -or
        $existingIgnore -notmatch '(?m)^/\.contentos/config\.json$') {
        throw (
            'Existing destination .gitignore must ignore /vault/ and ' +
            '/.contentos/config.json before initialization'
        )
    }
}

$created = [Collections.Generic.List[string]]::new()
$skipped = [Collections.Generic.List[string]]::new()

function Ensure-Directory {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        [void](New-Item -ItemType Directory -Path $Path -Force)
    }
}

function Get-RelativeTarget {
    param([string]$Target)
    return $Target.Substring($destinationFull.Length).TrimStart('\', '/').Replace('\', '/')
}

function Copy-NewFile {
    param([string]$Source, [string]$Target)

    Ensure-Directory -Path (Split-Path -Parent $Target)
    $relativeTarget = Get-RelativeTarget -Target $Target
    if (Test-Path -LiteralPath $Target) {
        $skipped.Add($relativeTarget)
        return
    }
    [IO.File]::WriteAllBytes($Target, [IO.File]::ReadAllBytes($Source))
    $created.Add($relativeTarget)
}

function Copy-NewTree {
    param([string]$SourceDirectory, [string]$TargetDirectory)

    foreach ($file in Get-ChildItem -LiteralPath $SourceDirectory -Recurse -File -Force) {
        $relative = $file.FullName.Substring($SourceDirectory.Length).TrimStart('\', '/')
        Copy-NewFile -Source $file.FullName -Target (Join-Path $TargetDirectory $relative)
    }
}

Ensure-Directory -Path $destinationFull

foreach ($name in @(
    'README.md', 'AGENTS.md', '.gitattributes', 'LICENSE',
    'LICENSE-CODE', 'LICENSE-DOCS.md', 'THIRD-PARTY-NOTICES.md',
    'CONTRIBUTING.md', 'SECURITY.md', 'MANIFEST.json'
)) {
    $source = Join-Path $sourceFull $name
    if (Test-Path -LiteralPath $source -PathType Leaf) {
        Copy-NewFile -Source $source -Target (Join-Path $destinationFull $name)
    }
}

$instanceIgnorePath = Join-Path $destinationFull '.gitignore'
if (Test-Path -LiteralPath $instanceIgnorePath -PathType Leaf) {
    $skipped.Add('.gitignore')
}
else {
    $sourceIgnore = [IO.File]::ReadAllText(
        (Join-Path $sourceFull '.gitignore'),
        [Text.UTF8Encoding]::new($false)
    ).Replace("`r`n", "`n").Replace("`r", "`n").TrimEnd("`n")
    $instanceIgnore = $sourceIgnore + "`n`n" +
        '# Instance-private ContentOS state' + "`n" +
        '/vault/' + "`n" +
        '/.contentos/config.json' + "`n"
    [IO.File]::WriteAllText(
        $instanceIgnorePath,
        $instanceIgnore,
        [Text.UTF8Encoding]::new($false)
    )
    $created.Add('.gitignore')
}

foreach ($directory in @('.agents', '.github', 'core', 'templates', 'scripts', 'tests', 'docs', 'config')) {
    $sourceDirectory = Join-Path $sourceFull $directory
    if (Test-Path -LiteralPath $sourceDirectory -PathType Container) {
        Copy-NewTree -SourceDirectory $sourceDirectory -TargetDirectory (Join-Path $destinationFull $directory)
    }
}
Copy-NewTree -SourceDirectory (Join-Path $sourceFull 'vault-template') -TargetDirectory (Join-Path $destinationFull 'vault')

$instanceConfigPath = Join-Path $destinationFull '.contentos\config.json'
Ensure-Directory -Path (Split-Path -Parent $instanceConfigPath)
if (Test-Path -LiteralPath $instanceConfigPath -PathType Leaf) {
    $skipped.Add('.contentos/config.json')
}
else {
    $config = Get-Content -LiteralPath (Join-Path $sourceFull 'config\contentos.example.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $config.active_profile = $Profile
    $configJson = ($config | ConvertTo-Json -Depth 8).
        Replace("`r`n", "`n").Replace("`r", "`n")
    [IO.File]::WriteAllText(
        $instanceConfigPath,
        $configJson + "`n",
        [Text.UTF8Encoding]::new($false)
    )
    $created.Add('.contentos/config.json')
}

$receipt = [ordered]@{
    schema = 'contentos-init-receipt-v1'
    status = 'initialized'
    release_id = [string]$profiles.release_id
    profile_id = $Profile
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
    privacy_defaults_applied = $true
    update_performed = $false
}

if ($Pretty) {
    $receipt | ConvertTo-Json -Depth 6
}
else {
    $receipt | ConvertTo-Json -Depth 6 -Compress
}
