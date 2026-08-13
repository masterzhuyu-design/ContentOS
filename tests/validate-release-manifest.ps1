[CmdletBinding()]
param([string]$Root)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Split-Path -Parent $PSScriptRoot
}
$rootFull = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
if (-not (Test-Path -LiteralPath (Join-Path $rootFull 'vault-template') -PathType Container)) {
    if (Test-Path -LiteralPath (Join-Path $rootFull 'vault') -PathType Container) {
        'SUMMARY: release manifest validation not applicable to initialized instance'
        exit 0
    }
    'FAIL: unknown ContentOS layout'
    exit 1
}

$failures = [Collections.Generic.List[string]]::new()
$manifestPath = Join-Path $rootFull 'MANIFEST.json'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    'FAIL: MANIFEST.json missing'
    exit 1
}
$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 |
    ConvertFrom-Json
$manifestBytes = [IO.File]::ReadAllBytes($manifestPath)
if (($manifestBytes -contains 13) -or
    ($manifestBytes.Count -ge 3 -and
        $manifestBytes[0] -eq 0xEF -and
        $manifestBytes[1] -eq 0xBB -and
        $manifestBytes[2] -eq 0xBF)) {
    $failures.Add('manifest_encoding_not_lf_utf8_no_bom')
}
if ([string]$manifest.schema -ne 'contentos-package-manifest-v1' -or
    [string]$manifest.release_id -ne 'contentos-v0.2.0-rc.2' -or
    $manifest.manifest_self_excluded -ne $true) {
    $failures.Add('manifest_identity_mismatch')
}
if ($null -ne $manifest.PSObject.Properties['generated_at']) {
    $failures.Add('manifest_contains_nondeterministic_generated_at')
}
$manifestPaths = @($manifest.files | ForEach-Object { [string]$_.path })
[string[]]$ordinalManifestPaths = @($manifestPaths)
[Array]::Sort($ordinalManifestPaths, [StringComparer]::Ordinal)
if (($manifestPaths -join "`n") -cne
    ($ordinalManifestPaths -join "`n")) {
    $failures.Add('manifest_paths_not_sorted')
}

$actualFiles = @(
    Get-ChildItem -LiteralPath $rootFull -Recurse -File -Force |
        Where-Object {
            $relative = $_.FullName.Substring($rootFull.Length).
                TrimStart('\', '/').Replace('\', '/')
            $relative -ne 'MANIFEST.json' -and $relative -ne '.git' -and
                -not $relative.StartsWith('.git/', [StringComparison]::OrdinalIgnoreCase)
        }
)
if ([int]$manifest.file_count -ne $actualFiles.Count -or
    [int]$manifest.file_count -ne @($manifest.files).Count) {
    $failures.Add('manifest_file_count_mismatch')
}
$actualTotal = [int64](
    $actualFiles | ForEach-Object { [int64]$_.Length } | Measure-Object -Sum
).Sum
if ([int64]$manifest.total_bytes -ne $actualTotal) {
    $failures.Add('manifest_total_bytes_mismatch')
}

foreach ($file in $actualFiles) {
    $relative = $file.FullName.Substring($rootFull.Length).
        TrimStart('\', '/').Replace('\', '/')
    $rows = @($manifest.files | Where-Object path -eq $relative)
    if ($rows.Count -ne 1) {
        $failures.Add("manifest_row_count:${relative}:$($rows.Count)")
        continue
    }
    $row = $rows[0]
    $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    if ([int64]$row.bytes -ne [int64]$file.Length -or [string]$row.sha256 -ne $hash) {
        $failures.Add("manifest_content_mismatch:$relative")
    }
    $expectedLicense = if (
        $relative -match '^(scripts|tests|config|\.github|core/(schemas|profiles|capabilities|upgrades))/' -or
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
    if ([string]$row.license_class -ne $expectedLicense) {
        $failures.Add("manifest_license_mismatch:$relative")
    }
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { "FAIL: $_" }
    "SUMMARY: release manifest validation failed ($($failures.Count))"
    exit 1
}
"SUMMARY: release manifest validation passed ($($actualFiles.Count) files)"
