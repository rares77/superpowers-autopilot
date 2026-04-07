---
name: superpowers-autopilot
description: Use when the user wants to implement all features from a PRD.md automatically with zero manual intervention — "run autopilot on my PRD", "implement everything from PRD", "autopilot mode", "PRD to production", or wants Claude to work through a feature list unattended. Orchestrates superpowers:writing-plans and superpowers:subagent-driven-development in a loop per feature, consulting Codex CLI when stuck. Use this skill even if the user just drops a PRD.md path and says "go".
---

# Superpowers Autopilot

## Overview

Autonomous outer loop that implements every feature in a PRD.md with zero human intervention. You read the PRD, queue features, plan and execute each one using Superpowers skills, consult Codex when stuck, and exit with a summary report.

**Invocation:** `/superpowers-autopilot <path/to/PRD.md>`

## Prerequisites

- PRD.md exists at the provided path
- Project is a git repository (clean working tree preferred)
- Superpowers skills available: `superpowers:writing-plans`, `superpowers:subagent-driven-development`
- Optional: `codex` CLI installed for second-opinion consultations (falls back gracefully)

---

## Phase 0: Initialize

1. Parse the PRD → run `scripts/parse-prd.sh <PRD_PATH>` to extract feature list as JSON
2. **Detect available second-opinion CLIs** → run `scripts/detect-consultants.sh`
   - Shows which of `codex`, `gemini`, `claude` are installed
   - **Ask the user to choose** (or confirm the recommended default):
     ```
     🔍 Second-opinion consultant detection:
       ✅ claude (Opus) — always available ⭐ recommended
                          more capable model = genuine reasoning upgrade
       ✅ codex          — available (different model family)
       ❌ gemini         — not found

     Which should I consult when stuck? [claude / codex]
     Default: claude/Opus (press Enter to confirm)
     ```
   - `claude` (Opus) este întotdeauna recomandat — orchestratorul rulează pe Sonnet,
     Opus oferă un upgrade real de raționament, nu doar context izolat
   - Save the chosen consultant to state as `consultant`
3. Initialize `autopilot-state.json` using `templates/autopilot-state.template.json`
4. Create a dedicated git branch: `git checkout -b autopilot/$(date +%Y%m%d)`
5. Announce the queue to the user:
   ```
   🚀 Autopilot starting. Features queued:
     [ ] F1: <name>
     [ ] F2: <name>
     ...
   Consultant: codex | Working autonomously. I'll report when done.
   ```

---

## Phase 1: Feature Loop

```
FOR each feature in autopilot-state.json WHERE status == "queued":
  → Phase 2: Planning
  → Phase 3: Execution
  → Phase 4: Completion
  → loop back
ALL done → Phase 5: Final Report
```

**Circuit breaker:** Check `circuit_breaker.consecutive_failures` before each feature.
If `>= 3` → STOP, print blocker summary, wait for user input.

---

## Phase 2: Planning

1. Read the feature spec from state (name, acceptance_criteria, constraints)
2. Update state: `status = "in_progress"`, increment `attempts`
3. Build the planning prompt from `templates/feature-context.template.md`
4. **Invoke `superpowers:writing-plans`** with the feature context injected
5. Validate the generated plan:
   - At least one test per implementation task?
   - Referenced file paths exist or will be created?
   - No circular task dependencies?
6. If validation fails → **Phase 2b: Codex Consultation**, then retry planning once

---

## Phase 2b: Codex Consultation

Trigger when:
- Plan validation fails
- Subagent fails the same task 2× in a row
- Test suite regresses after implementation
- Requirement in PRD is ambiguous

How to consult:
```bash
AUTOPILOT_CONSULTANT=$(./scripts/state-manager.sh get consultant) \
  ./scripts/codex-consult.sh "<formatted question>" "<context snippet>"
```

See `references/codex-patterns.md` for question templates per situation.

After consulting:
- Log result to `codex_consultations[]` in state with timestamp
- Apply the answer and retry the failed step
- If Codex is unavailable (not installed), reason through it independently

---

## Phase 3: Execution

1. **Invoke `superpowers:subagent-driven-development`** with the validated plan
2. For each task subagent:
   - Track pass/fail
   - If a task fails twice → trigger Phase 2b (Codex), then retry once more
   - If still failing → skip task, mark feature as `"partial"`, continue
3. After all tasks complete → run `scripts/check-tests.sh`
   - **All pass** → proceed to Phase 4
   - **Regression detected** → git revert last commit, trigger Phase 2b, retry once
   - **Still failing** → mark feature `"failed"`, increment `consecutive_failures`, skip to next feature

---

## Phase 4: Feature Completion

1. Stage and commit:
   ```bash
   git add -A
   git commit -m "feat(<feature-id>): implement <feature-name> per PRD spec"
   ```
2. Capture `commit_sha` in state
3. Update state: `status = "done"`, `consecutive_failures = 0`
4. Print progress:
   ```
   ✅ Feature <N>/<total>: <name> — done
   ```
5. → Back to Phase 1

---

## Phase 5: Final Report

When all features are `"done"` or `"failed"`:

```
📊 Autopilot Complete
══════════════════════════════════
Features done:    N / total
Features failed:  F / total
Codex calls:      M
Branch:           autopilot/YYYYMMDD
══════════════════════════════════
Failed features:
  ❌ F2: <name> — <brief reason>

Next steps:
  git log --oneline autopilot/YYYYMMDD
  gh pr create --base main
```

If all features passed → offer to open a PR automatically.

---

## State Management

All state lives in `autopilot-state.json` at the project root.
Use `scripts/state-manager.sh` to read/write safely:

```bash
# Read
./scripts/state-manager.sh get current_feature
./scripts/state-manager.sh get features

# Write
./scripts/state-manager.sh set-feature-status F1 done
./scripts/state-manager.sh set-commit F1 abc123
./scripts/state-manager.sh increment consecutive_failures
./scripts/state-manager.sh reset-failures
./scripts/state-manager.sh append-codex F1 "question" "answer"
```

---

## Supporting Files

| File | Purpose |
|------|---------|
| `scripts/parse-prd.sh` | Extract features from PRD.md → JSON |
| `scripts/state-manager.sh` | Read/write autopilot-state.json |
| `scripts/codex-consult.sh` | Wrapper for `codex -p` with timeout |
| `scripts/check-tests.sh` | Run test suite, return pass/fail + diff |
| `references/prd-formats.md` | Supported PRD formats and parsing rules |
| `references/codex-patterns.md` | When/how to consult Codex per situation |
| `references/safety-rails.md` | Circuit breaker, rollback, cost guard logic |
| `templates/autopilot-state.template.json` | Initial state file structure |
| `templates/feature-context.template.md` | Per-feature context injection prompt |
