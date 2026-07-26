[CmdletBinding()]
param([string]$Root = (Split-Path -Parent $PSScriptRoot))

$ErrorActionPreference = 'Stop'
$gatePath = Join-Path $Root 'scripts\evaluate-quality-gate-lite.ps1'

if (-not (Test-Path -LiteralPath $gatePath -PathType Leaf)) {
    "FAIL: quality_gate_interface_missing"
    "SUMMARY: problem regression scenarios failed (1)"
    exit 1
}

function Invoke-QualityGate {
    param([System.Collections.IDictionary]$Request)

    $requestJson = $Request | ConvertTo-Json -Compress -Depth 12
    $global:LASTEXITCODE = 0
    $outputItems = @(
        & $gatePath -ObservationJson $requestJson -Root $Root
    )
    $succeeded = $?
    $exitCode = $LASTEXITCODE
    $raw = $outputItems -join "`n"
    if (-not $succeeded -or $exitCode -ne 0) {
        throw "Quality gate failed to execute: $raw"
    }
    return ($raw | ConvertFrom-Json)
}

$failures = [Collections.Generic.List[string]]::new()

$teachingMissing = Invoke-QualityGate -Request ([ordered]@{
    schema = 'contentos-lite-quality-observation-v1'
    observation_id = 'REG-TEACHING-BEFORE-TEST-RED'
    gate = 'teaching_before_test'
    task_kind = 'decomposition_qa_lite'
    facts = [ordered]@{
        teaching_visible = $false
        test_requested = $true
    }
})

if ([string]$teachingMissing.status -ne 'valid') {
    $failures.Add('teaching_missing_status_not_valid')
}
if ([string]$teachingMissing.decision -ne 'return_upstream') {
    $failures.Add('teaching_missing_not_returned_upstream')
}
if ([string]$teachingMissing.earliest_failure_layer -ne 'teaching') {
    $failures.Add('teaching_missing_wrong_failure_layer')
}
if ('deliver_teaching' -notin @($teachingMissing.next_actions)) {
    $failures.Add('teaching_missing_next_action_absent')
}

$leakedTransfer = Invoke-QualityGate -Request ([ordered]@{
    schema = 'contentos-lite-quality-observation-v1'
    observation_id = 'REG-TRANSFER-ANSWER-LEAK'
    gate = 'transfer_integrity'
    task_kind = 'transfer_qa_lite'
    facts = [ordered]@{
        required_inputs_present = $true
        answer_route_leaked = $true
        mechanism_match = 'unknown'
        boundary_differences_identified = $false
    }
})

if ([string]$leakedTransfer.decision -ne 'targeted_repair') {
    $failures.Add('transfer_leak_not_targeted_repair')
}
if ([string]$leakedTransfer.earliest_failure_layer -ne 'question_design') {
    $failures.Add('transfer_leak_wrong_failure_layer')
}
if ('answer_route_leaked' -notin @($leakedTransfer.violations)) {
    $failures.Add('transfer_leak_violation_absent')
}
if ('redesign_transfer_prompt' -notin @($leakedTransfer.next_actions)) {
    $failures.Add('transfer_leak_next_action_absent')
}

$missingTransferInputs = Invoke-QualityGate -Request ([ordered]@{
    schema = 'contentos-lite-quality-observation-v1'
    observation_id = 'REG-TRANSFER-INPUT-CLOSURE'
    gate = 'transfer_integrity'
    task_kind = 'transfer_qa_lite'
    facts = [ordered]@{
        required_inputs_present = $false
        answer_route_leaked = $false
        mechanism_match = 'unknown'
        boundary_differences_identified = $false
    }
})

if ([string]$missingTransferInputs.decision -ne 'return_upstream') {
    $failures.Add('missing_transfer_inputs_not_returned_upstream')
}
if (
    [string]$missingTransferInputs.earliest_failure_layer -ne
        'input_closure'
) {
    $failures.Add('missing_transfer_inputs_wrong_failure_layer')
}
if (
    'transfer_inputs_missing' -notin
        @($missingTransferInputs.violations)
) {
    $failures.Add('missing_transfer_inputs_violation_absent')
}
if (
    'bind_transfer_inputs' -notin
        @($missingTransferInputs.next_actions)
) {
    $failures.Add('missing_transfer_inputs_next_action_absent')
}

$surfaceSimilarAsset = Invoke-QualityGate -Request ([ordered]@{
    schema = 'contentos-lite-quality-observation-v1'
    observation_id = 'REG-ASSET-SURFACE-SIMILARITY'
    gate = 'asset_reuse'
    task_kind = 'learning_teaching_lite'
    facts = [ordered]@{
        mechanism_match = $false
        net_gain = $true
        conflict_detected = $false
        body_required_for_decision = $false
    }
})

if ([string]$surfaceSimilarAsset.decision -ne 'pass') {
    $failures.Add('surface_similar_asset_gate_not_pass')
}
if (
    [string]$surfaceSimilarAsset.result.reuse_decision -ne
        'no_use'
) {
    $failures.Add('surface_similar_asset_not_rejected')
}
if ('continue_without_asset' -notin @($surfaceSimilarAsset.next_actions)) {
    $failures.Add('surface_similar_asset_next_action_absent')
}

$lowGainAsset = Invoke-QualityGate -Request ([ordered]@{
    schema = 'contentos-lite-quality-observation-v1'
    observation_id = 'REG-ASSET-NO-NET-GAIN'
    gate = 'asset_reuse'
    task_kind = 'learning_teaching_lite'
    facts = [ordered]@{
        mechanism_match = $true
        net_gain = $false
        conflict_detected = $false
        body_required_for_decision = $false
    }
})

if ([string]$lowGainAsset.result.reuse_decision -ne 'no_use') {
    $failures.Add('low_gain_asset_not_rejected')
}
if ($lowGainAsset.result.body_load_allowed -ne $false) {
    $failures.Add('low_gain_asset_body_exposed')
}
if ('continue_without_asset' -notin @($lowGainAsset.next_actions)) {
    $failures.Add('low_gain_asset_next_action_absent')
}

$loadBearingAsset = Invoke-QualityGate -Request ([ordered]@{
    schema = 'contentos-lite-quality-observation-v1'
    observation_id = 'REG-ASSET-LOAD-BEARING-USE'
    gate = 'asset_reuse'
    task_kind = 'transfer_qa_lite'
    facts = [ordered]@{
        mechanism_match = $true
        net_gain = $true
        conflict_detected = $false
        body_required_for_decision = $true
    }
})

if ([string]$loadBearingAsset.result.reuse_decision -ne 'use') {
    $failures.Add('load_bearing_asset_not_selected')
}
if ($loadBearingAsset.result.body_load_allowed -ne $true) {
    $failures.Add('load_bearing_asset_body_not_allowed')
}
if ('load_selected_asset_body' -notin @($loadBearingAsset.next_actions)) {
    $failures.Add('load_bearing_asset_next_action_absent')
}

$conflictedAsset = Invoke-QualityGate -Request ([ordered]@{
    schema = 'contentos-lite-quality-observation-v1'
    observation_id = 'REG-ASSET-CONFLICTED-BACKSTAGE'
    gate = 'asset_reuse'
    task_kind = 'learning_teaching_lite'
    facts = [ordered]@{
        mechanism_match = $true
        net_gain = $true
        conflict_detected = $true
        body_required_for_decision = $true
    }
})

if ([string]$conflictedAsset.result.reuse_decision -ne 'backstage') {
    $failures.Add('conflicted_asset_not_backstage')
}
if ($conflictedAsset.result.body_load_allowed -ne $false) {
    $failures.Add('conflicted_asset_body_exposed')
}
if (
    'use_for_calibration_only' -notin
        @($conflictedAsset.next_actions)
) {
    $failures.Add('conflicted_asset_next_action_absent')
}

$incompleteShare = Invoke-QualityGate -Request ([ordered]@{
    schema = 'contentos-lite-quality-observation-v1'
    observation_id = 'REG-SHARE-INCOMPLETE-QA'
    gate = 'share_completeness'
    task_kind = 'share_card_lite'
    facts = [ordered]@{
        required_question_count = 3
        paired_answer_count = 2
        transfer_case_complete = $false
        input_conditions_present = $true
        reasoning_present = $true
        backend_scaffolding_exposed = $false
    }
})

if ([string]$incompleteShare.decision -ne 'targeted_repair') {
    $failures.Add('incomplete_share_not_targeted_repair')
}
if ([string]$incompleteShare.earliest_failure_layer -ne 'share_body') {
    $failures.Add('incomplete_share_wrong_failure_layer')
}
if (
    'question_answer_pair_missing' -notin
        @($incompleteShare.violations) -or
    'transfer_case_incomplete' -notin
        @($incompleteShare.violations)
) {
    $failures.Add('incomplete_share_violations_incomplete')
}
if ('repair_missing_share_units' -notin @($incompleteShare.next_actions)) {
    $failures.Add('incomplete_share_next_action_absent')
}

$overflowTruncation = Invoke-QualityGate -Request ([ordered]@{
    schema = 'contentos-lite-quality-observation-v1'
    observation_id = 'REG-CAPACITY-NO-SEMANTIC-TRUNCATION'
    gate = 'capacity_preservation'
    task_kind = 'share_card_lite'
    facts = [ordered]@{
        capacity_state = 'overflow'
        proposed_action = 'truncate_semantics'
        load_bearing_units_present = $true
    }
})

if ([string]$overflowTruncation.decision -ne 'blocked') {
    $failures.Add('overflow_truncation_not_blocked')
}
if (
    [string]$overflowTruncation.earliest_failure_layer -ne
        'capacity_decision'
) {
    $failures.Add('overflow_truncation_wrong_failure_layer')
}
if (
    'semantic_truncation_attempted' -notin
        @($overflowTruncation.violations)
) {
    $failures.Add('overflow_truncation_violation_absent')
}
if (
    'split_scope' -notin @($overflowTruncation.next_actions) -or
    'request_user_choice' -notin @($overflowTruncation.next_actions)
) {
    $failures.Add('overflow_truncation_safe_routes_absent')
}

$diffuseCreation = Invoke-QualityGate -Request ([ordered]@{
    schema = 'contentos-lite-quality-observation-v1'
    observation_id = 'REG-CREATION-DIFFUSE-MAINLINE'
    gate = 'creation_coherence'
    task_kind = 'content_creation_lite'
    facts = [ordered]@{
        primary_judgment_present = $false
        mainline_coherent = $false
        unbound_branch_count = 4
        contributions_bound_to_mainline = $false
    }
})

if ([string]$diffuseCreation.decision -ne 'return_upstream') {
    $failures.Add('diffuse_creation_not_returned_upstream')
}
if (
    [string]$diffuseCreation.earliest_failure_layer -ne
        'content_kernel'
) {
    $failures.Add('diffuse_creation_wrong_failure_layer')
}
if (
    'primary_judgment_missing' -notin
        @($diffuseCreation.violations) -or
    'mainline_diffuse' -notin @($diffuseCreation.violations)
) {
    $failures.Add('diffuse_creation_violations_incomplete')
}
if ('revise_content_kernel' -notin @($diffuseCreation.next_actions)) {
    $failures.Add('diffuse_creation_next_action_absent')
}
if ($diffuseCreation.full_rewrite_allowed -ne $true) {
    $failures.Add('diffuse_creation_full_rewrite_not_allowed')
}

$overbroadRevision = Invoke-QualityGate -Request ([ordered]@{
    schema = 'contentos-lite-quality-observation-v1'
    observation_id = 'REG-REVISION-NO-BLIND-FULL-REWRITE'
    gate = 'revision_scope'
    task_kind = 'content_review_lite'
    facts = [ordered]@{
        earliest_failure_layer = 'paragraph'
        kernel_failed = $false
        reasoning_spine_failed = $false
        proposed_full_rewrite = $true
        failed_draft_used_as_source = $false
        passed_sections = @('opening', 'case')
    }
})

if ([string]$overbroadRevision.decision -ne 'targeted_repair') {
    $failures.Add('overbroad_revision_not_targeted')
}
if (
    'full_rewrite_without_upstream_failure' -notin
        @($overbroadRevision.violations)
) {
    $failures.Add('overbroad_revision_violation_absent')
}
if ($overbroadRevision.full_rewrite_allowed -ne $false) {
    $failures.Add('overbroad_revision_full_rewrite_allowed')
}
if (
    @($overbroadRevision.frozen_surfaces).Count -ne 2 -or
    'opening' -notin @($overbroadRevision.frozen_surfaces) -or
    'case' -notin @($overbroadRevision.frozen_surfaces)
) {
    $failures.Add('overbroad_revision_passed_surfaces_not_frozen')
}
if (
    'repair_failed_section_only' -notin
        @($overbroadRevision.next_actions)
) {
    $failures.Add('overbroad_revision_next_action_absent')
}

$failedDraftSource = Invoke-QualityGate -Request ([ordered]@{
    schema = 'contentos-lite-quality-observation-v1'
    observation_id = 'REG-REVISION-FAILED-DRAFT-NOT-TRUTH'
    gate = 'revision_scope'
    task_kind = 'content_review_lite'
    facts = [ordered]@{
        earliest_failure_layer = 'source_selection'
        kernel_failed = $false
        reasoning_spine_failed = $false
        proposed_full_rewrite = $false
        failed_draft_used_as_source = $true
        passed_sections = @()
    }
})

if ([string]$failedDraftSource.decision -ne 'blocked') {
    $failures.Add('failed_draft_source_not_blocked')
}
if (
    [string]$failedDraftSource.earliest_failure_layer -ne
        'source_selection'
) {
    $failures.Add('failed_draft_source_wrong_failure_layer')
}
if (
    'failed_draft_as_truth_source' -notin
        @($failedDraftSource.violations)
) {
    $failures.Add('failed_draft_source_violation_absent')
}
if (
    'rebind_canonical_source' -notin
        @($failedDraftSource.next_actions)
) {
    $failures.Add('failed_draft_source_next_action_absent')
}

$singleAuthorshipSignal = Invoke-QualityGate -Request ([ordered]@{
    schema = 'contentos-lite-quality-observation-v1'
    observation_id = 'REG-AUTHORSHIP-SINGLE-SIGNAL-NOT-FAIL'
    gate = 'authorship_quality'
    task_kind = 'content_review_lite'
    facts = [ordered]@{
        independent_signal_clusters = 1
        reader_loss_present = $true
        fake_experience_or_noise = $false
    }
})

if ([string]$singleAuthorshipSignal.decision -ne 'pass') {
    $failures.Add('single_authorship_signal_false_positive')
}
if (@($singleAuthorshipSignal.violations).Count -ne 0) {
    $failures.Add('single_authorship_signal_violation_emitted')
}

$fabricatedHumanity = Invoke-QualityGate -Request ([ordered]@{
    schema = 'contentos-lite-quality-observation-v1'
    observation_id = 'REG-AUTHORSHIP-NO-FAKE-HUMANITY'
    gate = 'authorship_quality'
    task_kind = 'content_review_lite'
    facts = [ordered]@{
        independent_signal_clusters = 0
        reader_loss_present = $false
        fake_experience_or_noise = $true
    }
})

if ([string]$fabricatedHumanity.decision -ne 'targeted_repair') {
    $failures.Add('fabricated_humanity_not_targeted_repair')
}
if (
    'fabricated_humanity_signal' -notin
        @($fabricatedHumanity.violations)
) {
    $failures.Add('fabricated_humanity_violation_absent')
}
if (
    'remove_fabricated_humanity' -notin
        @($fabricatedHumanity.next_actions)
) {
    $failures.Add('fabricated_humanity_next_action_absent')
}

$discussionPollution = Invoke-QualityGate -Request ([ordered]@{
    schema = 'contentos-lite-quality-observation-v1'
    observation_id = 'REG-DISCUSSION-DELTA-NO-POLLUTION'
    gate = 'discussion_delta_integrity'
    task_kind = 'content_creation_lite'
    facts = [ordered]@{
        canonical_source_bound = $true
        canonical_load_bearing_unit_count = 5
        preserved_load_bearing_unit_count = 4
        confirmed_adjustment_ids = @('ADJ-1')
        applied_adjustment_ids = @('ADJ-1', 'OPTION-2')
        candidate_option_ids = @('OPTION-2')
        rejected_option_ids = @()
        clarification_only_ids = @()
        explicit_deletion_authorized = $false
    }
})

if ([string]$discussionPollution.decision -ne 'targeted_repair') {
    $failures.Add('discussion_pollution_not_targeted_repair')
}
if (
    [string]$discussionPollution.earliest_failure_layer -ne
        'source_projection'
) {
    $failures.Add('discussion_pollution_wrong_failure_layer')
}
if (
    'unconfirmed_discussion_applied' -notin
        @($discussionPollution.violations) -or
    'canonical_content_dropped' -notin
        @($discussionPollution.violations)
) {
    $failures.Add('discussion_pollution_violations_incomplete')
}
if (
    'rebind_canonical_source' -notin
        @($discussionPollution.next_actions) -or
    'apply_confirmed_deltas_only' -notin
        @($discussionPollution.next_actions) -or
    'restore_load_bearing_units' -notin
        @($discussionPollution.next_actions)
) {
    $failures.Add('discussion_pollution_recovery_incomplete')
}
if ($discussionPollution.full_rewrite_allowed -ne $false) {
    $failures.Add('discussion_pollution_full_rewrite_allowed')
}

$shareDiscussionPollution = Invoke-QualityGate -Request ([ordered]@{
    schema = 'contentos-lite-quality-observation-v1'
    observation_id = 'REG-SHARE-DISCUSSION-NO-POLLUTION'
    gate = 'discussion_delta_integrity'
    task_kind = 'share_card_lite'
    facts = [ordered]@{
        canonical_source_bound = $true
        canonical_load_bearing_unit_count = 8
        preserved_load_bearing_unit_count = 6
        confirmed_adjustment_ids = @('ADJ-TITLE')
        applied_adjustment_ids = @(
            'ADJ-TITLE'
            'OPTION-REMOVE-QUESTION'
        )
        candidate_option_ids = @('OPTION-REMOVE-QUESTION')
        rejected_option_ids = @()
        clarification_only_ids = @()
        explicit_deletion_authorized = $false
    }
})

if ([string]$shareDiscussionPollution.decision -ne 'targeted_repair') {
    $failures.Add('share_discussion_pollution_not_targeted')
}
if (
    'unconfirmed_discussion_applied' -notin
        @($shareDiscussionPollution.violations) -or
    'canonical_content_dropped' -notin
        @($shareDiscussionPollution.violations)
) {
    $failures.Add('share_discussion_pollution_not_detected')
}
if (
    'restore_load_bearing_units' -notin
        @($shareDiscussionPollution.next_actions)
) {
    $failures.Add('share_discussion_original_not_restored')
}

$unsupportedConfirmedClaim = Invoke-QualityGate -Request ([ordered]@{
    schema = 'contentos-lite-quality-observation-v1'
    observation_id = 'REG-SEARCH-CLAIM-CALIBRATION'
    gate = 'search_claim_calibration'
    task_kind = 'web_search_lite'
    facts = [ordered]@{
        direct_source_support = $false
        multi_fact_inference = $true
        current_best_basis_present = $true
        proposed_claim_class = 'confirmed'
    }
})

if (
    [string]$unsupportedConfirmedClaim.decision -ne
        'targeted_repair'
) {
    $failures.Add('unsupported_confirmed_claim_not_repaired')
}
if (
    [string]$unsupportedConfirmedClaim.result.claim_class -ne
        'inference'
) {
    $failures.Add('unsupported_confirmed_claim_wrong_class')
}
if (
    'unsupported_confirmed_claim' -notin
        @($unsupportedConfirmedClaim.violations)
) {
    $failures.Add('unsupported_confirmed_claim_violation_absent')
}
if (
    'relabel_claim' -notin
        @($unsupportedConfirmedClaim.next_actions)
) {
    $failures.Add('unsupported_confirmed_claim_next_action_absent')
}

$overbroadRightsBlock = Invoke-QualityGate -Request ([ordered]@{
    schema = 'contentos-lite-quality-observation-v1'
    observation_id = 'REG-RIGHTS-LOCAL-BLOCK-ONLY'
    gate = 'rights_scope'
    task_kind = 'share_card_lite'
    facts = [ordered]@{
        rights_status = 'unclear'
        restricted_element_count = 1
        original_transformation_possible = $true
        proposed_whole_work_block = $true
    }
})

if ([string]$overbroadRightsBlock.decision -ne 'targeted_repair') {
    $failures.Add('overbroad_rights_block_not_targeted')
}
if (
    [string]$overbroadRightsBlock.earliest_failure_layer -ne
        'rights_scope'
) {
    $failures.Add('overbroad_rights_block_wrong_failure_layer')
}
if (
    'overbroad_rights_block' -notin
        @($overbroadRightsBlock.violations)
) {
    $failures.Add('overbroad_rights_block_violation_absent')
}
if (
    'isolate_restricted_elements' -notin
        @($overbroadRightsBlock.next_actions) -or
    'continue_original_transformation' -notin
        @($overbroadRightsBlock.next_actions)
) {
    $failures.Add('overbroad_rights_block_safe_route_absent')
}

$maladaptiveReview = Invoke-QualityGate -Request ([ordered]@{
    schema = 'contentos-lite-quality-observation-v1'
    observation_id = 'REG-REVIEW-TRANSFER-FAILURE-ADAPTS'
    gate = 'review_adaptation'
    task_kind = 'review_schedule_lite'
    facts = [ordered]@{
        dominant_signal = 'transfer_failure'
        proposed_action = 'repeat_same_question'
    }
})

if ([string]$maladaptiveReview.decision -ne 'targeted_repair') {
    $failures.Add('maladaptive_review_not_targeted')
}
if (
    [string]$maladaptiveReview.result.recommended_action -ne
        'new_transfer_scenario'
) {
    $failures.Add('maladaptive_review_wrong_recommendation')
}
if (
    'maladaptive_review_action' -notin
        @($maladaptiveReview.violations)
) {
    $failures.Add('maladaptive_review_violation_absent')
}
if (
    'schedule_new_transfer_scenario' -notin
        @($maladaptiveReview.next_actions)
) {
    $failures.Add('maladaptive_review_next_action_absent')
}

$unauthorizedCreationTrack = Invoke-QualityGate -Request ([ordered]@{
    schema = 'contentos-lite-quality-observation-v1'
    observation_id = 'REG-TRACK-NO-AUTO-CREATION'
    gate = 'track_authority'
    task_kind = 'learning_close_lite'
    facts = [ordered]@{
        source_track = 'LearningTrack'
        proposed_target_track = 'CreationTrack'
        explicit_creation_authority = $false
        trigger = 'shareable_learning_result'
    }
})

if ([string]$unauthorizedCreationTrack.decision -ne 'blocked') {
    $failures.Add('unauthorized_creation_track_not_blocked')
}
if (
    [string]$unauthorizedCreationTrack.earliest_failure_layer -ne
        'track_authority'
) {
    $failures.Add('unauthorized_creation_track_wrong_failure_layer')
}
if (
    'creation_without_authority' -notin
        @($unauthorizedCreationTrack.violations)
) {
    $failures.Add('unauthorized_creation_track_violation_absent')
}
if (
    'remain_learning_track' -notin
        @($unauthorizedCreationTrack.next_actions)
) {
    $failures.Add('unauthorized_creation_track_safe_route_absent')
}

$startupPath = Join-Path $Root 'scripts\resolve-startup-lite.ps1'
$shareStartupInput = [ordered]@{
    learning_result = 'fixture:learning-result'
    share_scope = 'fixture:ordinary-share-card'
} | ConvertTo-Json -Compress
$shareStartup = @(
    & $startupPath `
        -TaskKind share_card_lite `
        -InputsJson $shareStartupInput `
        -Root $Root
) -join "`n" | ConvertFrom-Json

if ([string]$shareStartup.status -ne 'ready') {
    $failures.Add('share_startup_not_ready')
}
$shareGates = @(
    $shareStartup.generator_view.quality_gate_interface.gates
)
foreach ($requiredShareGate in @(
    'share_completeness'
    'capacity_preservation'
    'discussion_delta_integrity'
    'rights_scope'
    'track_authority'
)) {
    if ($requiredShareGate -notin $shareGates) {
        $failures.Add(
            "share_quality_gate_not_projected:$requiredShareGate"
        )
    }
}
if (
    [string]$shareStartup.generator_view.quality_gate_interface.tool -ne
        'scripts/evaluate-quality-gate-lite.ps1'
) {
    $failures.Add('share_quality_gate_tool_not_projected')
}

$incompleteObservation = Invoke-QualityGate -Request ([ordered]@{
    schema = 'contentos-lite-quality-observation-v1'
    observation_id = 'REG-OBSERVATION-CLOSURE-FAIL-CLOSED'
    gate = 'share_completeness'
    task_kind = 'share_card_lite'
    facts = [ordered]@{
        required_question_count = 3
    }
})

if ([string]$incompleteObservation.decision -ne 'blocked') {
    $failures.Add('incomplete_observation_not_blocked')
}
if (
    [string]$incompleteObservation.earliest_failure_layer -ne
        'observation_closure'
) {
    $failures.Add('incomplete_observation_wrong_failure_layer')
}
if (
    'missing_observations' -notin
        @($incompleteObservation.violations)
) {
    $failures.Add('incomplete_observation_violation_absent')
}
if (
    'paired_answer_count' -notin
        @($incompleteObservation.result.missing_fields) -or
    'transfer_case_complete' -notin
        @($incompleteObservation.result.missing_fields)
) {
    $failures.Add('incomplete_observation_missing_fields_absent')
}

$multiSignalAuthorshipLoss = Invoke-QualityGate -Request ([ordered]@{
    schema = 'contentos-lite-quality-observation-v1'
    observation_id = 'REG-AUTHORSHIP-MULTI-SIGNAL-LOSS'
    gate = 'authorship_quality'
    task_kind = 'content_review_lite'
    facts = [ordered]@{
        independent_signal_clusters = 2
        reader_loss_present = $true
        fake_experience_or_noise = $false
    }
})

if (
    [string]$multiSignalAuthorshipLoss.decision -ne
        'targeted_repair'
) {
    $failures.Add('multi_signal_authorship_loss_not_repaired')
}
if (
    'multi_signal_authorship_loss' -notin
        @($multiSignalAuthorshipLoss.violations)
) {
    $failures.Add('multi_signal_authorship_loss_violation_absent')
}

$confirmedDiscussionOnly = Invoke-QualityGate -Request ([ordered]@{
    schema = 'contentos-lite-quality-observation-v1'
    observation_id = 'REG-DISCUSSION-CONFIRMED-DELTA-PASSES'
    gate = 'discussion_delta_integrity'
    task_kind = 'share_card_lite'
    facts = [ordered]@{
        canonical_source_bound = $true
        canonical_load_bearing_unit_count = 8
        preserved_load_bearing_unit_count = 8
        confirmed_adjustment_ids = @('ADJ-TITLE')
        applied_adjustment_ids = @('ADJ-TITLE')
        candidate_option_ids = @('OPTION-2')
        rejected_option_ids = @('OPTION-3')
        clarification_only_ids = @('CLARIFY-1')
        explicit_deletion_authorized = $false
    }
})

if ([string]$confirmedDiscussionOnly.decision -ne 'pass') {
    $failures.Add('confirmed_discussion_delta_false_positive')
}
if (@($confirmedDiscussionOnly.violations).Count -ne 0) {
    $failures.Add('confirmed_discussion_delta_violation_emitted')
}

$validKernelRewrite = Invoke-QualityGate -Request ([ordered]@{
    schema = 'contentos-lite-quality-observation-v1'
    observation_id = 'REG-REVISION-KERNEL-FAIL-ALLOWS-REWRITE'
    gate = 'revision_scope'
    task_kind = 'content_review_lite'
    facts = [ordered]@{
        earliest_failure_layer = 'content_kernel'
        kernel_failed = $true
        reasoning_spine_failed = $false
        proposed_full_rewrite = $true
        failed_draft_used_as_source = $false
        passed_sections = @()
    }
})

if ([string]$validKernelRewrite.decision -ne 'pass') {
    $failures.Add('valid_kernel_rewrite_blocked')
}
if ($validKernelRewrite.full_rewrite_allowed -ne $true) {
    $failures.Add('valid_kernel_rewrite_not_allowed')
}

$validScopeSplit = Invoke-QualityGate -Request ([ordered]@{
    schema = 'contentos-lite-quality-observation-v1'
    observation_id = 'REG-CAPACITY-SCOPE-SPLIT-PASSES'
    gate = 'capacity_preservation'
    task_kind = 'share_card_lite'
    facts = [ordered]@{
        capacity_state = 'overflow'
        proposed_action = 'split_scope'
        load_bearing_units_present = $true
    }
})

if ([string]$validScopeSplit.decision -ne 'pass') {
    $failures.Add('valid_scope_split_blocked')
}

$authorizedCreationTrack = Invoke-QualityGate -Request ([ordered]@{
    schema = 'contentos-lite-quality-observation-v1'
    observation_id = 'REG-TRACK-EXPLICIT-CREATION-PASSES'
    gate = 'track_authority'
    task_kind = 'content_creation_lite'
    facts = [ordered]@{
        source_track = 'LearningTrack'
        proposed_target_track = 'CreationTrack'
        explicit_creation_authority = $true
        trigger = 'explicit_creation_request'
    }
})

if ([string]$authorizedCreationTrack.decision -ne 'pass') {
    $failures.Add('authorized_creation_track_blocked')
}

$completeShare = Invoke-QualityGate -Request ([ordered]@{
    schema = 'contentos-lite-quality-observation-v1'
    observation_id = 'REG-SHARE-COMPLETE-PASSES'
    gate = 'share_completeness'
    task_kind = 'share_card_lite'
    facts = [ordered]@{
        required_question_count = 3
        paired_answer_count = 3
        transfer_case_complete = $true
        input_conditions_present = $true
        reasoning_present = $true
        backend_scaffolding_exposed = $false
    }
})

if ([string]$completeShare.decision -ne 'pass') {
    $failures.Add('complete_share_false_positive')
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { "FAIL: $_" }
    "SUMMARY: problem regression scenarios failed ($($failures.Count))"
    exit 1
}

"SUMMARY: problem regression scenarios passed (28)"
