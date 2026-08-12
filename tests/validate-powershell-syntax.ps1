[CmdletBinding()]
param([string]$Root)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Split-Path -Parent $PSScriptRoot
}
$failures = [Collections.Generic.List[string]]::new()
$files = @(Get-ChildItem -LiteralPath $Root -Recurse -File -Filter '*.ps1')
foreach ($file in $files) {
    $tokens = $null
    $errors = $null
    $null = [Management.Automation.Language.Parser]::ParseFile(
        $file.FullName,
        [ref]$tokens,
        [ref]$errors
    )
    foreach ($error in @($errors)) {
        $relative = $file.FullName.Substring($Root.Length).TrimStart('\', '/')
        $failures.Add("powershell_parse_error:${relative}:$($error.Message)")
    }
}
if ($failures.Count -gt 0) {
    $failures | ForEach-Object { "FAIL: $_" }
    "SUMMARY: PowerShell syntax validation failed ($($failures.Count))"
    exit 1
}
"SUMMARY: PowerShell syntax validation passed ($($files.Count) scripts)"
