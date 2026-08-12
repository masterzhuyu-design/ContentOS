[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ObservationJson,

    [string]$Root,

    [switch]$Pretty
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Split-Path -Parent $PSScriptRoot
}

function Write-QualityDecision {
    param([System.Collections.IDictionary]$Decision)

    if ($Pretty) {
        $Decision | ConvertTo-Json -Depth 12
    }
    else {
        $Decision | ConvertTo-Json -Compress -Depth 12
    }
}

try {
    $request = $ObservationJson | ConvertFrom-Json
}
catch {
    throw "Invalid quality observation JSON: $($_.Exception.Message)"
}

if (
    [string]$request.schema -ne
        'contentos-quality-observation-v1'
) {
    throw "Unsupported quality observation schema: $($request.schema)"
}
foreach ($field in @('observation_id', 'gate', 'task_kind')) {
    if ([string]::IsNullOrWhiteSpace([string]$request.$field)) {
        throw "Quality observation field is required: $field"
    }
}
if ($null -eq $request.facts) {
    throw 'Quality observation facts are required'
}

$decision = [ordered]@{
    schema = 'contentos-quality-decision-v1'
    status = 'valid'
    observation_id = [string]$request.observation_id
    gate = [string]$request.gate
    task_kind = [string]$request.task_kind
    decision = 'pass'
    earliest_failure_layer = 'none'
    violations = @()
    frozen_surfaces = @()
    next_actions = @()
    full_rewrite_allowed = $false
    side_effects = 'none'
}

$requiredFactsByGate = @{
    teaching_before_test = @(
        'teaching_visible'
        'test_requested'
    )
    transfer_integrity = @(
        'required_inputs_present'
        'answer_route_leaked'
        'mechanism_match'
        'boundary_differences_identified'
    )
    asset_reuse = @(
        'mechanism_match'
        'net_gain'
        'conflict_detected'
        'body_required_for_decision'
    )
    share_completeness = @(
        'required_question_count'
        'paired_answer_count'
        'transfer_case_complete'
        'input_conditions_present'
        'reasoning_present'
        'backend_scaffolding_exposed'
    )
    capacity_preservation = @(
        'capacity_state'
        'proposed_action'
        'load_bearing_units_present'
    )
    creation_coherence = @(
        'primary_judgment_present'
        'mainline_coherent'
        'unbound_branch_count'
        'contributions_bound_to_mainline'
    )
    revision_scope = @(
        'earliest_failure_layer'
        'kernel_failed'
        'reasoning_spine_failed'
        'proposed_full_rewrite'
        'failed_draft_used_as_source'
        'passed_sections'
    )
    authorship_quality = @(
        'independent_signal_clusters'
        'reader_loss_present'
        'fake_experience_or_noise'
    )
    discussion_delta_integrity = @(
        'canonical_source_bound'
        'canonical_load_bearing_unit_count'
        'preserved_load_bearing_unit_count'
        'confirmed_adjustment_ids'
        'applied_adjustment_ids'
        'candidate_option_ids'
        'rejected_option_ids'
        'clarification_only_ids'
        'explicit_deletion_authorized'
    )
    search_claim_calibration = @(
        'direct_source_support'
        'multi_fact_inference'
        'current_best_basis_present'
        'proposed_claim_class'
    )
    rights_scope = @(
        'rights_status'
        'restricted_element_count'
        'original_transformation_possible'
        'proposed_whole_work_block'
    )
    review_adaptation = @(
        'dominant_signal'
        'proposed_action'
    )
    track_authority = @(
        'source_track'
        'proposed_target_track'
        'explicit_creation_authority'
        'trigger'
    )
}

$requestedGate = [string]$request.gate
if ($requiredFactsByGate.ContainsKey($requestedGate)) {
    $factNames = @($request.facts.PSObject.Properties.Name)
    $missingFacts = @(
        @($requiredFactsByGate[$requestedGate]) |
            Where-Object { $_ -notin $factNames }
    )
    if ($missingFacts.Count -gt 0) {
        $decision.decision = 'blocked'
        $decision.earliest_failure_layer = 'observation_closure'
        $decision.violations = @('missing_observations')
        $decision.next_actions = @('complete_quality_observation')
        $decision['result'] = [ordered]@{
            missing_fields = $missingFacts
        }
        Write-QualityDecision -Decision $decision
        return
    }
}

switch ([string]$request.gate) {
    'teaching_before_test' {
        $testRequested = $request.facts.test_requested -eq $true
        $teachingVisible = $request.facts.teaching_visible -eq $true
        if ($testRequested -and -not $teachingVisible) {
            $decision.decision = 'return_upstream'
            $decision.earliest_failure_layer = 'teaching'
            $decision.violations = @('teaching_missing_before_test')
            $decision.next_actions = @('deliver_teaching')
        }
    }
    'transfer_integrity' {
        if ($request.facts.required_inputs_present -ne $true) {
            $decision.decision = 'return_upstream'
            $decision.earliest_failure_layer = 'input_closure'
            $decision.violations = @('transfer_inputs_missing')
            $decision.next_actions = @('bind_transfer_inputs')
        }
        elseif ($request.facts.answer_route_leaked -eq $true) {
            $decision.decision = 'targeted_repair'
            $decision.earliest_failure_layer = 'question_design'
            $decision.violations = @('answer_route_leaked')
            $decision.next_actions = @('redesign_transfer_prompt')
        }
    }
    'asset_reuse' {
        if ($request.facts.mechanism_match -ne $true) {
            $decision['result'] = [ordered]@{
                reuse_decision = 'no_use'
                body_load_allowed = $false
            }
            $decision.next_actions = @('continue_without_asset')
        }
        elseif ($request.facts.conflict_detected -eq $true) {
            $decision['result'] = [ordered]@{
                reuse_decision = 'backstage'
                body_load_allowed = $false
            }
            $decision.next_actions = @('use_for_calibration_only')
        }
        elseif (
            $request.facts.net_gain -eq $true -and
            $request.facts.conflict_detected -ne $true
        ) {
            $decision['result'] = [ordered]@{
                reuse_decision = 'use'
                body_load_allowed =
                    ($request.facts.body_required_for_decision -eq $true)
            }
            $decision.next_actions = if (
                $request.facts.body_required_for_decision -eq $true
            ) {
                @('load_selected_asset_body')
            }
            else {
                @('use_asset_summary')
            }
        }
        else {
            $decision['result'] = [ordered]@{
                reuse_decision = 'no_use'
                body_load_allowed = $false
            }
            $decision.next_actions = @('continue_without_asset')
        }
    }
    'share_completeness' {
        $shareViolations = [Collections.Generic.List[string]]::new()
        if (
            [int]$request.facts.paired_answer_count -lt
                [int]$request.facts.required_question_count
        ) {
            $shareViolations.Add('question_answer_pair_missing')
        }
        if ($request.facts.transfer_case_complete -ne $true) {
            $shareViolations.Add('transfer_case_incomplete')
        }
        if ($request.facts.input_conditions_present -ne $true) {
            $shareViolations.Add('question_input_missing')
        }
        if ($request.facts.reasoning_present -ne $true) {
            $shareViolations.Add('answer_reasoning_missing')
        }
        if ($request.facts.backend_scaffolding_exposed -eq $true) {
            $shareViolations.Add('backend_scaffolding_exposed')
        }
        if ($shareViolations.Count -gt 0) {
            $decision.decision = 'targeted_repair'
            $decision.earliest_failure_layer = 'share_body'
            $decision.violations = @($shareViolations)
            $decision.next_actions = @('repair_missing_share_units')
        }
    }
    'capacity_preservation' {
        if (
            [string]$request.facts.capacity_state -eq 'overflow' -and
            [string]$request.facts.proposed_action -eq
                'truncate_semantics'
        ) {
            $decision.decision = 'blocked'
            $decision.earliest_failure_layer = 'capacity_decision'
            $decision.violations = @('semantic_truncation_attempted')
            $decision.next_actions = @(
                'split_scope'
                'request_user_choice'
            )
        }
    }
    'creation_coherence' {
        $creationViolations =
            [Collections.Generic.List[string]]::new()
        if ($request.facts.primary_judgment_present -ne $true) {
            $creationViolations.Add('primary_judgment_missing')
        }
        if (
            $request.facts.mainline_coherent -ne $true -or
            [int]$request.facts.unbound_branch_count -gt 0 -or
            $request.facts.contributions_bound_to_mainline -ne $true
        ) {
            $creationViolations.Add('mainline_diffuse')
        }
        if ($creationViolations.Count -gt 0) {
            $decision.decision = 'return_upstream'
            $decision.earliest_failure_layer = if (
                'primary_judgment_missing' -in
                    @($creationViolations)
            ) {
                'content_kernel'
            }
            else {
                'reasoning_spine'
            }
            $decision.violations = @($creationViolations)
            $decision.next_actions = if (
                $decision.earliest_failure_layer -eq 'content_kernel'
            ) {
                @('revise_content_kernel')
            }
            else {
                @('revise_reasoning_spine')
            }
            $decision.full_rewrite_allowed = $true
        }
    }
    'revision_scope' {
        $decision.frozen_surfaces = @(
            $request.facts.passed_sections
        )
        $upstreamFailed = (
            $request.facts.kernel_failed -eq $true -or
            $request.facts.reasoning_spine_failed -eq $true
        )
        $decision.full_rewrite_allowed = $upstreamFailed
        if ($request.facts.failed_draft_used_as_source -eq $true) {
            $decision.decision = 'blocked'
            $decision.earliest_failure_layer = 'source_selection'
            $decision.violations = @(
                'failed_draft_as_truth_source'
            )
            $decision.next_actions = @(
                'rebind_canonical_source'
            )
        }
        elseif (
            $request.facts.proposed_full_rewrite -eq $true -and
            -not $upstreamFailed
        ) {
            $decision.decision = 'targeted_repair'
            $decision.earliest_failure_layer =
                [string]$request.facts.earliest_failure_layer
            $decision.violations = @(
                'full_rewrite_without_upstream_failure'
            )
            $decision.next_actions = @(
                'repair_failed_section_only'
            )
        }
    }
    'authorship_quality' {
        if ($request.facts.fake_experience_or_noise -eq $true) {
            $decision.decision = 'targeted_repair'
            $decision.earliest_failure_layer = 'authorship'
            $decision.violations = @(
                'fabricated_humanity_signal'
            )
            $decision.next_actions = @(
                'remove_fabricated_humanity'
            )
        }
        elseif (
            [int]$request.facts.independent_signal_clusters -ge 2 -and
            $request.facts.reader_loss_present -eq $true
        ) {
            $decision.decision = 'targeted_repair'
            $decision.earliest_failure_layer = 'authorship'
            $decision.violations = @(
                'multi_signal_authorship_loss'
            )
            $decision.next_actions = @(
                'repair_strongest_authorship_losses'
            )
        }
    }
    'discussion_delta_integrity' {
        if ($request.facts.canonical_source_bound -ne $true) {
            $decision.decision = 'blocked'
            $decision.earliest_failure_layer = 'source_binding'
            $decision.violations = @(
                'canonical_source_not_bound'
            )
            $decision.next_actions = @(
                'rebind_canonical_source'
            )
        }
        else {
            $confirmedAdjustments = @(
                $request.facts.confirmed_adjustment_ids |
                    ForEach-Object { [string]$_ }
            )
            $appliedAdjustments = @(
                $request.facts.applied_adjustment_ids |
                    ForEach-Object { [string]$_ }
            )
            $unconfirmedApplied = @(
                $appliedAdjustments |
                    Where-Object { $_ -notin $confirmedAdjustments }
            )
            $discussionViolations =
                [Collections.Generic.List[string]]::new()
            if ($unconfirmedApplied.Count -gt 0) {
                $discussionViolations.Add(
                    'unconfirmed_discussion_applied'
                )
            }
            $canonicalContentDropped = (
                [int]$request.facts.preserved_load_bearing_unit_count -lt
                    [int]$request.facts.canonical_load_bearing_unit_count -and
                $request.facts.explicit_deletion_authorized -ne $true
            )
            if ($canonicalContentDropped) {
                $discussionViolations.Add(
                    'canonical_content_dropped'
                )
            }
            if ($discussionViolations.Count -gt 0) {
                $decision.decision = 'targeted_repair'
                $decision.earliest_failure_layer =
                    'source_projection'
                $decision.violations = @($discussionViolations)
                $discussionActions =
                    [Collections.Generic.List[string]]::new()
                $discussionActions.Add('rebind_canonical_source')
                $discussionActions.Add(
                    'apply_confirmed_deltas_only'
                )
                if ($canonicalContentDropped) {
                    $discussionActions.Add(
                        'restore_load_bearing_units'
                    )
                }
                $decision.next_actions = @($discussionActions)
            }
        }
    }
    'search_claim_calibration' {
        $claimClass = if (
            $request.facts.direct_source_support -eq $true
        ) {
            'confirmed'
        }
        elseif ($request.facts.multi_fact_inference -eq $true) {
            'inference'
        }
        elseif (
            $request.facts.current_best_basis_present -eq $true
        ) {
            'best_current_judgment'
        }
        else {
            'unknown'
        }
        $decision['result'] = [ordered]@{
            claim_class = $claimClass
        }
        if (
            [string]$request.facts.proposed_claim_class -ne
                $claimClass
        ) {
            $decision.decision = 'targeted_repair'
            $decision.earliest_failure_layer =
                'claim_calibration'
            $decision.violations = if (
                [string]$request.facts.proposed_claim_class -eq
                    'confirmed' -and
                $claimClass -ne 'confirmed'
            ) {
                @('unsupported_confirmed_claim')
            }
            else {
                @('claim_class_mismatch')
            }
            $decision.next_actions = @('relabel_claim')
        }
    }
    'rights_scope' {
        if (
            $request.facts.proposed_whole_work_block -eq $true -and
            $request.facts.original_transformation_possible -eq
                $true
        ) {
            $decision.decision = 'targeted_repair'
            $decision.earliest_failure_layer = 'rights_scope'
            $decision.violations = @('overbroad_rights_block')
            $decision.next_actions = @(
                'isolate_restricted_elements'
                'continue_original_transformation'
            )
        }
    }
    'review_adaptation' {
        $reviewActions = @{
            retrieval_failure = 'shorter_unguided_recall'
            mechanism_confusion = 'relation_discrimination'
            transfer_failure = 'new_transfer_scenario'
            high_importance = 'earlier_review'
            stable_mastery = 'extend_interval'
            evidence_update = 'immediate_update_review'
        }
        $signal = [string]$request.facts.dominant_signal
        if (-not $reviewActions.ContainsKey($signal)) {
            throw "Unsupported review signal: $signal"
        }
        $recommendedAction = [string]$reviewActions[$signal]
        $decision['result'] = [ordered]@{
            recommended_action = $recommendedAction
        }
        if (
            [string]$request.facts.proposed_action -ne
                $recommendedAction
        ) {
            $decision.decision = 'targeted_repair'
            $decision.earliest_failure_layer = 'review_plan'
            $decision.violations = @(
                'maladaptive_review_action'
            )
            $decision.next_actions = @(
                "schedule_$recommendedAction"
            )
        }
    }
    'track_authority' {
        if (
            [string]$request.facts.proposed_target_track -eq
                'CreationTrack' -and
            $request.facts.explicit_creation_authority -ne $true
        ) {
            $decision.decision = 'blocked'
            $decision.earliest_failure_layer = 'track_authority'
            $decision.violations = @(
                'creation_without_authority'
            )
            $decision.next_actions = @(
                'remain_learning_track'
            )
        }
    }
    default {
        throw "Unsupported quality gate: $($request.gate)"
    }
}

Write-QualityDecision -Decision $decision
