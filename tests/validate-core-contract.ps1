[CmdletBinding()]
param([string]$Root = (Split-Path -Parent $PSScriptRoot))

$ErrorActionPreference = 'Stop'
$failures = [Collections.Generic.List[string]]::new()

function Require-Text {
    param(
        [string]$Text,
        [string]$Pattern,
        [string]$Failure
    )
    if ($Text -notmatch $Pattern) {
        $failures.Add($Failure)
    }
}

$profilePath = Join-Path $Root 'core\profiles\task-profiles.json'
$profiles = Get-Content -LiteralPath $profilePath -Raw -Encoding UTF8 |
    ConvertFrom-Json
$requiredKinds = @(
    'thread_recovery_lite',
    'vault_query_lite',
    'learning_intake_lite',
    'learning_teaching_lite',
    'decomposition_qa_lite',
    'transfer_qa_lite',
    'learning_close_lite',
    'review_schedule_lite',
    'share_card_lite',
    'model_case_capture_lite',
    'ontology_update_lite',
    'asset_reuse_lite',
    'web_search_lite',
    'content_creation_lite',
    'content_review_lite'
)
$actualKinds = @($profiles.profiles.task_kind)
foreach ($kind in $requiredKinds) {
    if ($kind -notin $actualKinds) {
        $failures.Add("missing_task_kind:$kind")
    }
}
foreach ($group in @($actualKinds | Group-Object | Where-Object Count -gt 1)) {
    $failures.Add("duplicate_task_kind:$($group.Name)")
}

$allRules = @(
    Get-ChildItem -LiteralPath (Join-Path $Root 'core\rules') -File |
        ForEach-Object {
            Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8
        }
) -join "`n"
foreach ($required in @(
    'adaptive_mode',
    'no_fixed_quota',
    'semantic_truncation_forbidden',
    'expansion_receipt',
    '拆解问答',
    '迁移问答',
    'detached_share_export',
    'ReviewPlan',
    'D\+1、D\+7、D\+30',
    'ModelCard',
    'CaseCard',
    'OntologyStatement',
    'AssetReusePlanner',
    'use / backstage / no_use',
    'LearningTrack',
    'KnowledgeAssetTrack',
    'CreationTrack'
)) {
    Require-Text `
        -Text $allRules `
        -Pattern $required `
        -Failure "core_contract_missing:$required"
}

$learningProfiles = @(
    $profiles.profiles |
        Where-Object {
            $_.task_kind -in @(
                'learning_teaching_lite',
                'decomposition_qa_lite',
                'transfer_qa_lite'
            )
        }
)
foreach ($profile in $learningProfiles) {
    if (
        'core/rules/04-assets-ontology-and-reuse.md' -notin
            @($profile.rule_files)
    ) {
        $failures.Add(
            "learning_asset_reuse_not_wired:$($profile.task_kind)"
        )
    }
}

$moduleRegistry = Get-Content `
    -LiteralPath (Join-Path $Root 'core\upgrades\module-registry.json') `
    -Raw `
    -Encoding UTF8 |
    ConvertFrom-Json
foreach ($coreModule in @(
    'learning_loop',
    'review_planner',
    'model_case_capture',
    'file_ontology',
    'asset_reuse',
    'share_card_body',
    'search_lite',
    'creation_lite'
)) {
    $rows = @(
        $moduleRegistry.modules |
            Where-Object {
                $_.module_id -eq $coreModule -and
                $_.state -eq 'core' -and
                $_.default_included -eq $true
            }
    )
    if ($rows.Count -ne 1) {
        $failures.Add("core_module_marker_missing:$coreModule")
    }
}

foreach ($forbiddenPath in @(
    'tools\knowledgeos',
    'models',
    '.contentos\runtime\index.sqlite'
)) {
    if (Test-Path -LiteralPath (Join-Path $Root $forbiddenPath)) {
        $failures.Add("forbidden_default_dependency:$forbiddenPath")
    }
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { "FAIL: $_" }
    "SUMMARY: core contract failed ($($failures.Count))"
    exit 1
}

"SUMMARY: core contract passed ($($requiredKinds.Count) TaskKinds)"
