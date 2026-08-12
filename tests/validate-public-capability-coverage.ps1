[CmdletBinding()]
param([string]$Root)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Split-Path -Parent $PSScriptRoot
}
$failures = [Collections.Generic.List[string]]::new()
$profiles = Get-Content -LiteralPath (
    Join-Path $Root 'core\profiles\task-profiles.json'
) -Raw -Encoding UTF8 | ConvertFrom-Json
$map = Get-Content -LiteralPath (
    Join-Path $Root 'core\capabilities\public-capability-map.json'
) -Raw -Encoding UTF8 | ConvertFrom-Json

$profileKinds = @($profiles.profiles | ForEach-Object { [string]$_.task_kind })
$mapKinds = @($map.capabilities | ForEach-Object { [string]$_.task_kind })
if ($profileKinds.Count -ne 28 -or $mapKinds.Count -ne 28) {
    $failures.Add("capability_count_mismatch:profiles=$($profileKinds.Count):map=$($mapKinds.Count)")
}
if ((($profileKinds | Sort-Object) -join '|') -ne
    (($mapKinds | Sort-Object) -join '|')) {
    $failures.Add('capability_task_set_mismatch')
}
if (@($mapKinds | Sort-Object -Unique).Count -ne 28) {
    $failures.Add('duplicate_capability_row')
}

foreach ($profile in @($profiles.profiles)) {
    $kind = [string]$profile.task_kind
    $row = @($map.capabilities | Where-Object task_kind -eq $kind)
    if ($row.Count -ne 1) {
        $failures.Add("capability_row_count:${kind}:$($row.Count)")
        continue
    }
    $expectedParity = if ([string]$profile.implementation -eq 'public_adapter') {
        'public_adapter'
    }
    else {
        'full'
    }
    if ([string]$row[0].parity -ne $expectedParity) {
        $failures.Add("parity_mismatch:$kind")
    }
    if ($expectedParity -eq 'public_adapter' -and
        [string]$row[0].adapter -ne [string]$profile.adapter_id) {
        $failures.Add("adapter_projection_mismatch:$kind")
    }
}

$fullCount = @($map.capabilities | Where-Object parity -eq 'full').Count
$adapterCount = @($map.capabilities | Where-Object parity -eq 'public_adapter').Count
if ($fullCount -ne 21 -or $adapterCount -ne 7) {
    $failures.Add("parity_class_count_mismatch:full=${fullCount}:adapter=$adapterCount")
}

$full = @($profiles.install_profiles | Where-Object profile_id -eq 'full')
$lite = @($profiles.install_profiles | Where-Object profile_id -eq 'lite')
if ($full.Count -ne 1 -or $lite.Count -ne 1) {
    $failures.Add('install_profile_identity_mismatch')
}
else {
    $fullKinds = @($full[0].task_kinds | ForEach-Object { [string]$_ })
    $liteKinds = @($lite[0].task_kinds | ForEach-Object { [string]$_ })
    if ($fullKinds.Count -ne 28 -or
        (($fullKinds | Sort-Object) -join '|') -ne
            (($profileKinds | Sort-Object) -join '|')) {
        $failures.Add('full_profile_not_all_canonical_tasks')
    }
    if ($liteKinds.Count -ne 15 -or @($liteKinds | Sort-Object -Unique).Count -ne 15) {
        $failures.Add('lite_profile_count_or_uniqueness_mismatch')
    }
    if (@($liteKinds | Where-Object { $_ -notin $fullKinds }).Count -gt 0) {
        $failures.Add('lite_profile_not_subset_of_full')
    }
}

if (@($map.intentionally_private_instance_surfaces).Count -lt 5) {
    $failures.Add('private_instance_boundary_too_weak')
}
if ([string]::IsNullOrWhiteSpace([string]$map.parity_definition)) {
    $failures.Add('parity_definition_missing')
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { "FAIL: $_" }
    "SUMMARY: public capability coverage failed ($($failures.Count))"
    exit 1
}
"SUMMARY: public capability coverage passed (21 native, 7 adapter-backed)"
