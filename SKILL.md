---
name: superpowers-autopilot
description: Use when the user wants to implement all features from a PRD.md automatically with zero manual intervention — "run autopilot on my PRD", "implement everything from PRD", "autopilot mode", "PRD to production", or wants Claude to work through a feature list unattended. Orchestrates superpowers:writing-plans and superpowers:subagent-driven-development in a loop per feature, consulting an external CLI when stuck. Use this skill even if the user just drops a PRD.md path and says "go".
---

# Superpowers Autopilot

## Overview

Autonomous outer loop that implements every feature in a PRD.md with zero human intervention. You read the PRD, queue features, plan and execute each one using Superpowers skills, consult an external CLI when stuck, and exit with a summary report.

**Invocation:** `/superpowers-autopilot <path/to/PRD.md>`

## Autopilot Rules — Override All Other Skills

These rules take priority over every other Superpowers skill for the duration of this autopilot run:

1. **NEVER invoke `superpowers:brainstorming` as a skill** — invoking it transfers control and the user gets asked questions directly. Instead, autopilot performs its own design review in Phase 2 step 5 (see below) and routes all questions to the consultant.
2. **NEVER ask the user questions** — all ambiguities and clarifications go to the consultant (Phase 2b).
3. **NEVER wait for user approval** between features — the loop is fully autonomous until all features are done or the circuit breaker fires.
4. **ALWAYS choose subagent-driven execution** when `writing-plans` asks — never inline, never ask the user which one.

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

---

## Phase 2: Planning

1. Read the feature spec from state (name, acceptance_criteria, constraints)
2. Update state: `status = "in_progress"`, increment `attempts`
3. Build the planning prompt from `templates/feature-context.template.md`
4. Print:
   ```
   📋 Planning <feature-id> (attempt <N>)…
   ```
5. **Design review (replaces brainstorming)** — scan the feature spec for anything that cannot be turned into concrete code:
   - Contradictory requirements (e.g., "no redirects" AND "use hosted checkout page")
   - Vague directives ("best", "appropriate", "optimal", "proper", "industry standard")
   - Missing concrete values (no port, no timeout, no retry count)
   - Multiple valid architectures with no guidance on which to pick
   For **each** issue found:
   a. Print:
      ```
      ❓ Design question for <feature-id>: <one-line summary of the ambiguity>
      ```
   b. Send the question to the consultant via Phase 2b (prints the `┌─ 🤝 Consulting` block)
   c. Record the consultant's answer as a **design decision**
   After all questions are resolved, build a **resolved spec** that replaces the ambiguous parts with the consultant's concrete answers. Print:
   ```
   ✔ Design review complete — <N> question(s) resolved via consultant
   ```
   If no ambiguities are found, print:
   ```
   ✔ Design review — spec is clear, no questions needed
   ```
6. **Invoke `superpowers:writing-plans`** with the resolved feature spec (not the original PRD text)
7. Validate the generated plan:
   - At least one test per implementation task?
   - Referenced file paths exist or will be created?
   - No circular task dependencies?
   - No placeholder text ("TBD", "similar to task N", "add validation")?
8. If validation passes, print:
   ```
   ✔ Plan valid — <task-count> tasks, saved to <plan_path>
   ```
   When `writing-plans` asks "Which execution approach?" — **always answer: subagent-driven (option 1)**. Do not wait for user input. Autopilot owns this decision.
9. If validation fails, print:
   ```
   ✘ Plan validation failed: <reason>
     → Triggering consultant (Phase 2b)
   ```
   Then → **Phase 2b: Consultant Conversation**, then return to step 6 (planning) once

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

## Phase 3: Execution

1. Print:
   ```
   🔨 Executing <feature-id> — invoking subagent-driven-development…
   ```
2. **Invoke `superpowers:subagent-driven-development`** with the validated plan
3. For each task subagent, print on start and completion:
   ```
     ⚙ Task <task-index>/<task-total>: <task-name>… [running]
   ```
   Then either:
   ```
     ✔ Task <task-index>/<task-total>: <task-name> — done
   ```
   or:
   ```
     ✘ Task <task-index>/<task-total>: <task-name> — failed (attempt <N>)
     Error: <brief error summary>
     → Triggering consultant (Phase 2b)
   ```
4. If a task still fails after consultant retry, print:
   ```
   ⚠ Task <task-name> skipped after 2 failures — feature marked partial
   ```
5. After all tasks complete → run `scripts/check-tests.sh` and print:
   ```
   🧪 Running tests…
     Passed: <N> | Failed: <M> | Total: <T>
   ```
   Then:
   - **All pass** → proceed to Phase 4
   - **Regression detected**, print and act:
     ```
     ⚠ Regression detected — <failing-test-names>
       Reverting last commit and consulting…
     ```
     → git revert last commit, trigger Phase 2b, retry once
   - **Still failing** → print and update state:
     ```
     ❌ Feature <feature-id> failed — marking failed, moving to next
        Consecutive failures: <N>/3
     ```
     increment `consecutive_failures`, skip to next feature

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
| `scripts/consult.sh` | Wrapper for consultant CLIs with timeout |
| `scripts/check-tests.sh` | Run test suite, return pass/fail + diff |
| `references/prd-formats.md` | Supported PRD formats and parsing rules |
| `references/consultant-patterns.md` | When/how to consult per situation |
| `references/safety-rails.md` | Circuit breaker, rollback, cost guard logic |
| `templates/autopilot-state.template.json` | Initial state file structure |
| `templates/feature-context.template.md` | Per-feature context injection prompt |
