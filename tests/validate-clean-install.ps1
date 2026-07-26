[CmdletBinding()]
param(
    [string]$Root = (Split-Path -Parent $PSScriptRoot),
    [switch]$KeepFixture
)

$ErrorActionPreference = 'Stop'
$failures = [Collections.Generic.List[string]]::new()
$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\', '/')
$fixture = Join-Path $tempRoot (
    'ContentOS Lite 干净安装 ' + [guid]::NewGuid().ToString('N').Substring(0, 8)
)

try {
    $init = Join-Path $Root 'scripts\init-contentos-lite.ps1'
    $first = & $init -SourceRoot $Root -Destination $fixture |
        ConvertFrom-Json
    if ($first.status -ne 'initialized' -or $first.created_count -lt 1) {
        $failures.Add('first_initialization_failed')
    }

    $userFile = Join-Path $fixture 'vault\00_Inbox\user-owned.md'
    [IO.File]::WriteAllText(
        $userFile,
        'user-owned-content',
        [Text.UTF8Encoding]::new($false)
    )
    $second = & $init -SourceRoot $Root -Destination $fixture |
        ConvertFrom-Json
    if (-not (Test-Path -LiteralPath $userFile -PathType Leaf)) {
        $failures.Add('user_file_removed')
    }
    elseif (
        (Get-Content -LiteralPath $userFile -Raw -Encoding UTF8) -ne
            'user-owned-content'
    ) {
        $failures.Add('user_file_overwritten')
    }
    if ($second.user_content_overwritten -ne $false) {
        $failures.Add('second_init_claimed_overwrite')
    }

    foreach ($forbidden in @(
        'tools\knowledgeos',
        '.contentos\runtime\index.sqlite',
        'models'
    )) {
        if (Test-Path -LiteralPath (Join-Path $fixture $forbidden)) {
            $failures.Add("forbidden_install_surface:$forbidden")
        }
    }

    $startup = & (Join-Path $fixture 'scripts\resolve-startup-lite.ps1') `
        -Root $fixture `
        -TaskKind 'content_creation_lite' |
        ConvertFrom-Json
    if (
        $startup.status -ne 'blocked_missing_inputs' -or
        $startup.generation_allowed -ne $false
    ) {
        $failures.Add('missing_inputs_did_not_block_generation')
    }

    foreach ($validatorName in @(
        'validate-core-contract.ps1',
        'validate-task-budgets.ps1',
        'validate-no-private-state.ps1'
    )) {
        $validatorOutput = @(
            & (Join-Path $fixture "tests\$validatorName") -Root $fixture
        )
        $validatorSucceeded = $?
        if (-not $validatorSucceeded) {
            $failures.Add("installed_validator_failed:$validatorName")
            $validatorOutput | ForEach-Object {
                $failures.Add(
                    "installed_validator_output:${validatorName}:$($_.ToString())"
                )
            }
        }
    }
}
finally {
    if (-not $KeepFixture -and (Test-Path -LiteralPath $fixture)) {
        $fixtureFull = [IO.Path]::GetFullPath($fixture)
        $safePrefix = $tempRoot + [IO.Path]::DirectorySeparatorChar +
            'ContentOS Lite 干净安装 '
        if (
            -not $fixtureFull.StartsWith(
                $safePrefix,
                [StringComparison]::OrdinalIgnoreCase
            )
        ) {
            throw "Refusing unsafe fixture cleanup: $fixtureFull"
        }
        Remove-Item -LiteralPath $fixtureFull -Recurse -Force
    }
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { "FAIL: $_" }
    "SUMMARY: clean install validation failed ($($failures.Count))"
    exit 1
}
"SUMMARY: clean install validation passed"
