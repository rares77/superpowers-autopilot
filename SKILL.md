---
name: superpowers-autopilot
description: Use when the user wants to implement all features from a PRD.md automatically with zero manual intervention — "run autopilot on my PRD", "implement everything from PRD", "autopilot mode", "PRD to production", or wants Claude to work through a feature list unattended. Orchestrates superpowers:writing-plans and superpowers:subagent-driven-development in a loop per feature, consulting an external CLI when stuck. Use this skill even if the user just drops a PRD.md path and says "go".
---

# Superpowers Autopilot

## Overview

Autonomous outer loop that implements every feature in a PRD.md with zero human intervention. You read the PRD, queue features, plan and execute each one using Superpowers skills, consult an external CLI when stuck, and exit with a summary report.

**Invocation:** `/superpowers-autopilot <path/to/PRD.md>`

## Autopilot Rules

1. **Each feature is dispatched as a subagent** — the main session manages the loop, state, and commits. A fresh subagent handles planning + execution for each feature. This automatically skips brainstorming (Superpowers' `<SUBAGENT-STOP>` mechanism).
2. **Subagents NEVER ask the user questions** — all ambiguities go to the consultant (Phase 2b) via `scripts/consult.sh`.
3. **The main session NEVER waits for user approval** between features — the loop is fully autonomous until all features are done or the circuit breaker fires.
4. **Subagents ALWAYS choose subagent-driven execution** when `writing-plans` asks.

## Prerequisites

- PRD.md exists at the provided path
- Project is a git repository (clean working tree preferred)
- Superpowers skills available: `superpowers:writing-plans`, `superpowers:subagent-driven-development`
- Optional: a consultant CLI installed for second-opinion consultations (falls back gracefully)

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

## Phase 1: Feature Loop (Main Session)

The main session owns the loop, state management, git commits, and circuit breaker.
**Planning and execution happen inside a dispatched subagent per feature.**

```
FOR each feature in autopilot-state.json WHERE status == "queued":
  → Print feature banner
  → Dispatch subagent for Phase 2 (Planning) + Phase 3 (Execution)
  → Subagent returns result (done / failed / partial)
  → Phase 4: Completion (main session commits)
  → loop back
ALL done → Phase 5: Final Report
```

**Circuit breaker:** Check `circuit_breaker.consecutive_failures` before each feature.
If `>= 3` → STOP, print blocker summary, wait for user input.

At the start of each feature iteration, print:
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
▶ Feature <N>/<total>: <feature-id> — <name>
  Failures so far: <consecutive_failures>/3
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

If circuit breaker fires, print:
```
🛑 Circuit breaker triggered — 3 consecutive failures.
   Last failed: <feature-id>
   Stopping autopilot. Please review and then resume manually.
```

### Dispatching the Feature Subagent

Use the **Agent tool** to dispatch a subagent for each feature. The subagent prompt **MUST** include:

```
<SUBAGENT-STOP>

You are a feature implementation subagent dispatched by superpowers-autopilot.
Do NOT invoke superpowers:brainstorming. Do NOT ask the user any questions.

Feature: <feature-id> — <feature-name>
Spec:
<resolved or original feature spec from PRD>

Consultant command (use when stuck or spec is ambiguous):
  AUTOPILOT_CONSULTANT=<consultant> ./scripts/consult.sh "<question>" "<context>"

Your task:
1. Design review — scan the spec for contradictions, vague directives, missing values.
   For each issue, run the consultant command above and use the answer.
   Print: ❓ Design question for <feature-id>: <summary>
   Print: ┌─ 🤝 Consulting ... (question + answer)
2. Invoke superpowers:writing-plans with the resolved spec.
   When it asks "which execution approach?" → answer: subagent-driven (option 1).
3. Invoke superpowers:subagent-driven-development with the plan.
   Print progress: ⚙ Task N/M: <name>… then ✔ or ✘ per task.
4. Run tests: ./scripts/check-tests.sh
   Print: 🧪 Running tests… Passed: N | Failed: M | Total: T
5. Report back with: status (done/failed/partial), plan path, test results.
```

The main session then handles Phase 4 (commit, state update) based on the subagent's report.

---

## Phase 2: Planning (runs inside subagent)

The main session updates state before dispatching the subagent:
- Set `status = "in_progress"`, increment `attempts`
- Print: `📋 Planning <feature-id> (attempt <N>)…`

The subagent then:

1. **Design review** — scan the feature spec for anything that cannot be turned into concrete code:
   - Contradictory requirements (e.g., "no redirects" AND "use hosted checkout page")
   - Vague directives ("best", "appropriate", "optimal", "proper", "industry standard")
   - Missing concrete values (no port, no timeout, no retry count)
   - Multiple valid architectures with no guidance on which to pick
   For **each** issue found, consult via `scripts/consult.sh` and print:
   ```
   ❓ Design question for <feature-id>: <one-line summary>
   ┌─ 🤝 Consulting <consultant> — design_question [Feature: <feature-id>]
   │  Q: <question>
   │  A: <answer>
   └─ ✔ Applying answer
   ```
   After all resolved, print:
   ```
   ✔ Design review complete — <N> question(s) resolved via consultant
   ```
2. **Invoke `superpowers:writing-plans`** with the resolved spec
   - When it asks "Which execution approach?" → answer: subagent-driven (option 1)
3. **Validate** the generated plan:
   - At least one test per implementation task?
   - No placeholder text ("TBD", "similar to task N")?
   - If validation fails → consult via `scripts/consult.sh`, retry once

---

## Phase 2b: Consultant Conversation

Trigger when:
- Plan validation fails
- Subagent fails the same task 2× in a row
- Test suite regresses after implementation
- Requirement in PRD is ambiguous

**Before calling the consultant**, print the conversation header:
```
┌─ 🤝 Consulting <consultant> — <trigger reason> [Feature: <feature-id>]
│  Q: <the exact question being sent>
│  Context: <one-line summary of context snippet>
```

How to consult:
```bash
AUTOPILOT_CONSULTANT=$(./scripts/state-manager.sh get consultant) \
  ./scripts/consult.sh "<formatted question>" "<context snippet>"
```

See `references/consultant-patterns.md` for question templates per situation.

**After receiving the answer**, print the response and outcome:
```
│  A: <consultant answer, full text>
└─ ✔ Applying answer — retrying <plan/task/revert>
```

If the consultant is unavailable, print:
```
┌─ 🤝 Consulting <consultant> — unavailable, self-reasoning [Feature: <feature-id>]
│  Q: <question>
│  A: <Claude's own reasoning>
└─ ✔ Applying self-reasoning — retrying <plan/task/revert>
```

After consulting:
- Log result to `codex_consultations[]` in state with timestamp
- Apply the answer and retry the failed step
- If consultant is unavailable, reason through it independently and log as `"self-consultation"`

---

## Phase 3: Execution (runs inside subagent)

The subagent continues after planning:

1. Print:
   ```
   🔨 Executing <feature-id> — invoking subagent-driven-development…
   ```
2. **Invoke `superpowers:subagent-driven-development`** with the validated plan
3. For each task, print progress:
   ```
     ⚙ Task <task-index>/<task-total>: <task-name>… [running]
     ✔ Task <task-index>/<task-total>: <task-name> — done
   ```
   Or on failure:
   ```
     ✘ Task <task-index>/<task-total>: <task-name> — failed (attempt <N>)
     Error: <brief error summary>
   ```
   If a task fails twice → consult via `scripts/consult.sh`, retry once.
   If still failing → skip task, mark feature as `"partial"`.
4. After all tasks → run `scripts/check-tests.sh` and print:
   ```
   🧪 Running tests…
     Passed: <N> | Failed: <M> | Total: <T>
   ```
5. **Report back to main session** with:
   - `status`: `done` | `failed` | `partial`
   - `plan_path`: where the plan was saved
   - `test_results`: pass/fail counts
   - `error_summary`: if failed, what went wrong

---

## Phase 4: Feature Completion (Main Session)

After the subagent returns, the main session handles the result:

**If subagent reports `done`:**
1. Stage and commit:
   ```bash
   git add -A
   git commit -m "feat(<feature-id>): implement <feature-name> per PRD spec"
   ```
2. Capture `commit_sha` in state
3. Update state: `status = "done"`, `consecutive_failures = 0`
4. Print:
   ```
   ✅ Feature <N>/<total>: <name> — done
   ```

**If subagent reports `failed`:**
1. Revert uncommitted changes: `git checkout -- .`
2. Update state: `status = "failed"`, increment `consecutive_failures`
3. Print:
   ```
   ❌ Feature <feature-id> failed — <error_summary>
      Consecutive failures: <N>/3
   ```

**If subagent reports `partial`:**
1. Commit what was completed
2. Update state: `status = "partial"`, reset `consecutive_failures`
3. Print:
   ```
   ⚠ Feature <feature-id> partially complete — some tasks skipped
   ```

→ Back to Phase 1

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
| `scripts/consult.sh` | Wrapper for consultant CLIs with timeout |
| `scripts/check-tests.sh` | Run test suite, return pass/fail + diff |
| `references/prd-formats.md` | Supported PRD formats and parsing rules |
| `references/consultant-patterns.md` | When/how to consult per situation |
| `references/safety-rails.md` | Circuit breaker, rollback, cost guard logic |
| `templates/autopilot-state.template.json` | Initial state file structure |
| `templates/feature-context.template.md` | Per-feature context injection prompt |
