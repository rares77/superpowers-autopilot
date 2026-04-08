---
name: superpowers-autopilot
description: Use when the user wants to implement all features from a PRD.md automatically with zero manual intervention — "run autopilot on my PRD", "implement everything from PRD", "autopilot mode", "PRD to production", or wants Claude to work through a feature list unattended. Orchestrates superpowers:writing-plans and superpowers:subagent-driven-development in a loop per feature, consulting an external CLI when stuck. Use this skill even if the user just drops a PRD.md path and says "go".
---

# Superpowers Autopilot

## Runtime Context

**Autopilot state:**
!`cat .claude/autopilot-state.json 2>/dev/null || echo "not initialized — fresh run"`

**Current git branch:**
!`git branch --show-current 2>/dev/null || echo "unknown"`

**Guard status:**
!`[ -f .claude/autopilot-active ] && echo "ACTIVE — interactive skills blocked" || echo "INACTIVE — will activate in Phase 0"`

## Overview

Autonomous outer loop that implements every feature in a PRD.md with zero human intervention. You read the PRD, queue features, plan and execute each one using Superpowers skills, consult an external CLI when stuck, and exit with a summary report.

**Invocation:** `/superpowers-autopilot <path/to/PRD.md>`

## Autopilot Rules

1. **Interactive Superpowers skills are blocked by the guard hook** — `brainstorming`, `finishing-a-development-branch`, `executing-plans`, and `using-git-worktrees` are denied at the tool level while `.claude/autopilot-active` exists. You don't need to avoid them manually; the hook enforces it.
2. **NEVER ask the user questions** — all ambiguities and clarifications go to the consultant (Phase 2b).
3. **NEVER wait for user approval** between features — the loop is fully autonomous until all features are done or the circuit breaker fires.
4. **ALWAYS choose subagent-driven execution** when `writing-plans` asks — never inline, never ask the user which one.
5. **Design review replaces brainstorming** — scan every feature spec for ambiguities before planning, resolve them via the consultant, then invoke `writing-plans` with the resolved spec.

## Prerequisites

- PRD.md exists at the provided path
- Project is a git repository (clean working tree preferred)
- Superpowers skills available: `superpowers:writing-plans`, `superpowers:subagent-driven-development`
- Optional: a consultant CLI installed for second-opinion consultations (falls back gracefully)

---

## Resume Check

**Run this before anything else, every invocation:**

```bash
# Migrate state file from old location if needed (pre-.claude/ runs)
if [[ -f "autopilot-state.json" && ! -f ".claude/autopilot-state.json" ]]; then
  mkdir -p .claude && mv autopilot-state.json .claude/autopilot-state.json
  echo "📦 Migrated autopilot-state.json → .claude/autopilot-state.json"
fi

./scripts/state-manager.sh pending-count 2>/dev/null || echo "0"
```

| Result | Action |
|--------|--------|
| `0` or error | No prior run in progress → proceed to **Phase 0** (fresh start) |
| `> 0` | Prior run found → **resume** (skip Phase 0, go to Phase 1) |

**If resuming:**

1. Reset any interrupted features:
   ```bash
   ./scripts/state-manager.sh reset-in-progress
   ```
   Features that were `in_progress` when the session ended are reset to `queued` — safer to re-plan than to continue from an unknown mid-execution state.

2. Print resume banner:
   ```
   🔄 Resuming autopilot — found existing state
      Branch:     <branch from state>
      Consultant: <consultant from state>
      Remaining:  <N> feature(s) pending
        [ ] F3: <name>
        [ ] F5: <name>
        ...
      Skipping initialization. Jumping to Phase 1.
   ```

3. Jump directly to **Phase 1** — the feature loop picks up from the first `queued` feature.

> The Runtime Context section at the top of this skill already injects the current state,
> so all this information is available before any command runs.

---

## Phase 0: Initialize

**Step 0 — Auto-install guard hook (runs every time, instant if already done):**
```bash
./scripts/install.sh
```
- If it prints `already-installed` (exit 0) → continue immediately
- If it prints `installed` (exit 1) → the hook was just registered for the first time. Print:
  ```
  ⚠ Guard hook installed for the first time.
    Please restart Claude Code and run the skill again — this is a one-time step.
  ```
  Then stop. On the next invocation (after restart) the hook will be active and autopilot proceeds normally.

1. **Detect available consultants** → run `scripts/detect-consultants.sh`
   - Tests each CLI with `--version` (fast, no API call)
   - Two levels: **external CLI** (real second opinion) vs **self-reasoning** (fallback)
   - **Ask the user to choose** (or confirm the recommended default):

   *Example — external CLIs found:*
   ```
   🔍 Consultant detection:
     ✅ claude:opus   — available ⭐ recommended
                        Opus = reasoning upgrade over orchestrating Sonnet
     ✅ claude:sonnet — available (same model family as orchestrator)
     ✅ codex         — available (different model family)
     ❌ gemini        — not found
     ❌ copilot       — not found
     ❌ cursor        — not found

   Which consultant when stuck? [claude:opus / claude:sonnet / codex]
   Default: claude:opus (press Enter to confirm)
   ```

   *Example — no external CLIs found:*
   ```
   🔍 Consultant detection:
     ❌ claude   — not found
     ❌ codex    — not found
     ❌ gemini   — not found
     ❌ copilot  — not found
     ❌ cursor   — not found

   ⚠ No external consultant available.
     Will reason through blockers independently (same model, same session).
     For a genuine second opinion, install the claude CLI and re-run.

   Continuing with self-reasoning fallback.
   ```

   - Save the chosen consultant to state as `consultant`
   - Valid values: `claude:opus`, `claude:sonnet`, `codex`, `gemini`, `copilot`, `cursor`, `self`
2. Initialize `.claude/autopilot-state.json` — parses the PRD and writes state in one command:
   ```bash
   BRANCH="autopilot/$(date +%Y%m%d)"
   ./scripts/state-manager.sh init <PRD_PATH> "$BRANCH"
   ```
   No intermediate files — `state-manager.sh init` calls `parse-prd.sh` internally.
3. Create a dedicated git branch: `git checkout -b "$BRANCH"`
5. **Activate the autopilot guard** — `touch .claude/autopilot-active`
   This enables the PreToolUse hook that blocks interactive Superpowers skills for the rest of this run.
6. Announce the queue to the user:
   ```
   🚀 Autopilot starting. Features queued:
     [ ] F1: <name>
     [ ] F2: <name>
     ...
   Consultant: <consultant> | Working autonomously. I'll report when done.
   ```

---

## Phase 1: Feature Loop

```
FOR each feature in .claude/autopilot-state.json WHERE status == "queued":
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

**Before consulting**, print the header:
```
┌─ 🤝 Consulting <consultant> — <trigger reason> [Feature: <feature-id>]
│  Q: <the exact question being sent>
│  Trigger context: <what failed / what is ambiguous — one sentence>
```

**Level 1 — External CLI** (consultant is anything other than `self`):
```bash
AUTOPILOT_CONSULTANT=$(./scripts/state-manager.sh get consultant) \
  ./scripts/consult.sh "<formatted question>" "<what failed or is ambiguous>"
```
`consult.sh` automatically prepends full project context to every call
(README + current feature spec + current plan via `scripts/build-context.sh`).
The second argument is the **trigger-specific context** only — what went wrong or what is unclear.
After receiving the answer:
```
│  A: <consultant answer, full text>
└─ ✔ Applying answer — retrying <plan/task/revert>
```

**Level 2 — Self-reasoning** (consultant is `self`, or external CLI fails at runtime):
Do not call `consult.sh`. Instead, reason through the problem directly using this structure:
- Restate the blocker in one sentence
- List 2–3 concrete options with trade-offs
- Pick the best option and justify it in one sentence
Then print:
```
┌─ 🤔 Self-reasoning — <trigger reason> [Feature: <feature-id>]
│  Q: <question>
│  A: <your reasoning — options considered + chosen approach>
└─ ✔ Applying self-reasoning — retrying <plan/task/revert>
```
Note: same model, same session — less independent than an external consultant.

See `references/consultant-patterns.md` for question templates per situation.

After consulting (either level):
- Log result to `consultations[]` in state with `type` (`external` or `self`), timestamp, Q&A
- Apply the answer and retry the failed step

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

1. **Deactivate the autopilot guard** — `rm -f .claude/autopilot-active`
   This re-enables all Superpowers interactive skills for normal use.

2. Print the summary:
```
📊 Autopilot Complete
══════════════════════════════════
Features done:    N / total
Features failed:  F / total
Consultations:    M
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

All state lives in `.claude/autopilot-state.json` — inside the project's `.claude/` folder, not in the project root.
Use `scripts/state-manager.sh` to read/write safely:

```bash
# Read
./scripts/state-manager.sh get current_feature
./scripts/state-manager.sh get features
./scripts/state-manager.sh get consultant

# Write
./scripts/state-manager.sh set-current-feature F1
./scripts/state-manager.sh set-feature-status F1 in_progress
./scripts/state-manager.sh set-plan-path F1 docs/superpowers/plans/2026-04-07-my-feature.md
./scripts/state-manager.sh set-commit F1 abc123
./scripts/state-manager.sh set-consultant claude:opus
./scripts/state-manager.sh increment consecutive_failures
./scripts/state-manager.sh reset-failures
./scripts/state-manager.sh reset-in-progress
./scripts/state-manager.sh pending-count
./scripts/state-manager.sh append-consultation F1 external "question" "answer"
./scripts/state-manager.sh append-consultation F1 self "question" "reasoning"
```

All writes use Python (read → modify → write in-place) — no `/tmp` files.

---

## Supporting Files

| File | Purpose |
|------|---------|
| `scripts/install.sh` | Auto-installs guard hook on first invocation; idempotent |
| `scripts/autopilot-guard.sh` | PreToolUse hook: blocks 4 interactive skills while `.claude/autopilot-active` exists |
| `scripts/parse-prd.sh` | Extract features from PRD.md → JSON |
| `scripts/state-manager.sh` | Read/write .claude/autopilot-state.json |
| `scripts/detect-consultants.sh` | Detect available consultant CLIs and recommend best option |
| `scripts/build-context.sh` | Assemble project context (README + feature spec + plan) for consultant calls |
| `scripts/consult.sh` | Call external consultant CLI with full project context; handles all consultant types |
| `scripts/check-tests.sh` | Run test suite, return pass/fail + diff |
| `references/prd-formats.md` | Supported PRD formats and parsing rules |
| `references/consultant-patterns.md` | When/how to consult per situation |
| `references/safety-rails.md` | Circuit breaker, rollback, cost guard logic |
| `templates/autopilot-state.template.json` | Initial state file structure |
| `templates/feature-context.template.md` | Per-feature context injection prompt |
