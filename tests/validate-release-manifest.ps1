[CmdletBinding()]
param([string]$Root = (Split-Path -Parent $PSScriptRoot))

$ErrorActionPreference = 'Stop'
$rootFull = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
$releaseTemplate = Join-Path $rootFull 'vault-template'

if (-not (Test-Path -LiteralPath $releaseTemplate -PathType Container)) {
    if (Test-Path -LiteralPath (Join-Path $rootFull 'vault')) {
        'SUMMARY: release manifest validation not applicable to initialized layout'
        exit 0
    }
    'FAIL: neither release nor initialized layout detected'
    exit 1
}

$failures = [Collections.Generic.List[string]]::new()
$manifestPath = Join-Path $rootFull 'MANIFEST.json'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    'FAIL: MANIFEST.json missing'
    exit 1
}

$manifest = Get-Content `
    -LiteralPath $manifestPath `
    -Raw `
    -Encoding UTF8 |
    ConvertFrom-Json
$actualFiles = @(
    Get-ChildItem -LiteralPath $rootFull -Recurse -File -Force |
        Where-Object {
            $relative = $_.FullName.Substring($rootFull.Length).
                TrimStart('\', '/').Replace('\', '/')
            $relative -ne 'MANIFEST.json' -and
                $relative -ne '.git' -and
                -not $relative.StartsWith(
                    '.git/',
                    [StringComparison]::OrdinalIgnoreCase
                )
        }
)

if ($manifest.manifest_self_excluded -ne $true) {
    $failures.Add('manifest_self_exclusion_not_declared')
}
if (
    [int]$manifest.file_count -ne @($manifest.files).Count -or
    [int]$manifest.file_count -ne $actualFiles.Count
) {
    $failures.Add('manifest_file_count_mismatch')
}

$actualTotalBytes = [int64](
    $actualFiles |
        ForEach-Object { [int64]$_.Length } |
        Measure-Object -Sum
).Sum
if ([int64]$manifest.total_bytes -ne $actualTotalBytes) {
    $failures.Add('manifest_total_bytes_mismatch')
}

foreach ($file in $actualFiles) {
    $relative = $file.FullName.Substring($rootFull.Length).
        TrimStart('\', '/').Replace('\', '/')
    $row = @($manifest.files | Where-Object path -eq $relative)
    if ($row.Count -ne 1) {
        $failures.Add("manifest_row_count:$relative")
        continue
    }
    if ([int64]$file.Length -ne [int64]$row[0].bytes) {
        $failures.Add("manifest_bytes_mismatch:$relative")
    }
    $hash = (
        Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256
    ).Hash.ToLowerInvariant()
    if ($hash -ne [string]$row[0].sha256) {
        $failures.Add("manifest_hash_mismatch:$relative")
    }
}

foreach ($row in @($manifest.files)) {
    $relative = [string]$row.path
    if (
        $relative -eq '.git' -or
        $relative.StartsWith(
            '.git/',
            [StringComparison]::OrdinalIgnoreCase
        )
    ) {
        $failures.Add('manifest_contains_git_metadata')
    }
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { "FAIL: $_" }
    "SUMMARY: release manifest validation failed ($($failures.Count))"
    exit 1
}

"SUMMARY: release manifest validation passed ($($actualFiles.Count) files)"
