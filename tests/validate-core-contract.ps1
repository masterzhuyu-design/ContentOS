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
$expectedProfileId = 'contentos-lite-v0.1.1'
if ([string]$profiles.profile_id -ne $expectedProfileId) {
    $failures.Add('task_profile_release_id_mismatch')
}
$config = Get-Content `
    -LiteralPath (Join-Path $Root 'config\contentos.example.json') `
    -Raw `
    -Encoding UTF8 |
    ConvertFrom-Json
if ([string]$config.profile_id -ne $expectedProfileId) {
    $failures.Add('config_release_id_mismatch')
}
$manifest = Get-Content `
    -LiteralPath (Join-Path $Root 'MANIFEST.json') `
    -Raw `
    -Encoding UTF8 |
    ConvertFrom-Json
if ([string]$manifest.profile_id -ne $expectedProfileId) {
    $failures.Add('manifest_release_id_mismatch')
}
foreach ($manifestRow in @($manifest.files)) {
    $manifestRelative = [string]$manifestRow.path
    if (
        $manifestRelative -eq '.git' -or
        $manifestRelative.StartsWith(
            '.git/',
            [StringComparison]::OrdinalIgnoreCase
        )
    ) {
        $failures.Add('manifest_contains_git_metadata')
    }
}
$releaseManifestValidator = Join-Path `
    $Root `
    'tests\validate-release-manifest.ps1'
if (
    -not (
        Test-Path `
            -LiteralPath $releaseManifestValidator `
            -PathType Leaf
    )
) {
    $failures.Add('release_manifest_validator_missing')
}
$manifestBuilder = Get-Content `
    -LiteralPath (Join-Path $Root 'scripts\build-package-manifest.ps1') `
    -Raw `
    -Encoding UTF8
Require-Text `
    -Text $manifestBuilder `
    -Pattern 'contentos-lite-v0\.1\.1' `
    -Failure 'manifest_builder_release_id_mismatch'
$attributesPath = Join-Path $Root '.gitattributes'
if (-not (Test-Path -LiteralPath $attributesPath -PathType Leaf)) {
    $failures.Add('deterministic_line_endings_missing')
}
else {
    $attributes = Get-Content `
        -LiteralPath $attributesPath `
        -Raw `
        -Encoding UTF8
    Require-Text `
        -Text $attributes `
        -Pattern '\* text=auto eol=lf' `
        -Failure 'deterministic_line_endings_invalid'
}
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

$qualityGatePath = Join-Path `
    $Root `
    'scripts\evaluate-quality-gate-lite.ps1'
if (-not (Test-Path -LiteralPath $qualityGatePath -PathType Leaf)) {
    $failures.Add('quality_gate_interface_missing')
}
foreach ($schemaPath in @(
    'core\schemas\quality-observation.schema.json'
    'core\schemas\quality-decision.schema.json'
)) {
    if (-not (Test-Path -LiteralPath (Join-Path $Root $schemaPath))) {
        $failures.Add("quality_gate_schema_missing:$schemaPath")
    }
}
if (
    [string]$profiles.quality_gate_interface.tool -ne
        'scripts/evaluate-quality-gate-lite.ps1' -or
    [string]$profiles.quality_gate_interface.input_schema -ne
        'contentos-lite-quality-observation-v1' -or
    [string]$profiles.quality_gate_interface.output_schema -ne
        'contentos-lite-quality-decision-v1' -or
    [string]$profiles.quality_gate_interface.side_effects -ne 'none'
) {
    $failures.Add('quality_gate_manifest_interface_invalid')
}
$requiredGateMappings = [ordered]@{
    decomposition_qa_lite = @(
        'teaching_before_test'
        'asset_reuse'
    )
    transfer_qa_lite = @(
        'teaching_before_test'
        'transfer_integrity'
        'asset_reuse'
    )
    review_schedule_lite = @(
        'review_adaptation'
        'asset_reuse'
    )
    share_card_lite = @(
        'share_completeness'
        'capacity_preservation'
        'discussion_delta_integrity'
        'rights_scope'
        'authorship_quality'
        'track_authority'
    )
    web_search_lite = @('search_claim_calibration')
    content_creation_lite = @(
        'creation_coherence'
        'asset_reuse'
        'capacity_preservation'
        'discussion_delta_integrity'
        'rights_scope'
        'authorship_quality'
        'track_authority'
    )
    content_review_lite = @(
        'revision_scope'
        'discussion_delta_integrity'
        'authorship_quality'
        'rights_scope'
        'capacity_preservation'
    )
}
foreach ($mapping in $requiredGateMappings.GetEnumerator()) {
    $profile = @(
        $profiles.profiles |
            Where-Object task_kind -eq $mapping.Key
    )[0]
    foreach ($requiredGate in @($mapping.Value)) {
        if ($requiredGate -notin @($profile.quality_gates)) {
            $failures.Add(
                "quality_gate_mapping_missing:$($mapping.Key):$requiredGate"
            )
        }
    }
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
    'QualityObservation'
    'QualityDecision'
    'discussion_delta_integrity'
    'canonical_source_digest'
    'confirmed_adjustment'
    'candidate_option'
    'rejected_option'
    'clarification_only'
    'load_bearing_units'
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
if ([string]$moduleRegistry.profile_id -ne $expectedProfileId) {
    $failures.Add('module_registry_release_id_mismatch')
}
foreach ($coreModule in @(
    'learning_loop',
    'review_planner',
    'model_case_capture',
    'file_ontology',
    'asset_reuse',
    'share_card_body',
    'search_lite',
    'creation_lite',
    'quality_gate',
    'problem_regression_suite'
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

$functionGuide = Get-Content `
    -LiteralPath (Join-Path $Root 'docs\功能与操作流程.md') `
    -Raw `
    -Encoding UTF8
foreach ($requiredFunctionGuideText in @(
    '质量门操作'
    'QualityObservation'
    'QualityDecision'
    'discussion_delta_integrity'
    'apply_confirmed_deltas_only'
    'evaluate-quality-gate-lite.ps1'
)) {
    Require-Text `
        -Text $functionGuide `
        -Pattern $requiredFunctionGuideText `
        -Failure "function_guide_missing:$requiredFunctionGuideText"
}

$upgradeGuide = Get-Content `
    -LiteralPath (Join-Path $Root 'docs\可升级模块地图.md') `
    -Raw `
    -Encoding UTF8
foreach ($requiredUpgradeGuideText in @(
    'QualityGate'
    'ProblemRegressionSuite'
    'discussion_delta_integrity'
    '不获得写入'
    '行为级回归'
)) {
    Require-Text `
        -Text $upgradeGuide `
        -Pattern $requiredUpgradeGuideText `
        -Failure "upgrade_guide_missing:$requiredUpgradeGuideText"
}

$chatGuidePath = Join-Path $Root 'docs\对外聊天简要说明.md'
if (-not (Test-Path -LiteralPath $chatGuidePath -PathType Leaf)) {
    $failures.Add('chat_guide_missing')
}
else {
    $chatGuide = Get-Content `
        -LiteralPath $chatGuidePath `
        -Raw `
        -Encoding UTF8
    foreach ($requiredChatGuideText in @(
        '直接复制版'
        '拆解问答'
        '迁移问答'
        '复习计划'
        '模型、案例和本体关系'
        '分享卡'
        '按需复用'
        '没有捆绑本地大模型'
        '最小规则'
        '确认差量'
        'ZIP'
        '安装到一个新文件夹'
        '运行自带验证'
    )) {
        Require-Text `
            -Text $chatGuide `
            -Pattern $requiredChatGuideText `
            -Failure "chat_guide_missing:$requiredChatGuideText"
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
