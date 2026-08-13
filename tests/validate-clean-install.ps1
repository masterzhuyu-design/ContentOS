[CmdletBinding()]
param([string]$Root)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Split-Path -Parent $PSScriptRoot
}
$Root = [IO.Path]::GetFullPath($Root)
if (-not (Test-Path -LiteralPath (Join-Path $Root 'vault-template') -PathType Container)) {
    if (Test-Path -LiteralPath (Join-Path $Root 'vault') -PathType Container) {
        'SUMMARY: clean-install validation not applicable to initialized instance'
        exit 0
    }
    'FAIL: clean-install source layout is unknown'
    exit 1
}

$testBase = Join-Path ([IO.Path]::GetTempPath()) 'ContentOS-open-source-tests'
[void](New-Item -ItemType Directory -Path $testBase -Force)
$engine = (Get-Process -Id $PID).Path
$failures = [Collections.Generic.List[string]]::new()
$fixtures = [Collections.Generic.List[string]]::new()
$readmeText = Get-Content -LiteralPath (Join-Path $Root 'README.md') -Raw `
    -Encoding UTF8
$installText = Get-Content -LiteralPath (Join-Path $Root 'docs\install.md') -Raw `
    -Encoding UTF8
if ($readmeText -match "-Destination '\\.\\my-contentos" -or
    $installText -match "-Destination '\\.\\my-contentos" -or
    $installText -notmatch 'github\.com/masterzhuyu-design/ContentOS\.git') {
    $failures.Add('public_install_instructions_not_executable')
}

function Invoke-ChildValidation {
    param([string]$Fixture, [string]$RelativeTest)
    $testPath = Join-Path $Fixture $RelativeTest
    $output = & $engine -NoProfile -NonInteractive -ExecutionPolicy Bypass `
        -File $testPath -Root $Fixture 2>&1
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        $failures.Add("installed_validation_failed:${RelativeTest}:$exitCode")
        $output | ForEach-Object { Write-Output $_ }
    }
}

try {
    foreach ($profile in @('full', 'lite')) {
        $fixture = Join-Path $testBase (
            "ContentOS-$profile-" + [guid]::NewGuid().ToString('N').Substring(0, 8)
        )
        $fixtures.Add($fixture)
        $receipt = & (Join-Path $Root 'scripts\init-contentos.ps1') `
            -SourceRoot $Root -Destination $fixture -Profile $profile |
            ConvertFrom-Json
        if ([string]$receipt.status -ne 'initialized' -or
            [string]$receipt.profile_id -ne $profile -or
            $receipt.user_content_overwritten -ne $false) {
            $failures.Add("init_receipt_invalid:$profile")
            continue
        }
        $instanceIgnore = Get-Content -LiteralPath (
            Join-Path $fixture '.gitignore'
        ) -Raw -Encoding UTF8
        if ($instanceIgnore -notmatch '(?m)^/vault/$' -or
            $instanceIgnore -notmatch '(?m)^/\.contentos/config\.json$') {
            $failures.Add("instance_private_paths_not_ignored:$profile")
        }
        $config = Get-Content -LiteralPath (
            Join-Path $fixture '.contentos\config.json'
        ) -Raw -Encoding UTF8 | ConvertFrom-Json
        if ([string]$config.active_profile -ne $profile) {
            $failures.Add("installed_profile_mismatch:$profile")
        }

        foreach ($test in @(
            'tests\validate-powershell-syntax.ps1',
            'tests\validate-core-contract.ps1',
            'tests\validate-public-capability-coverage.ps1',
            'tests\validate-functional-parity.ps1',
            'tests\validate-problem-regression-scenarios.ps1',
            'tests\validate-task-budgets.ps1',
            'tests\validate-no-private-state.ps1'
        )) {
            Invoke-ChildValidation -Fixture $fixture -RelativeTest $test
        }

        $userFile = Join-Path $fixture 'vault\00_Inbox\user-owned-note.md'
        $marker = "user-owned-$profile"
        [IO.File]::WriteAllText(
            $userFile,
            $marker + [Environment]::NewLine,
            [Text.UTF8Encoding]::new($false)
        )
        $git = Get-Command git.exe -ErrorAction SilentlyContinue
        if ($null -eq $git) {
            $failures.Add('git_required_for_instance_privacy_check')
        }
        else {
            & $git.Source -C $fixture init --quiet
            & $git.Source -C $fixture check-ignore --quiet -- `
                'vault/00_Inbox/user-owned-note.md'
            if ($LASTEXITCODE -ne 0) {
                $failures.Add("vault_not_git_ignored:$profile")
            }
            & $git.Source -C $fixture check-ignore --quiet -- `
                '.contentos/config.json'
            if ($LASTEXITCODE -ne 0) {
                $failures.Add("instance_config_not_git_ignored:$profile")
            }
        }
        $second = & (Join-Path $Root 'scripts\init-contentos.ps1') `
            -SourceRoot $Root -Destination $fixture -Profile $profile |
            ConvertFrom-Json
        $readback = [IO.File]::ReadAllText($userFile, [Text.UTF8Encoding]::new($false)).Trim()
        if ($readback -ne $marker -or
            [string]$second.status -ne 'existing_instance_unchanged' -or
            [int]$second.created_count -ne 0 -or
            $second.user_content_overwritten -ne $false) {
            $failures.Add("repeat_init_overwrote_user_content:$profile")
        }

        if ($profile -eq 'full') {
            $runAllOutput = & $engine -NoProfile -NonInteractive `
                -ExecutionPolicy Bypass -File (Join-Path $fixture 'tests\run-all.ps1') `
                -Root $fixture 2>&1
            if ($LASTEXITCODE -ne 0 -or
                ($runAllOutput -join "`n") -notmatch
                    '8 passed, 2 skipped, 0 failed') {
                $failures.Add('installed_run_all_skip_accounting_invalid')
            }
        }
    }
}
finally {
    $baseFull = [IO.Path]::GetFullPath($testBase).TrimEnd('\', '/')
    $prefix = $baseFull + [IO.Path]::DirectorySeparatorChar
    foreach ($fixture in $fixtures) {
        $fixtureFull = [IO.Path]::GetFullPath($fixture)
        if ($fixtureFull.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) -and
            (Test-Path -LiteralPath $fixtureFull)) {
            Remove-Item -LiteralPath $fixtureFull -Recurse -Force
        }
    }
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { "FAIL: $_" }
    "SUMMARY: clean-install validation failed ($($failures.Count))"
    exit 1
}
'SUMMARY: clean-install validation passed (full + lite, repeat-init preservation)'
