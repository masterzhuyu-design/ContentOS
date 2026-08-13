[CmdletBinding()]
param([string]$Root)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Split-Path -Parent $PSScriptRoot
}
$validator = Join-Path $Root 'scripts\validate-package-sanitization.ps1'
$includeGitHistory = Test-Path -LiteralPath (Join-Path $Root '.git') -PathType Container
$result = & $validator -Root $Root -IncludeGitHistory:$includeGitHistory |
    ConvertFrom-Json
if ([string]$result.status -ne 'passed' -or [int]$result.failure_count -ne 0) {
    @($result.failures) | ForEach-Object { "FAIL: $_" }
    'SUMMARY: no-private-state validation failed'
    exit 1
}

$git = Get-Command git.exe -ErrorAction SilentlyContinue
if ($null -eq $git) {
    'FAIL: Git is required for the historical filename alias regression'
    exit 1
}
$fixture = Join-Path ([IO.Path]::GetTempPath()) (
    'contentos-history-alias-' + [guid]::NewGuid().ToString('N')
)
try {
    [void](New-Item -ItemType Directory -Path $fixture -Force)
    foreach ($relative in @(
        'LICENSE-CODE', 'LICENSE-DOCS.md', 'THIRD-PARTY-NOTICES.md',
        'MANIFEST.json', 'AGENTS.md',
        'core\profiles\task-profiles.json',
        'core\capabilities\public-capability-map.json'
    )) {
        $target = Join-Path $fixture $relative
        [void](New-Item -ItemType Directory -Path (Split-Path -Parent $target) `
            -Force)
        Copy-Item -LiteralPath (Join-Path $Root $relative) -Destination $target
    }
    & $git.Source -C $fixture init --quiet
    & $git.Source -C $fixture config user.name 'ContentOS Test'
    & $git.Source -C $fixture config user.email 'contentos-test@example.invalid'
    & $git.Source -C $fixture config core.autocrlf false
    & $git.Source -C $fixture config core.safecrlf false
    [IO.File]::WriteAllText(
        (Join-Path $fixture 'safe.txt'),
        "same-blob`n",
        [Text.UTF8Encoding]::new($false)
    )
    & $git.Source -C $fixture add .
    & $git.Source -C $fixture commit --quiet -m 'safe baseline'
    Copy-Item -LiteralPath (Join-Path $fixture 'safe.txt') `
        -Destination (Join-Path $fixture '.env.backup')
    & $git.Source -C $fixture add .env.backup
    & $git.Source -C $fixture commit --quiet -m 'historical secret filename alias'
    Remove-Item -LiteralPath (Join-Path $fixture '.env.backup') -Force
    & $git.Source -C $fixture add -u
    & $git.Source -C $fixture commit --quiet -m 'remove alias from tip'

    $engine = (Get-Process -Id $PID).Path
    $historyOutput = & $engine -NoProfile -NonInteractive `
        -ExecutionPolicy Bypass -File $validator -Root $fixture `
        -IncludeGitHistory 2>&1
    $historyExit = $LASTEXITCODE
    $historyResult = ($historyOutput -join "`n") | ConvertFrom-Json
    if ($historyExit -eq 0 -or
        'secret_bearing_filename:git-history-path:.env.backup' -notin
            @($historyResult.failures)) {
        'FAIL: historical sensitive filename alias was not detected'
        exit 1
    }
}
finally {
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\', '/')
    $fixtureFull = [IO.Path]::GetFullPath($fixture)
    if ($fixtureFull.StartsWith(
        $tempRoot + [IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase
    ) -and (Test-Path -LiteralPath $fixtureFull)) {
        Remove-Item -LiteralPath $fixtureFull -Recurse -Force
    }
}
$historySummary = if ($result.history_scanned -and $result.index_scanned) {
    ", $($result.index_blob_count) staged blobs, " +
        "$($result.history_blob_count) historical blobs"
}
else {
    ', no Git history in installed fixture'
}
"SUMMARY: no-private-state validation passed ($($result.file_count) files$historySummary)"
