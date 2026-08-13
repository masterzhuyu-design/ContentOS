[CmdletBinding()]
param(
    [ValidateSet('resolve_proposal')]
    [string]$Action = 'resolve_proposal',

    [Parameter(Mandatory = $true)]
    [string]$ClaimedClientId,

    [Parameter(Mandatory = $true)]
    [string]$ExternalSessionId,

    [Parameter(Mandatory = $true)]
    [string]$CurrentHostTurnId,

    [Parameter(Mandatory = $true)]
    [string]$TaskKind,

    [Parameter(Mandatory = $true)]
    [string]$TaskExecutionInputJson,

    [string]$SharedTaskScopeId = '',

    [ValidateSet('full', 'lite')]
    [string]$Profile = 'full',

    [string]$Root,

    [switch]$Pretty
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Split-Path -Parent $PSScriptRoot
}

function Get-TextDigest {
    param([string]$Text)

    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha.ComputeHash(
            [Text.UTF8Encoding]::new($false).GetBytes($Text)
        )
    }
    finally { $sha.Dispose() }
    return 'sha256:' + (($hash | ForEach-Object { $_.ToString('x2') }) -join '')
}

if ($ClaimedClientId -notmatch '^[A-Za-z0-9][A-Za-z0-9._:-]{1,127}$') {
    throw 'ClaimedClientId must be an explicit stable client label.'
}
if ($ExternalSessionId -notmatch '^[A-Za-z0-9][A-Za-z0-9._:@-]{7,255}$') {
    throw 'ExternalSessionId must be a host-native opaque session identifier.'
}
if ($ExternalSessionId -eq 'known-sentinel-session') {
    throw 'A known sentinel ExternalSessionId is not allowed.'
}
if ($CurrentHostTurnId -notmatch '^[A-Za-z0-9][A-Za-z0-9._:@-]{0,255}$') {
    throw 'CurrentHostTurnId must be the exact current host turn identifier.'
}

try {
    $taskExecutionInput = $TaskExecutionInputJson | ConvertFrom-Json
}
catch {
    throw "TaskExecutionInputJson is invalid: $($_.Exception.Message)"
}
if ([string]$taskExecutionInput.schema -ne
    'contentos-task-execution-input-v1') {
    throw 'Unsupported TaskExecutionInputJson schema.'
}
if ([string]$taskExecutionInput.task_kind -ne $TaskKind) {
    throw 'TaskExecutionInputJson task_kind must match TaskKind.'
}
if ([string]$taskExecutionInput.current_turn_id -cne $CurrentHostTurnId) {
    throw 'CurrentHostTurnId must exactly match TaskExecutionInputJson current_turn_id.'
}
if (-not [string]::IsNullOrWhiteSpace($SharedTaskScopeId) -and
    [string]$taskExecutionInput.scope_id -cne $SharedTaskScopeId) {
    throw 'SharedTaskScopeId must exactly match TaskExecutionInputJson scope_id.'
}

$resolver = Join-Path $Root 'scripts\resolve-contentos-startup.ps1'
if (-not (Test-Path -LiteralPath $resolver -PathType Leaf)) {
    throw "ContentOS startup resolver missing: $resolver"
}
$raw = @(
    & $resolver -Root $Root -Profile $Profile -TaskKind $TaskKind `
        -TaskExecutionInputJson $TaskExecutionInputJson 2>&1 |
        ForEach-Object { $_.ToString() }
) -join "`n"
if ($LASTEXITCODE -notin @(0, $null)) {
    throw "ContentOS startup failed for external proposal: $raw"
}
try { $startup = $raw | ConvertFrom-Json }
catch { throw 'ContentOS startup did not return valid JSON.' }

$ready = (
    [string]$startup.status -eq 'ready' -and
    [string]$startup.task_execution.status -eq 'ready' -and
    [bool]$startup.generation_allowed
)
$inputDigest = Get-TextDigest -Text $TaskExecutionInputJson
$envelope = [ordered]@{
    schema = 'contentos-external-proposal-envelope-v1'
    status = if ($ready) { 'ready' } else { 'blocked' }
    mode = 'proposal_only'
    action = $Action
    claimed_client_id = $ClaimedClientId
    external_session_ref = $ExternalSessionId
    freshness_binding = [ordered]@{
        external_session_ref = $ExternalSessionId
        current_host_turn_ref = $CurrentHostTurnId
        scope_id = [string]$taskExecutionInput.scope_id
        current_turn_id = [string]$taskExecutionInput.current_turn_id
        task_kind = [string]$taskExecutionInput.task_kind
        task_stage = [string]$taskExecutionInput.task_stage
        task_execution_input_digest = $inputDigest
        reuse_scope = 'exact_binding_only'
        cross_stage_reuse_allowed = $false
    }
    shared_task_binding = [ordered]@{
        status = if ([string]::IsNullOrWhiteSpace($SharedTaskScopeId)) {
            'unbound'
        }
        else { 'bound_to_scope' }
        scope_id = $SharedTaskScopeId
        authority = 'correlation_only'
        target_task_state_verified = $false
    }
    proposal_generation_allowed = $ready
    proposal_view = if ($ready) { $startup.generator_view } else { $null }
    blocked_status = if ($ready) { $null } else { [string]$startup.status }
    input_closure = $startup.task_execution.input_closure
    external_access = [ordered]@{
        write_authority = $false
        adoption_authority = $false
        domain_action_allowed = $false
        persistence_allowed = $false
        output_transport = 'stdout_only'
        side_effects = 'none'
    }
    note = (
        'This envelope is a proposal only. A canonical owner must ' +
        'independently adopt, validate, and write.'
    )
}

if ($Pretty) {
    $envelope | ConvertTo-Json -Depth 30
}
else {
    $envelope | ConvertTo-Json -Compress -Depth 30
}
