---
name: contentos-external-proposal
description: Build a proposal-only ContentOS task envelope from a complete current host turn without granting canonical write or adoption authority.
---

# ContentOS external proposal

Use this entry whenever an external AI client starts or resumes a knowledge, learning, reply, research, creation, scoring, transfer, recovery, or maintenance stage.

1. Read the installed `AGENTS.md` and select one existing TaskKind. Do not create a client-specific substitute task name.
2. Build one complete `contentos-task-execution-input-v1`. Every current-turn binding must point to the exact current host turn; every workspace binding must be relative to this ContentOS root and include the current file digest.
3. Pass the host-native session as `ExternalSessionId` and the exact current host turn as `CurrentHostTurnId`. The input `current_turn_id` must match it exactly. A session ID identifies the caller; it never selects a checkpoint or grants owner authority.
4. A folded UI is presentation, not absence. Expand or otherwise read the exact current-turn bytes before building a load-bearing input. After stop/resume or host-native retry, rebuild from those bytes or a previously bound canonical workspace artifact. If the host cannot expose them, fail closed; never score a summary, infer hidden answers, or skip a folded block.
5. Call `scripts/invoke-contentos-external-client-boundary.ps1` and accept only `proposal_only`. Never call a write interface from this skill and never reuse an earlier stage envelope, score, transfer result, current turn ID, or temporary input file.
6. Finish the user's current task. Asset or source discoveries may be returned as clearly non-authoritative candidates, but they do not change TaskKind, Registry state, lifecycle, adoption, publication, or the selected mainline.
7. Return a clean user-facing artifact when that is the requested output. Internal checks do not become a second visible report unless the task itself asks for analysis or review.
8. Any canonical write, adoption, publication, account action, experiment, or lifecycle change requires a separately authorized canonical owner.
