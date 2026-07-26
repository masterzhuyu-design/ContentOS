[CmdletBinding()]
param(
    [string]$Root = (Split-Path -Parent $PSScriptRoot),
    [switch]$Pretty
)

$ErrorActionPreference = 'Stop'
$rootFull = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
$manifestPath = Join-Path $rootFull 'MANIFEST.json'

$rows = @(
    Get-ChildItem -LiteralPath $rootFull -Recurse -File -Force |
        Where-Object {
            $_.FullName -ne $manifestPath -and
            $_.FullName -notmatch '[\\/]\.git[\\/]'
        } |
        ForEach-Object {
            $relative = $_.FullName.Substring($rootFull.Length).
                TrimStart('\', '/').Replace('\', '/')
            $licenseClass = if (
                $relative -match
                    '^(scripts|tests|core/schemas)/' -or
                $relative -eq 'LICENSE-CODE'
            ) {
                'MIT'
            }
            elseif ($relative -match '^vault-template/.+\.gitkeep$') {
                'empty_directory_marker'
            }
            else {
                'CC-BY-NC-SA-4.0'
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
    schema = 'contentos-lite-package-manifest-v1'
    profile_id = 'contentos-lite-v0.1'
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
[IO.File]::WriteAllText(
    $manifestPath,
    $json + [Environment]::NewLine,
    [Text.UTF8Encoding]::new($false)
)

[ordered]@{
    schema = 'contentos-lite-manifest-build-receipt-v1'
    status = 'built'
    manifest_path = $manifestPath
    file_count = $rows.Count
    total_bytes = $manifest.total_bytes
    manifest_sha256 = (
        Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256
    ).Hash.ToLowerInvariant()
} | ConvertTo-Json -Depth 4 -Compress
