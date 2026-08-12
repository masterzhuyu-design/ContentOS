[CmdletBinding()]
param(
    [string]$Root,
    [switch]$IncludeGitHistory,
    [string]$GitExecutable,
    [switch]$Pretty
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Split-Path -Parent $PSScriptRoot
}
$rootFull = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
$failures = [Collections.Generic.List[string]]::new()

function Add-SanitizationFailure {
    param([string]$Code, [string]$Location)
    $entry = if ([string]::IsNullOrWhiteSpace($Location)) {
        $Code
    }
    else {
        "${Code}:$Location"
    }
    if (-not $failures.Contains($entry)) {
        $failures.Add($entry)
    }
}

$secretPatterns = @(
    [pscustomobject]@{
        id = 'private_key_material'
        regex = '(?i)-----BEGIN (?:RSA |EC |OPENSSH |DSA |PGP )?PRIVATE KEY-----'
    },
    [pscustomobject]@{
        id = 'openai_style_api_key'
        regex = '(?<![A-Za-z0-9])sk-(?:proj-|svcacct-)?[A-Za-z0-9_-]{20,}'
    },
    [pscustomobject]@{
        id = 'github_token'
        regex = '(?<![A-Za-z0-9])(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})'
    },
    [pscustomobject]@{
        id = 'gitlab_token'
        regex = '(?<![A-Za-z0-9])glpat-[A-Za-z0-9_-]{20,}'
    },
    [pscustomobject]@{
        id = 'aws_access_key'
        regex = '(?<![A-Z0-9])(?:AKIA|ASIA)[A-Z0-9]{16}(?![A-Z0-9])'
    },
    [pscustomobject]@{
        id = 'google_api_key'
        regex = '(?<![A-Za-z0-9])AIza[0-9A-Za-z_-]{30,}'
    },
    [pscustomobject]@{
        id = 'slack_token'
        regex = '(?<![A-Za-z0-9])xox[baprs]-[A-Za-z0-9-]{10,}'
    },
    [pscustomobject]@{
        id = 'stripe_live_key'
        regex = '(?<![A-Za-z0-9])(?:sk|rk)_live_[A-Za-z0-9]{16,}'
    },
    [pscustomobject]@{
        id = 'huggingface_token'
        regex = '(?<![A-Za-z0-9])hf_[A-Za-z0-9]{20,}'
    },
    [pscustomobject]@{
        id = 'npm_token'
        regex = '(?<![A-Za-z0-9])npm_[A-Za-z0-9]{20,}'
    },
    [pscustomobject]@{
        id = 'pypi_token'
        regex = '(?<![A-Za-z0-9])pypi-[A-Za-z0-9_-]{20,}'
    },
    [pscustomobject]@{
        id = 'jwt_token'
        regex = '(?<![A-Za-z0-9_-])eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}'
    },
    [pscustomobject]@{
        id = 'authorization_bearer_token'
        regex = '(?i)\bauthorization\s*[:=]\s*["'']?bearer\s+[A-Za-z0-9._~+/-]{20,}={0,2}'
    },
    [pscustomobject]@{
        id = 'credential_in_url'
        regex = '(?i)\b[a-z][a-z0-9+.-]*://[^/\s:@]+:[^/\s@]+@'
    },
    [pscustomobject]@{
        id = 'populated_secret_assignment'
        regex = '(?im)\b(?:api[_-]?key|access[_-]?token|refresh[_-]?token|client[_-]?secret|password|private[_-]?token|secret)\b\s*[:=]\s*["'']?(?!\s*(?:change_me|replace_me|example|dummy|test|<[^>]+>|\$\{[^}]+\}|\{\{[^}]+\}\}))[A-Za-z0-9_./+=-]{16,}'
    }
)

$secretFilePatterns = @(
    '(?i)(^|/)\.env(?:\.|$)',
    '(?i)(^|/)\.(?:npmrc|pypirc|netrc)$',
    '(?i)(^|/)(?:id_rsa|id_ed25519)(?:\.|$)',
    '(?i)\.(?:pem|key|p12|pfx)$',
    '(?i)(^|/)(?:credentials|service-account[^/]*)\.json$'
)

function Test-TextForSecrets {
    param([string]$Text, [string]$Location)
    foreach ($pattern in $secretPatterns) {
        if ($Text -match [string]$pattern.regex) {
            Add-SanitizationFailure -Code (
                'secret_pattern_' + [string]$pattern.id
            ) -Location $Location
        }
    }
}

function Test-PathForSecrets {
    param([string]$RelativePath, [string]$LocationPrefix)
    foreach ($pattern in $secretFilePatterns) {
        if ($RelativePath -match $pattern) {
            Add-SanitizationFailure -Code 'secret_bearing_filename' `
                -Location ("${LocationPrefix}${RelativePath}")
        }
    }
}

function Resolve-GitExecutable {
    if (-not [string]::IsNullOrWhiteSpace($GitExecutable)) {
        if (Test-Path -LiteralPath $GitExecutable -PathType Leaf) {
            return [IO.Path]::GetFullPath($GitExecutable)
        }
        return $null
    }
    $command = Get-Command git.exe -ErrorAction SilentlyContinue
    if ($null -ne $command) {
        return $command.Source
    }
    $candidates = @(
        (Join-Path $env:ProgramFiles 'Git\cmd\git.exe'),
        (Join-Path $env:LOCALAPPDATA (
            'Microsoft\WinGet\Packages\' +
            'Git.MinGit_Microsoft.Winget.Source_8wekyb3d8bbwe\cmd\git.exe'
        ))
    )
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return [IO.Path]::GetFullPath($candidate)
        }
    }
    return $null
}

function Test-GitBlobForSecrets {
    param(
        [string]$Git,
        [string]$ObjectId,
        [string]$Location,
        [string]$RelativePath
    )
    if (-not [string]::IsNullOrWhiteSpace($RelativePath)) {
        Test-PathForSecrets -RelativePath ($RelativePath.Replace('\', '/')) `
            -LocationPrefix ($Location + ':')
    }
    $sizeText = (& $Git -C $rootFull cat-file -s $ObjectId 2>$null) |
        Select-Object -First 1
    [int64]$size = 0
    if ($LASTEXITCODE -ne 0 -or
        -not [int64]::TryParse([string]$sizeText, [ref]$size)) {
        Add-SanitizationFailure -Code 'git_object_scan_failed' `
            -Location ($Location + ':blob_size')
        return
    }
    if ($size -gt 5242880) {
        Add-SanitizationFailure -Code 'git_object_too_large_to_scan' `
            -Location ($Location + ':' + $ObjectId.Substring(0, 12))
        return
    }
    $blobText = @(
        & $Git -C $rootFull cat-file blob $ObjectId 2>$null
    ) -join "`n"
    if ($LASTEXITCODE -ne 0) {
        Add-SanitizationFailure -Code 'git_object_scan_failed' `
            -Location ($Location + ':blob_read')
        return
    }
    Test-TextForSecrets -Text $blobText -Location (
        $Location + ':blob:' + $ObjectId.Substring(0, 12)
    )
}

$files = @(
    Get-ChildItem -LiteralPath $rootFull -Recurse -File -Force |
        Where-Object {
            $candidateRelative = $_.FullName.Substring($rootFull.Length).
                TrimStart('\', '/').Replace('\', '/')
            $candidateRelative -ne '.git' -and
                -not $candidateRelative.StartsWith(
                    '.git/',
                    [StringComparison]::OrdinalIgnoreCase
                )
        }
)

$denySegments = @(
    '.agents/',
    '.codex/',
    '.codex-remote-attachments/',
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

foreach ($file in $files) {
    $relative = $file.FullName.Substring($rootFull.Length).
        TrimStart('\', '/').Replace('\', '/')
    $lower = $relative.ToLowerInvariant()
    Test-PathForSecrets -RelativePath $relative -LocationPrefix ''
    foreach ($segment in $denySegments) {
        if ($lower.StartsWith($segment) -or $lower.Contains('/' + $segment)) {
            Add-SanitizationFailure -Code 'forbidden_path' -Location $relative
            break
        }
    }
    if ($file.Extension.ToLowerInvariant() -in $denyExtensions) {
        Add-SanitizationFailure -Code 'forbidden_binary' -Location $relative
        continue
    }
    if ($file.Length -gt 0) {
        try {
            $text = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8
        }
        catch {
            Add-SanitizationFailure -Code 'non_utf8_or_unreadable' `
                -Location $relative
            continue
        }
        if ($text -match $drivePattern -or $text -match $userPattern) {
            Add-SanitizationFailure -Code 'absolute_local_path' -Location $relative
        }
        if ($text -match $uuidPattern) {
            Add-SanitizationFailure -Code 'live_uuid_like_identity' `
                -Location $relative
        }
        Test-TextForSecrets -Text $text -Location $relative
    }
}

$secretPatternSelfTests = @(
    [pscustomobject]@{
        id = 'openai_style_api_key'
        text = 'sk-' + ('A' * 32)
    },
    [pscustomobject]@{
        id = 'github_token'
        text = 'ghp_' + ('B' * 36)
    },
    [pscustomobject]@{
        id = 'private_key_material'
        text = '-----BEGIN ' + 'PRIVATE KEY-----'
    },
    [pscustomobject]@{
        id = 'populated_secret_assignment'
        text = 'api_key=' + ('C' * 32)
    }
)
foreach ($fixture in $secretPatternSelfTests) {
    $matchedIds = @(
        $secretPatterns |
            Where-Object { $fixture.text -match [string]$_.regex } |
            ForEach-Object { [string]$_.id }
    )
    if ([string]$fixture.id -notin $matchedIds) {
        Add-SanitizationFailure -Code 'secret_scanner_self_test_failed' `
            -Location ([string]$fixture.id)
    }
}

$historyScanned = $false
$historyBlobCount = 0
$historyCommitCount = 0
$indexScanned = $false
$indexBlobCount = 0
if ($IncludeGitHistory) {
    $git = Resolve-GitExecutable
    if ([string]::IsNullOrWhiteSpace($git)) {
        Add-SanitizationFailure -Code 'git_history_scan_unavailable' `
            -Location 'git_executable_missing'
    }
    else {
        $inside = (& $git -C $rootFull rev-parse --is-inside-work-tree 2>$null) |
            Select-Object -First 1
        if ($LASTEXITCODE -ne 0 -or [string]$inside -ne 'true') {
            Add-SanitizationFailure -Code 'git_history_scan_unavailable' `
                -Location 'not_a_git_worktree'
        }
        else {
            $indexLines = @(& $git -C $rootFull ls-files -s 2>$null)
            if ($LASTEXITCODE -ne 0) {
                Add-SanitizationFailure -Code 'git_index_scan_failed' `
                    -Location 'ls_files'
            }
            else {
                $seenIndexBlobs = [Collections.Generic.HashSet[string]]::new(
                    [StringComparer]::OrdinalIgnoreCase
                )
                foreach ($line in $indexLines) {
                    if ([string]$line -notmatch (
                        '^\d+\s+([0-9a-f]{40,64})\s+\d+\t(.+)$'
                    )) {
                        continue
                    }
                    $objectId = [string]$Matches[1]
                    $relative = [string]$Matches[2]
                    if (-not $seenIndexBlobs.Add($objectId)) {
                        continue
                    }
                    $indexBlobCount++
                    Test-GitBlobForSecrets -Git $git -ObjectId $objectId `
                        -Location 'git-index' -RelativePath $relative
                }
                $indexScanned = $true
            }

            $objectLines = @(& $git -C $rootFull rev-list --objects --all 2>$null)
            if ($LASTEXITCODE -ne 0) {
                Add-SanitizationFailure -Code 'git_history_scan_failed' `
                    -Location 'rev_list'
            }
            else {
                $seen = [Collections.Generic.HashSet[string]]::new(
                    [StringComparer]::OrdinalIgnoreCase
                )
                foreach ($line in $objectLines) {
                    if ([string]$line -notmatch '^([0-9a-f]{40,64})(?:\s+(.*))?$') {
                        continue
                    }
                    $objectId = [string]$Matches[1]
                    $relative = [string]$Matches[2]
                    if (-not $seen.Add($objectId)) {
                        continue
                    }
                    $type = (& $git -C $rootFull cat-file -t $objectId 2>$null) |
                        Select-Object -First 1
                    if ($LASTEXITCODE -ne 0 -or [string]$type -ne 'blob') {
                        continue
                    }
                    $historyBlobCount++
                    Test-GitBlobForSecrets -Git $git -ObjectId $objectId `
                        -Location 'git-history' -RelativePath $relative
                }
            }

            $commitIds = @(& $git -C $rootFull rev-list --all 2>$null)
            if ($LASTEXITCODE -ne 0) {
                Add-SanitizationFailure -Code 'git_history_scan_failed' `
                    -Location 'commit_list'
            }
            else {
                foreach ($commitId in $commitIds) {
                    $historyCommitCount++
                    $message = @(
                        & $git -C $rootFull show -s --format=%B $commitId 2>$null
                    ) -join "`n"
                    if ($LASTEXITCODE -ne 0) {
                        Add-SanitizationFailure -Code 'git_history_scan_failed' `
                            -Location 'commit_message_read'
                        continue
                    }
                    Test-TextForSecrets -Text $message -Location (
                        'git-history:commit:' +
                        ([string]$commitId).Substring(0, 12)
                    )
                }
            }
            $historyScanned = $true
        }
    }
}

foreach ($required in @(
    'LICENSE-CODE',
    'LICENSE-DOCS.md',
    'THIRD-PARTY-NOTICES.md',
    'MANIFEST.json',
    'AGENTS.md',
    'core/profiles/task-profiles.json',
    'core/capabilities/public-capability-map.json'
)) {
    $path = Join-Path $rootFull $required
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Add-SanitizationFailure -Code 'required_file_missing' -Location $required
    }
}

$result = [ordered]@{
    schema = 'contentos-sanitization-result-v1'
    status = if ($failures.Count -eq 0) { 'passed' } else { 'failed' }
    root = $rootFull
    file_count = $files.Count
    history_requested = [bool]$IncludeGitHistory
    index_scanned = $indexScanned
    index_blob_count = $indexBlobCount
    history_scanned = $historyScanned
    history_blob_count = $historyBlobCount
    history_commit_count = $historyCommitCount
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
