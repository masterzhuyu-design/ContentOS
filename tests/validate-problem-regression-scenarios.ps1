[CmdletBinding()]
param([string]$Root)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Split-Path -Parent $PSScriptRoot
}
$gateTool = Join-Path $Root 'scripts\evaluate-contentos-quality-gate.ps1'
$failures = [Collections.Generic.List[string]]::new()

$cases = @(
    [ordered]@{id='teaching_missing';gate='teaching_before_test';task='fixed_learning_first_round';facts=[ordered]@{teaching_visible=$false;test_requested=$true};decision='return_upstream';violation='teaching_missing_before_test'},
    [ordered]@{id='teaching_present';gate='teaching_before_test';task='fixed_learning_first_round';facts=[ordered]@{teaching_visible=$true;test_requested=$true};decision='pass'},
    [ordered]@{id='transfer_inputs_missing';gate='transfer_integrity';task='fixed_learning_transfer_round';facts=[ordered]@{required_inputs_present=$false;answer_route_leaked=$false;mechanism_match=$true;boundary_differences_identified=$true};decision='return_upstream';violation='transfer_inputs_missing'},
    [ordered]@{id='transfer_answer_leak';gate='transfer_integrity';task='fixed_learning_transfer_round';facts=[ordered]@{required_inputs_present=$true;answer_route_leaked=$true;mechanism_match=$true;boundary_differences_identified=$true};decision='targeted_repair';violation='answer_route_leaked'},
    [ordered]@{id='transfer_evidence_missing';gate='transfer_integrity';task='fixed_learning_transfer_round';facts=[ordered]@{required_inputs_present=$true;answer_route_leaked=$false;mechanism_match=$true;boundary_differences_identified=$true};decision='return_upstream';violation='transfer_evidence_missing'},
    [ordered]@{id='transfer_same_route_no_gain';gate='transfer_integrity';task='fixed_learning_transfer_round';facts=[ordered]@{required_inputs_present=$true;answer_route_leaked=$false;mechanism_match=$true;boundary_differences_identified=$true;scaffold_profile=[ordered]@{practice_purpose='assessment';user_requested_practice=$false;remediation_target=$null};leakage_map=[ordered]@{current_answer_route_overlap='equivalent';new_load_bearing_inference_count=0;recent_error_evidence=$false}};decision='targeted_repair';violation='transfer_no_incremental_diagnostic_value'},
    [ordered]@{id='transfer_distinct_route';gate='transfer_integrity';task='fixed_learning_transfer_round';facts=[ordered]@{required_inputs_present=$true;answer_route_leaked=$false;mechanism_match=$true;boundary_differences_identified=$true;scaffold_profile=[ordered]@{practice_purpose='assessment';user_requested_practice=$false;remediation_target=$null};leakage_map=[ordered]@{current_answer_route_overlap='partial';new_load_bearing_inference_count=1;recent_error_evidence=$false}};decision='pass';transfer_evidence='fresh_transfer'},
    [ordered]@{id='transfer_real_remediation';gate='transfer_integrity';task='fixed_learning_transfer_round';facts=[ordered]@{required_inputs_present=$true;answer_route_leaked=$false;mechanism_match=$true;boundary_differences_identified=$true;scaffold_profile=[ordered]@{practice_purpose='remediation';user_requested_practice=$false;remediation_target='confused mechanism boundary in latest answer'};leakage_map=[ordered]@{current_answer_route_overlap='equivalent';new_load_bearing_inference_count=0;recent_error_evidence=$true}};decision='pass';transfer_evidence='remediation_practice_only'},
    [ordered]@{id='asset_no_match';gate='asset_reuse';task='fixed_learning_old_knowledge_query';facts=[ordered]@{mechanism_match=$false;net_gain=$true;conflict_detected=$false;body_required_for_decision=$false};decision='pass';reuse='no_use'},
    [ordered]@{id='asset_conflict';gate='asset_reuse';task='fixed_learning_old_knowledge_query';facts=[ordered]@{mechanism_match=$true;net_gain=$true;conflict_detected=$true;body_required_for_decision=$true};decision='pass';reuse='backstage'},
    [ordered]@{id='asset_use';gate='asset_reuse';task='fixed_learning_old_knowledge_query';facts=[ordered]@{mechanism_match=$true;net_gain=$true;conflict_detected=$false;body_required_for_decision=$true};decision='pass';reuse='use'},
    [ordered]@{id='share_pair_missing';gate='share_completeness';task='share_card_body';facts=[ordered]@{required_question_count=2;paired_answer_count=1;transfer_case_complete=$true;input_conditions_present=$true;reasoning_present=$true;backend_scaffolding_exposed=$false};decision='targeted_repair';violation='question_answer_pair_missing'},
    [ordered]@{id='share_scaffolding_exposed';gate='share_completeness';task='share_card_body';facts=[ordered]@{required_question_count=2;paired_answer_count=2;transfer_case_complete=$true;input_conditions_present=$true;reasoning_present=$true;backend_scaffolding_exposed=$true};decision='targeted_repair';violation='backend_scaffolding_exposed'},
    [ordered]@{id='capacity_semantic_truncation';gate='capacity_preservation';task='content_creation';facts=[ordered]@{capacity_state='overflow';proposed_action='truncate_semantics';load_bearing_units_present=$true};decision='blocked';violation='semantic_truncation_attempted'},
    [ordered]@{id='capacity_scope_split';gate='capacity_preservation';task='content_creation';facts=[ordered]@{capacity_state='overflow';proposed_action='split_scope';load_bearing_units_present=$true};decision='pass'},
    [ordered]@{id='creation_judgment_missing';gate='creation_coherence';task='content_creation';facts=[ordered]@{primary_judgment_present=$false;mainline_coherent=$true;unbound_branch_count=0;contributions_bound_to_mainline=$true};decision='return_upstream';violation='primary_judgment_missing';full_rewrite=$true},
    [ordered]@{id='creation_mainline_diffuse';gate='creation_coherence';task='content_creation';facts=[ordered]@{primary_judgment_present=$true;mainline_coherent=$false;unbound_branch_count=2;contributions_bound_to_mainline=$false};decision='return_upstream';violation='mainline_diffuse';full_rewrite=$true},
    [ordered]@{id='local_failure_not_full_rewrite';gate='revision_scope';task='content_review';facts=[ordered]@{earliest_failure_layer='paragraph';kernel_failed=$false;reasoning_spine_failed=$false;proposed_full_rewrite=$true;failed_draft_used_as_source=$false;passed_sections=@('opening','ending')};decision='targeted_repair';violation='full_rewrite_without_upstream_failure';full_rewrite=$false},
    [ordered]@{id='failed_draft_not_truth';gate='revision_scope';task='content_review';facts=[ordered]@{earliest_failure_layer='source';kernel_failed=$false;reasoning_spine_failed=$false;proposed_full_rewrite=$false;failed_draft_used_as_source=$true;passed_sections=@()};decision='blocked';violation='failed_draft_as_truth_source'},
    [ordered]@{id='kernel_failure_allows_rewrite';gate='revision_scope';task='content_review';facts=[ordered]@{earliest_failure_layer='kernel';kernel_failed=$true;reasoning_spine_failed=$false;proposed_full_rewrite=$true;failed_draft_used_as_source=$false;passed_sections=@()};decision='pass';full_rewrite=$true},
    [ordered]@{id='fabricated_humanity';gate='authorship_quality';task='content_creation';facts=[ordered]@{independent_signal_clusters=0;reader_loss_present=$false;fake_experience_or_noise=$true};decision='targeted_repair';violation='fabricated_humanity_signal'},
    [ordered]@{id='multi_signal_reader_loss';gate='authorship_quality';task='content_creation';facts=[ordered]@{independent_signal_clusters=2;reader_loss_present=$true;fake_experience_or_noise=$false};decision='targeted_repair';violation='multi_signal_authorship_loss'},
    [ordered]@{id='discussion_source_unbound';gate='discussion_delta_integrity';task='content_creation';facts=[ordered]@{canonical_source_bound=$false;canonical_load_bearing_unit_count=3;preserved_load_bearing_unit_count=3;confirmed_adjustment_ids=@();applied_adjustment_ids=@();candidate_option_ids=@();rejected_option_ids=@();clarification_only_ids=@();explicit_deletion_authorized=$false};decision='blocked';violation='canonical_source_not_bound'},
    [ordered]@{id='discussion_unconfirmed_applied';gate='discussion_delta_integrity';task='content_creation';facts=[ordered]@{canonical_source_bound=$true;canonical_load_bearing_unit_count=3;preserved_load_bearing_unit_count=3;confirmed_adjustment_ids=@('A1');applied_adjustment_ids=@('A1','C1');candidate_option_ids=@('C1');rejected_option_ids=@();clarification_only_ids=@();explicit_deletion_authorized=$false};decision='targeted_repair';violation='unconfirmed_discussion_applied'},
    [ordered]@{id='discussion_load_bearing_drop';gate='discussion_delta_integrity';task='share_card_body';facts=[ordered]@{canonical_source_bound=$true;canonical_load_bearing_unit_count=3;preserved_load_bearing_unit_count=2;confirmed_adjustment_ids=@();applied_adjustment_ids=@();candidate_option_ids=@();rejected_option_ids=@();clarification_only_ids=@();explicit_deletion_authorized=$false};decision='targeted_repair';violation='canonical_content_dropped'},
    [ordered]@{id='search_overclaim';gate='search_claim_calibration';task='public_information_research';facts=[ordered]@{direct_source_support=$false;multi_fact_inference=$true;current_best_basis_present=$true;proposed_claim_class='confirmed'};decision='targeted_repair';violation='unsupported_confirmed_claim';claim='inference'},
    [ordered]@{id='search_direct_confirmed';gate='search_claim_calibration';task='public_information_research';facts=[ordered]@{direct_source_support=$true;multi_fact_inference=$false;current_best_basis_present=$true;proposed_claim_class='confirmed'};decision='pass';claim='confirmed'},
    [ordered]@{id='rights_overbroad_block';gate='rights_scope';task='share_card_body';facts=[ordered]@{rights_status='mixed';restricted_element_count=1;original_transformation_possible=$true;proposed_whole_work_block=$true};decision='targeted_repair';violation='overbroad_rights_block'},
    [ordered]@{id='review_maladaptive';gate='review_adaptation';task='fixed_learning_transfer_round';facts=[ordered]@{dominant_signal='transfer_failure';proposed_action='extend_interval'};decision='targeted_repair';violation='maladaptive_review_action';action='new_transfer_scenario'},
    [ordered]@{id='review_adaptive';gate='review_adaptation';task='fixed_learning_transfer_round';facts=[ordered]@{dominant_signal='stable_mastery';proposed_action='extend_interval'};decision='pass';action='extend_interval'},
    [ordered]@{id='creation_without_authority';gate='track_authority';task='share_card_body';facts=[ordered]@{source_track='LearningTrack';proposed_target_track='CreationTrack';explicit_creation_authority=$false;trigger='learning_complete'};decision='blocked';violation='creation_without_authority'},
    [ordered]@{id='observation_incomplete';gate='share_completeness';task='share_card_body';facts=[ordered]@{required_question_count=2};decision='blocked';violation='missing_observations'}
)

foreach ($case in $cases) {
    $observation = [ordered]@{
        schema = 'contentos-quality-observation-v1'
        observation_id = [string]$case.id
        gate = [string]$case.gate
        task_kind = [string]$case.task
        facts = $case.facts
    } | ConvertTo-Json -Compress -Depth 10
    try {
        $decision = & $gateTool -Root $Root -ObservationJson $observation |
            ConvertFrom-Json
    }
    catch {
        $failures.Add("scenario_threw:$($case.id)")
        continue
    }
    if ([string]$decision.schema -ne 'contentos-quality-decision-v1' -or
        [string]$decision.decision -ne [string]$case.decision -or
        [string]$decision.side_effects -ne 'none' -or
        [string]$decision.observation_authority -ne
            'caller_supplied_not_independently_verified') {
        $failures.Add("scenario_decision_mismatch:$($case.id):$($decision.decision)")
    }
    if ($null -ne $case.violation -and [string]$case.violation -notin @($decision.violations)) {
        $failures.Add("scenario_violation_missing:$($case.id):$($case.violation)")
    }
    if ($null -ne $case.reuse -and [string]$decision.result.reuse_decision -ne [string]$case.reuse) {
        $failures.Add("scenario_reuse_mismatch:$($case.id)")
    }
    if ($null -ne $case.claim -and [string]$decision.result.claim_class -ne [string]$case.claim) {
        $failures.Add("scenario_claim_mismatch:$($case.id)")
    }
    if ($null -ne $case.action -and [string]$decision.result.recommended_action -ne [string]$case.action) {
        $failures.Add("scenario_action_mismatch:$($case.id)")
    }
    if ($null -ne $case.transfer_evidence -and [string]$decision.result.transfer_evidence_class -ne [string]$case.transfer_evidence) {
        $failures.Add("scenario_transfer_evidence_mismatch:$($case.id)")
    }
    if ($null -ne $case.full_rewrite -and
        [bool]$decision.full_rewrite_allowed -ne [bool]$case.full_rewrite) {
        $failures.Add("scenario_rewrite_scope_mismatch:$($case.id)")
    }
}

$extraRootRejected = $false
try {
    $null = & $gateTool -Root $Root -ObservationJson (@{
        schema = 'contentos-quality-observation-v1'
        observation_id = 'unexpected-root-field'
        gate = 'teaching_before_test'
        task_kind = 'fixed_learning_first_round'
        facts = @{ teaching_visible = $true; test_requested = $true }
        claimed_verified = $true
    } | ConvertTo-Json -Compress -Depth 5)
}
catch { $extraRootRejected = $true }
if (-not $extraRootRejected) {
    $failures.Add('quality_observation_additional_property_not_blocked')
}

if ($cases.Count -ne 32) {
    $failures.Add("scenario_count_mismatch:$($cases.Count)")
}
if ($failures.Count -gt 0) {
    $failures | ForEach-Object { "FAIL: $_" }
    "SUMMARY: problem regression validation failed ($($failures.Count))"
    exit 1
}
"SUMMARY: problem regression validation passed (32 behavior scenarios)"
