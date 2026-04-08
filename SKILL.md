---
name: superpowers-autopilot
description: Use when the user wants to implement all features from a PRD.md with autonomous execution after initial setup and consultant selection — "run autopilot on my PRD", "implement everything from PRD", "autopilot mode", "PRD to production", or wants Claude to work through a feature list unattended. Orchestrates superpowers:writing-plans and superpowers:subagent-driven-development in a loop per feature, consulting an external CLI when stuck. Use this skill even if the user just drops a PRD.md path and says "go".
---

# Superpowers Autopilot

## Runtime Context

Runtime state is checked explicitly in `Resume Check` and `Phase 0`.
Do not execute bash from this section during skill initialization.

## Overview

Autonomous outer loop that implements every feature in a PRD.md with a single bootstrap choice at startup. You read the PRD, let the user choose the consultant once during initialization, then queue features, plan and execute each one using Superpowers skills, consult that chosen CLI when stuck, and exit with a summary report.

**Invocation:** `/superpowers-autopilot <path/to/PRD.md>`

## Autopilot Rules

1. **Interactive Superpowers skills are blocked by the guard hook** — `brainstorming`, `finishing-a-development-branch`, `executing-plans`, and `using-git-worktrees` are denied at the tool level while `.claude/autopilot-active` exists. You don't need to avoid them manually; the hook enforces it.
2. **Only ask the user one operational question during Phase 0** — let them choose the consultant from the detected options (or accept the recommended default). After that, do not ask further questions during execution; all ambiguities and clarifications go to the consultant (Phase 2b).
3. **NEVER wait for user approval after Phase 0** — once initialization is complete, the loop is fully autonomous until all features are done or the circuit breaker fires.
4. **ALWAYS choose subagent-driven execution** when `writing-plans` asks — never inline, never ask the user which one.
5. **Design review replaces brainstorming** — scan every feature spec for ambiguities before planning, resolve them via the consultant, then invoke `writing-plans` with the resolved spec.
6. **When running shell commands from this skill, invoke only the bare wrapper command exactly as written.** Do not append `2>&1`, `; echo`, `&&`, `||`, or any extra shell decoration.

## Prerequisites

- PRD.md exists at the provided path
- Project is a git repository (clean working tree preferred)
- Superpowers skills available: `writing-plans` and `subagent-driven-development` (prefixed as `superpowers:writing-plans` / `superpowers:subagent-driven-development` in Claude Code)
- Optional: a consultant CLI installed for second-opinion consultations (falls back gracefully)

---

## Resume Check

**Run this before anything else, every invocation:**

```bash
./.claude/autopilot.sh startup-status
```

- If the JSON says `"mode": "resume"` → skip Phase 0 and resume.
- If the JSON says `"mode": "fresh"` and `"restart_required": true` → print the restart message below and stop.
- If the JSON says `"mode": "fresh"` and `"restart_required": false` → use the embedded consultant metadata for the picker.

**If resuming:**

1. Reset any interrupted features:
   ```bash
   ./.claude/autopilot.sh state reset-in-progress
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

**Step 0 — Inspect startup status once:**
```bash
./.claude/autopilot.sh startup-status
```
- This single command handles: legacy-state migration, resume detection, fallback install, and consultant detection.
- If the JSON says `"restart_required": true`, print:
  ```
  ⚠ Guard hook was not installed yet, so autopilot installed it now.
    Please restart Claude Code and run the skill again.
    Recommended onboarding is to run scripts/install.sh before the first invocation so only one restart is needed.
  ```
  Then stop.
- Otherwise, use the returned `consultants` object directly. Do not run `resume-check`, `verify-install`, or `detect-consultants` separately.

1. **Ask the user to choose the consultant** from the `consultants` object returned by `startup-status`
   - Tests each CLI with `--version` (fast, no API call)
   - Two levels: **external CLI** (real second opinion) vs **self-reasoning** (fallback)
   - **Ask the user to choose** (or confirm the recommended default). This is the only operational question autopilot asks before the autonomous run begins.
   - Keep the prompt short and picker-like. Do not read the PRD, summarize features, or perform any other work before the user answers.
   - Stop after printing the consultant picker and wait for the user's choice.

   *Example — external CLIs found:*
   ```
   Consultant?
   [claude:opus] recommended
   [claude:sonnet]
   [codex]
   Reply with one option, or press Enter for claude:opus.
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

   - Keep the chosen consultant in memory for the next step
   - Valid values: `claude:opus`, `claude:sonnet`, `codex`, `gemini`, `copilot`, `cursor`, `self`
2. Initialize the run in one command:
   ```bash
   ./.claude/autopilot.sh start-run <PRD_PATH> <chosen-consultant>
   ```
   - This single command parses the PRD, initializes state, saves the consultant, creates the branch, and activates `.claude/autopilot-active`.
3. Announce the queue to the user:
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
2. Update state for the new active feature in one command:
   ```bash
   ./.claude/autopilot.sh begin-feature <feature-id>
   ```
   This sets both `current_feature` and `status = "in_progress"` before any consultant call.
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
6. **Invoke `writing-plans`** (also known as `superpowers:writing-plans` in Claude Code) with the resolved feature spec (not the original PRD text)
   Before invoking it, apply these autopilot-specific constraints:
   - Treat `.claude/` and cloned skill files as tooling noise, not project source. When assessing project structure, focus on user-owned files only.
   - If the repo only contains `PRD.md` plus tooling folders, treat it as a fresh repo.
   - Create `docs/superpowers/plans/` before saving the plan if it does not exist.
   - When saving the plan with the Write tool, use the required `file_path` parameter.
   - Keep the plan document implementation-oriented but avoid raw risky DOM sink examples such as `innerHTML`. Prefer textual steps or safe DOM APIs like `textContent`, `replaceChildren`, and `append`.
   - Avoid the literal token `exec(` anywhere in the plan text, even for harmless APIs like SQLite `db.exec()`, because some security hooks flag it as command execution. Prefer alternatives like `db.prepare(...).run(...)` or plain-text descriptions.
   - If a Write hook blocks the plan document because of a risky example or false-positive pattern match, rewrite the plan text to remove the trigger phrase. Do not start changing implementation files during planning.
   - Do not ask the user which execution mode to use. Autopilot always chooses subagent-driven execution.
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
AUTOPILOT_CONSULTANT="$(./.claude/autopilot.sh state get consultant)"
./.claude/autopilot.sh consult "<formatted question>" "<what failed or is ambiguous>"
```
`consult.sh` automatically prepends full project context to every call
(README + current feature spec + current plan via `./.claude/autopilot.sh build-context`).
The second argument is the **trigger-specific context** only — what went wrong or what is unclear.
When asking the consultant, treat it as a narrow second-opinion call, not a delegated agent:
- answer the question directly
- choose one option explicitly when options are given
- do not inspect repository files
- do not invoke skills
- do not propose workflows or planning rituals
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
2. **Invoke `subagent-driven-development`** (also known as `superpowers:subagent-driven-development` in Claude Code) with the validated plan
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
5. After all tasks complete → run `./.claude/autopilot.sh check-tests` and print:
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
```

---

## State Management

All state lives in `.claude/autopilot-state.json` — inside the project's `.claude/` folder, not in the project root.
Use `./.claude/autopilot.sh state` to read/write safely:

```bash
# Read
./.claude/autopilot.sh state get current_feature
./.claude/autopilot.sh state get features
./.claude/autopilot.sh state get consultant

# Write
./.claude/autopilot.sh state set-current-feature F1
./.claude/autopilot.sh state set-feature-status F1 in_progress
./.claude/autopilot.sh begin-feature F1
./.claude/autopilot.sh state set-plan-path F1 docs/superpowers/plans/2026-04-07-my-feature.md
./.claude/autopilot.sh state set-commit F1 abc123
./.claude/autopilot.sh state set-consultant claude:opus
./.claude/autopilot.sh state increment consecutive_failures
./.claude/autopilot.sh state reset-failures
./.claude/autopilot.sh state reset-in-progress
./.claude/autopilot.sh state pending-count
./.claude/autopilot.sh state append-consultation F1 external "question" "answer"
./.claude/autopilot.sh state append-consultation F1 self "question" "reasoning"
```

All writes use Python (read → modify → write in-place) — no `/tmp` files.

---

## Supporting Files

| File | Purpose |
|------|---------|
| `scripts/install.sh` | Installs the project guard hook during setup; fallback if setup was skipped |
| `scripts/autopilot.sh` | Single runtime entrypoint for state, consultant detection, context, parsing, and test checks |
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
