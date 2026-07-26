[CmdletBinding()]
param(
    [string]$Root = (Split-Path -Parent $PSScriptRoot),
    [switch]$Pretty
)

$ErrorActionPreference = 'Stop'
$rootFull = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
$failures = [Collections.Generic.List[string]]::new()

$files = @(
    Get-ChildItem -LiteralPath $rootFull -Recurse -File -Force |
        Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' }
)

$denySegments = @(
    '.agents/',
    '.codex/',
    '.codex-remote-attachments/',
    'tools/knowledgeos/',
    '.contentos/runtime/',
    '__pycache__/'
)
$denyExtensions = @(
    '.db', '.sqlite', '.sqlite3', '.bin', '.gguf', '.safetensors',
    '.pyc', '.pyd', '.dll', '.exe'
)
$drivePattern = '(?<![A-Za-z0-9])[A-Za-z]:' + '[\\/]'
$userPattern = 'C:' + '[\\/]' + 'Users' + '[\\/]'
$uuidPattern = '(?i)\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b'
$populatedSecretPattern =
    '(?i)"(?:api_key|access_token|refresh_token|password|secret|cookie)"\s*:\s*"(?!\s*(?:|CHANGE_ME|REPLACE_ME|<[^>]+>)\s*")[^"]+"'

foreach ($file in $files) {
    $relative = $file.FullName.Substring($rootFull.Length).
        TrimStart('\', '/').Replace('\', '/')
    $lower = $relative.ToLowerInvariant()
    foreach ($segment in $denySegments) {
        if ($lower.StartsWith($segment) -or $lower.Contains('/' + $segment)) {
            $failures.Add("forbidden_path:$relative")
            break
        }
    }
    if ($file.Extension.ToLowerInvariant() -in $denyExtensions) {
        $failures.Add("forbidden_binary:$relative")
        continue
    }
    if ($file.Length -gt 0) {
        try {
            $text = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8
        }
        catch {
            $failures.Add("non_utf8_or_unreadable:$relative")
            continue
        }
        if ($text -match $drivePattern -or $text -match $userPattern) {
            $failures.Add("absolute_local_path:$relative")
        }
        if ($text -match $uuidPattern) {
            $failures.Add("live_uuid_like_identity:$relative")
        }
        if ($text -match $populatedSecretPattern) {
            $failures.Add("populated_secret_like_field:$relative")
        }
    }
}

foreach ($required in @(
    'LICENSE-CODE',
    'LICENSE-DOCS.md',
    'THIRD-PARTY-NOTICES.md',
    'MANIFEST.json',
    'AGENTS.md',
    'core/profiles/task-profiles.json'
)) {
    $path = Join-Path $rootFull $required
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        $failures.Add("required_file_missing:$required")
    }
}

$result = [ordered]@{
    schema = 'contentos-lite-sanitization-result-v1'
    status = if ($failures.Count -eq 0) { 'passed' } else { 'failed' }
    root = $rootFull
    file_count = $files.Count
    failure_count = $failures.Count
    failures = @($failures)
    policy = 'fail_closed_no_archive'
}

if ($Pretty) {
    $result | ConvertTo-Json -Depth 6
}
else {
    $result | ConvertTo-Json -Depth 6 -Compress
}
if ($failures.Count -gt 0) {
    exit 1
}
