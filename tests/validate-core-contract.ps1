[CmdletBinding()]
param([string]$Root)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Split-Path -Parent $PSScriptRoot
}
$Root = [IO.Path]::GetFullPath($Root)
$failures = [Collections.Generic.List[string]]::new()
$releaseId = 'contentos-v0.2.0-rc.2'

function Require-File {
    param([string]$Relative)
    if (-not (Test-Path -LiteralPath (Join-Path $Root $Relative) -PathType Leaf)) {
        $failures.Add("missing_file:$Relative")
    }
}

foreach ($file in Get-ChildItem -LiteralPath $Root -Recurse -File -Filter '*.json') {
    try {
        $null = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 |
            ConvertFrom-Json
    }
    catch {
        $relative = $file.FullName.Substring($Root.Length).TrimStart('\', '/')
        $failures.Add("invalid_json:$relative")
    }
}

foreach ($required in @(
    'README.md', 'AGENTS.md', 'LICENSE', 'LICENSE-DOCS.md',
    'CONTRIBUTING.md', 'SECURITY.md', 'MANIFEST.json',
    'core\profiles\task-profiles.json',
    'core\capabilities\public-capability-map.json',
    'core\upgrades\module-registry.json',
    'core\schemas\adapter-binding.schema.json',
    'core\schemas\task-execution-input.schema.json',
    'templates\adapter-binding.json',
    'scripts\resolve-contentos-startup.ps1',
    'scripts\invoke-contentos-external-client-boundary.ps1',
    'scripts\init-contentos.ps1',
    'scripts\evaluate-contentos-quality-gate.ps1',
    'docs\对外聊天简要说明.md',
    'docs\功能与操作流程.md',
    '.agents\skills\contentos-external-proposal\SKILL.md'
)) {
    Require-File -Relative $required
}

$creationRule = Get-Content -LiteralPath (
    Join-Path $Root 'core\rules\06-content-creation.md'
) -Raw -Encoding UTF8
foreach ($marker in @(
    '纯文字任务不创建 `MediaExecutionPlan`',
    'footage_edit / programmable_motion / longform_repurpose / generated_sequence / hybrid',
    'styleframe / shot_recipe / motion_canary / timeline_segment / candidate_reel / full_short',
    'preview.validates / preview.cannot_prove / expansion_authority',
    '可编辑交付指针',
    '来源、权利与生成过程的 provenance',
    '不自动授权整片扩展、批量生成或发布',
    '## 共用阶段引导',
    '零至三个会实质改变判断、路线、成本、权利、扩展范围或成品效果的选择',
    '最多一个当前无法可靠代选的承重问题',
    'auto_continue / wait_for_user / complete / paused',
    '用户要求只给成品时把引导留在后台',
    'StageGuide 不新增 TaskKind、状态 owner、回执、常驻阶段包或人工闸门'
)) {
    if (-not $creationRule.Contains($marker)) {
        $failures.Add("creation_media_execution_contract_missing:$marker")
    }
}

function Resolve-PublicStageGuide {
    param(
        [string]$Stage,
        [object[]]$Choices = @(),
        [string]$Question = '',
        [ValidateSet('auto_continue','wait_for_user','complete','paused')]
        [string]$Advance,
        [AllowNull()][string]$NextStage
    )
    $distinct = @(
        $Choices |
            Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.delta) } |
            Group-Object family |
            ForEach-Object { $_.Group[0] }
    )
    if ($distinct.Count -gt 3) { throw 'too_many_visible_choices' }
    $hasQuestion = -not [string]::IsNullOrWhiteSpace($Question)
    if ($Advance -eq 'auto_continue' -and ($hasQuestion -or $distinct.Count -ne 0)) {
        throw 'auto_continue_must_not_wait'
    }
    if ($Advance -eq 'wait_for_user' -and -not $hasQuestion -and $distinct.Count -lt 2) {
        throw 'waiting_without_real_decision'
    }
    if ($Advance -in @('complete','paused') -and -not [string]::IsNullOrWhiteSpace($NextStage)) {
        throw 'terminal_stage_must_not_advance'
    }
    [pscustomobject]@{
        stage = $Stage
        choices = $distinct
        question = if ($hasQuestion) { $Question } else { $null }
        advance = $Advance
        next_stage = if ([string]::IsNullOrWhiteSpace($NextStage)) { $null } else { $NextStage }
    }
}

$autoGuide = Resolve-PublicStageGuide -Stage 'kernel' -Advance auto_continue -NextStage 'assembly'
if ($autoGuide.advance -ne 'auto_continue' -or $autoGuide.question -ne $null -or $autoGuide.choices.Count -ne 0) {
    $failures.Add('guided_stage_auto_continue_failed')
}
$choiceGuide = Resolve-PublicStageGuide -Stage 'media_route' -Choices @(
    [pscustomobject]@{family='footage';delta='preserve_real_scene'},
    [pscustomobject]@{family='motion';delta='replace_with_motion_explanation'},
    [pscustomobject]@{family='footage';delta='wording_only_duplicate'}
) -Question '保留真实现场，还是改成动态图解？' -Advance wait_for_user -NextStage 'preview'
if ($choiceGuide.choices.Count -ne 2 -or $choiceGuide.question -eq $null) {
    $failures.Add('guided_stage_distinct_choice_failed')
}
$pauseGuide = Resolve-PublicStageGuide -Stage 'draft' -Advance paused -NextStage $null
if ($pauseGuide.advance -ne 'paused' -or $pauseGuide.next_stage -ne $null) {
    $failures.Add('guided_stage_pause_failed')
}

$profiles = Get-Content -LiteralPath (
    Join-Path $Root 'core\profiles\task-profiles.json'
) -Raw -Encoding UTF8 | ConvertFrom-Json
$config = Get-Content -LiteralPath (
    Join-Path $Root 'config\contentos.example.json'
) -Raw -Encoding UTF8 | ConvertFrom-Json
$capabilities = Get-Content -LiteralPath (
    Join-Path $Root 'core\capabilities\public-capability-map.json'
) -Raw -Encoding UTF8 | ConvertFrom-Json
$modules = Get-Content -LiteralPath (
    Join-Path $Root 'core\upgrades\module-registry.json'
) -Raw -Encoding UTF8 | ConvertFrom-Json
$manifest = Get-Content -LiteralPath (
    Join-Path $Root 'MANIFEST.json'
) -Raw -Encoding UTF8 | ConvertFrom-Json

foreach ($pair in @(
    @('profiles', [string]$profiles.release_id),
    @('config', [string]$config.release_id),
    @('capabilities', [string]$capabilities.release_id),
    @('modules', [string]$modules.release_id),
    @('manifest', [string]$manifest.release_id)
)) {
    if ($pair[1] -ne $releaseId) {
        $failures.Add("release_id_mismatch:$($pair[0]):$($pair[1])")
    }
}

$expectedKinds = @(
    'architecture_maintenance', 'learning_method_correction', 'knowledge_query',
    'fixed_learning_old_knowledge_query', 'model_library_maintenance',
    'public_learning_intake', 'public_information_research',
    'restricted_information_collection', 'platform_video_recovery',
    'non_ergodic_decision_review', 'link_maintenance', 'fixed_learning_intake',
    'fixed_learning_teaching', 'fixed_learning_first_round',
    'fixed_learning_transfer_round', 'learning_transfer_history_backfill',
    'artifact_semantic_review', 'empirical_research_preregistration',
    'empirical_research_execution', 'learning_registry_sync', 'share_card_body',
    'share_visual_local', 'application_discovery', 'direct_topic_creation',
    'content_creation', 'content_review', 'xhs_account_daily_review',
    'thread_recovery'
)
$actualKinds = @($profiles.profiles | ForEach-Object { [string]$_.task_kind })
if ((($actualKinds | Sort-Object) -join '|') -ne
    (($expectedKinds | Sort-Object) -join '|')) {
    $failures.Add('canonical_task_kind_set_mismatch')
}
if (@($actualKinds | Group-Object | Where-Object Count -ne 1).Count -gt 0) {
    $failures.Add('duplicate_task_kind')
}

$quality = $profiles.quality_gate_interface
if (
    [string]$quality.tool -ne 'scripts/evaluate-contentos-quality-gate.ps1' -or
    [string]$quality.input_schema -ne 'contentos-quality-observation-v1' -or
    [string]$quality.output_schema -ne 'contentos-quality-decision-v1' -or
    [string]$quality.side_effects -ne 'none' -or
    [string]$quality.observation_authority -ne
        'caller_supplied_not_independently_verified' -or
    [string]::IsNullOrWhiteSpace([string]$quality.semantic_gate_authority)
) {
    $failures.Add('quality_gate_interface_mismatch')
}
$inputContract = $profiles.input_contract
if ([string]$inputContract.schema -ne 'contentos-input-contract-v1' -or
    [int]$inputContract.max_binding_utf8_bytes -le 0 -or
    [int]$inputContract.max_total_binding_utf8_bytes -lt
        [int]$inputContract.max_binding_utf8_bytes -or
    [int]$inputContract.max_task_execution_input_utf8_bytes -lt
        [int]$inputContract.max_total_binding_utf8_bytes -or
    [int]$inputContract.max_binding_count -lt 5) {
    $failures.Add('input_contract_invalid')
}
$mechanicalGates = @($quality.mechanical_gates | ForEach-Object { [string]$_ })
if ($mechanicalGates.Count -ne 13 -or @($mechanicalGates | Sort-Object -Unique).Count -ne 13) {
    $failures.Add('mechanical_gate_set_invalid')
}
$qualityTool = Join-Path $Root ([string]$quality.tool)
foreach ($gate in $mechanicalGates) {
    $observation = [ordered]@{
        schema = 'contentos-quality-observation-v1'
        observation_id = "support-check-$gate"
        gate = $gate
        task_kind = 'content_review'
        facts = [ordered]@{ contract_probe = $true }
    } | ConvertTo-Json -Compress -Depth 5
    try {
        $decision = & $qualityTool -Root $Root -ObservationJson $observation |
            ConvertFrom-Json
        if ([string]$decision.decision -ne 'blocked' -or
            [string]$decision.earliest_failure_layer -ne 'observation_closure') {
            $failures.Add("mechanical_gate_not_supported:$gate")
        }
    }
    catch {
        $failures.Add("mechanical_gate_throws:$gate")
    }
}

foreach ($profile in @($profiles.profiles)) {
    $kind = [string]$profile.task_kind
    foreach ($field in @('task_stage', 'track', 'objective', 'implementation')) {
        if ([string]::IsNullOrWhiteSpace([string]$profile.$field)) {
            $failures.Add("profile_field_missing:${kind}:$field")
        }
    }
    if (@($profile.required_inputs).Count -eq 0) {
        $failures.Add("required_inputs_empty:$kind")
    }
    foreach ($workspaceRole in @(
        $profile.workspace_required_inputs |
            Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }
    )) {
        if ([string]$workspaceRole -notin @($profile.required_inputs)) {
            $failures.Add("workspace_input_not_required:${kind}:$workspaceRole")
        }
    }
    if (@($profile.quality_gates).Count -eq 0) {
        $failures.Add("quality_gates_empty:$kind")
    }
    foreach ($rule in @($profile.rule_files)) {
        if (-not (Test-Path -LiteralPath (Join-Path $Root ([string]$rule)) -PathType Leaf)) {
            $failures.Add("profile_rule_missing:${kind}:$rule")
        }
    }
    $soft = [int]$profile.budget.soft_target_utf8_bytes
    $advisory = [int]$profile.budget.advisory_ceiling_utf8_bytes
    $hard = [int]$profile.budget.hard_safety_ceiling_utf8_bytes
    if ($soft -le 0 -or $soft -gt $advisory -or $advisory -gt $hard) {
        $failures.Add("budget_order_invalid:$kind")
    }
    if ([string]$profile.implementation -eq 'public_adapter' -and
        [string]::IsNullOrWhiteSpace([string]$profile.adapter_id)) {
        $failures.Add("adapter_id_missing:$kind")
    }
    if ([string]$profile.implementation -eq 'public_adapter' -and (
        [string]::IsNullOrWhiteSpace([string]$profile.adapter_binding_input) -or
        [string]$profile.adapter_binding_input -notin @($profile.required_inputs)
    )) {
        $failures.Add("adapter_binding_input_invalid:$kind")
    }
}

foreach ($module in @($modules.modules)) {
    if ([string]$module.owner -ne 'instance') {
        Require-File -Relative ([string]$module.owner)
    }
}

$vaultContractRoot = if (
    Test-Path -LiteralPath (Join-Path $Root 'vault-template') -PathType Container
) {
    Join-Path $Root 'vault-template'
}
else {
    Join-Path $Root 'vault'
}
$canonicalSurface = @(
    Get-ChildItem -LiteralPath (Join-Path $Root 'core') -Recurse -File
    Get-ChildItem -LiteralPath (Join-Path $Root 'templates') -Recurse -File
    Get-ChildItem -LiteralPath $vaultContractRoot -Recurse -File
) | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8 } |
    Out-String
if ($canonicalSurface -match 'contentos-lite') {
    $failures.Add('legacy_lite_schema_in_canonical_surface')
}

$compatibilityWrappers = @(
    'scripts\resolve-startup-lite.ps1',
    'scripts\init-contentos-lite.ps1',
    'scripts\evaluate-quality-gate-lite.ps1'
)
foreach ($wrapper in $compatibilityWrappers) {
    Require-File -Relative $wrapper
    $lineCount = @(Get-Content -LiteralPath (Join-Path $Root $wrapper)).Count
    if ($lineCount -gt 30) {
        $failures.Add("compatibility_wrapper_too_deep:${wrapper}:$lineCount")
    }
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { "FAIL: $_" }
    "SUMMARY: core contract validation failed ($($failures.Count))"
    exit 1
}
"SUMMARY: core contract validation passed (28 canonical TaskKinds)"
