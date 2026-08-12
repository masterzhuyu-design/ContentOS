[CmdletBinding()]
param([string]$Root)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Split-Path -Parent $PSScriptRoot
}
$failures = [Collections.Generic.List[string]]::new()
$files = @(Get-ChildItem -LiteralPath $Root -Recurse -File -Filter '*.ps1')
foreach ($file in $files) {
    $relative = $file.FullName.Substring($Root.Length).TrimStart('\', '/')
    $bytes = [IO.File]::ReadAllBytes($file.FullName)
    $hasUtf8Bom = (
        $bytes.Count -ge 3 -and
        $bytes[0] -eq 0xEF -and
        $bytes[1] -eq 0xBB -and
        $bytes[2] -eq 0xBF
    )
    try {
        $text = [Text.UTF8Encoding]::new($false, $true).GetString($bytes)
        $hasNonAscii = $text -match '[^\x00-\x7F]'
    }
    catch {
        $failures.Add("powershell_not_valid_utf8:${relative}")
        $hasNonAscii = $false
    }
    if ($hasNonAscii -and -not $hasUtf8Bom) {
        $failures.Add("powershell_non_ascii_without_utf8_bom:${relative}")
    }
    $tokens = $null
    $errors = $null
    $null = [Management.Automation.Language.Parser]::ParseFile(
        $file.FullName,
        [ref]$tokens,
        [ref]$errors
    )
    foreach ($error in @($errors)) {
        $failures.Add("powershell_parse_error:${relative}:$($error.Message)")
    }
}
if ($failures.Count -gt 0) {
    $failures | ForEach-Object { "FAIL: $_" }
    "SUMMARY: PowerShell syntax validation failed ($($failures.Count))"
    exit 1
}
"SUMMARY: PowerShell syntax validation passed ($($files.Count) scripts)"
