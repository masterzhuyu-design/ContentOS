[CmdletBinding()]
param(
    [string]$Root,
    [switch]$Pretty
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Split-Path -Parent $PSScriptRoot
}
$rootFull = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
$manifestPath = Join-Path $rootFull 'MANIFEST.json'

$rows = @(
    Get-ChildItem -LiteralPath $rootFull -Recurse -File -Force |
        Where-Object {
            $candidateRelative = $_.FullName.Substring($rootFull.Length).
                TrimStart('\', '/').Replace('\', '/')
            $_.FullName -ne $manifestPath -and
                $candidateRelative -ne '.git' -and
                -not $candidateRelative.StartsWith(
                    '.git/',
                    [StringComparison]::OrdinalIgnoreCase
                )
        } |
        ForEach-Object {
            $relative = $_.FullName.Substring($rootFull.Length).
                TrimStart('\', '/').Replace('\', '/')
            $licenseClass = if (
                $relative -match
                    '^(scripts|tests|config|\.github|core/(schemas|profiles|capabilities|upgrades))/' -or
                $relative -in @('LICENSE', 'LICENSE-CODE')
            ) {
                'MIT'
            }
            elseif ($relative -match '^vault-template/.+\.gitkeep$') {
                'empty_directory_marker'
            }
            else {
                'CC-BY-SA-4.0'
            }
            [ordered]@{
                path = $relative
                bytes = [int64]$_.Length
                sha256 = (
                    Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256
                ).Hash.ToLowerInvariant()
                license_class = $licenseClass
            }
        } |
        Sort-Object path
)

$manifest = [ordered]@{
    schema = 'contentos-package-manifest-v1'
    release_id = 'contentos-v0.2.0-rc.1'
    generated_at = (Get-Date).ToString('o')
    manifest_self_excluded = $true
    file_count = $rows.Count
    total_bytes = [int64](
        $rows |
            ForEach-Object { [int64]$_['bytes'] } |
            Measure-Object -Sum
    ).Sum
    files = $rows
}

$json = if ($Pretty) {
    $manifest | ConvertTo-Json -Depth 7
}
else {
    $manifest | ConvertTo-Json -Depth 7 -Compress
}
$json = $json.Replace("`r`n", "`n").Replace("`r", "`n")
[IO.File]::WriteAllText(
    $manifestPath,
    $json + "`n",
    [Text.UTF8Encoding]::new($false)
)

[ordered]@{
    schema = 'contentos-manifest-build-receipt-v1'
    status = 'built'
    manifest_path = $manifestPath
    file_count = $rows.Count
    total_bytes = $manifest.total_bytes
    manifest_sha256 = (
        Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256
    ).Hash.ToLowerInvariant()
} | ConvertTo-Json -Depth 4 -Compress
