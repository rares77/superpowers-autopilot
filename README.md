# superpowers-autopilot

> From PRD to production with one bootstrap step.

A [Claude Code](https://claude.ai/code) skill that wraps [Superpowers](https://github.com/obra/superpowers) with an autonomous outer loop, turning the manual "pick feature → plan → execute → repeat" cycle into a fully automated pipeline.

---

## Full Superpowers Flow

Superpowers has two distinct phases:

**Phase 1 — Design** (done once, with you):
```
/brainstorming → spec doc (docs/superpowers/specs/) → you approve → PRD.md ready
```

**Phase 2 — Implementation** (per feature, manual by default):
```
PRD.md → [YOU pick feature] → writing-plans → [YOU say "go"]
       → subagent-driven-development → [YOU come back] → repeat
```

That's **3 manual touchpoints per feature**. If your PRD has 10 features, you're the bottleneck.

## The Solution

Autopilot takes over Phase 2 entirely. After one startup choice of consultant, each feature goes through an autonomous design review, planning, execution, and test cycle:

```
PRD.md → autopilot reads features
       → [per feature]:
           → design review (resolves ambiguities via consultant)
           → writing-plans (auto)
           → subagent-driven-development (auto)
           → tests
       → main session commits → next feature → repeat
       → [all done] → summary report
```

**One bootstrap choice, then zero manual interventions per feature. You sleep, it ships.**

> **Note:** Without a PRD, Superpowers works normally — brainstorming runs as usual, you interact with it, and it produces the PRD. Autopilot only kicks in when you have a PRD ready.

---

## Requirements

- [Claude Code](https://claude.ai/code) with Superpowers installed
- Superpowers skills available: `superpowers:writing-plans`, `superpowers:subagent-driven-development`
- A git repository with a PRD.md (typically the output of `superpowers:brainstorming`)
- Python 3 available on `PATH` as `python3`
- Optional: a consultant CLI for second-opinion consultations when stuck (`claude`, `codex`, `gemini`, `copilot`, or `cursor`)

---

## Installation

Run the setup commands from an existing git repository. If the project is new,
initialize it first with `git init`.

### Per-project

```bash
cd your-project
# if needed: git init
git clone https://github.com/rares77/superpowers-autopilot .claude/skills/superpowers-autopilot
.claude/skills/superpowers-autopilot/scripts/install.sh
```

### Global (available in all your projects)

```bash
git clone https://github.com/rares77/superpowers-autopilot ~/.claude/skills/superpowers-autopilot
cd your-project
# if needed: git init
~/.claude/skills/superpowers-autopilot/scripts/install.sh
```

The install step registers the project-level guard hook in `.claude/settings.json`. Restart Claude Code after this step so both the skill and the hook are loaded together. In the recommended onboarding flow, this is a one-time restart per project.

The setup, parsing, and state-management scripts require `python3`.

If you skip the install step, the skill will try to install the hook on first invocation as a fallback and will then ask you to restart before continuing.

### Keeping it updated

```bash
# Per-project
cd your-project/.claude/skills/superpowers-autopilot && git pull

# Global
cd ~/.claude/skills/superpowers-autopilot && git pull
```

---

## Try It With the Sample PRD

The `samples/` folder contains a ready-to-run TODO app PRD designed to showcase how the skill works. To try it:

1. Create a new empty git repository:
   ```bash
   mkdir todo-test && cd todo-test && git init
   ```
2. Install the skill and guard hook:
   ```bash
   git clone https://github.com/rares77/superpowers-autopilot .claude/skills/superpowers-autopilot
   .claude/skills/superpowers-autopilot/scripts/install.sh
   ```
3. Restart Claude Code once so the hook is active.
4. Copy the sample PRD into it:
   ```bash
   cp .claude/skills/superpowers-autopilot/samples/PRD.md .
   # or if installed globally:
   cp ~/.claude/skills/superpowers-autopilot/samples/PRD.md .
   ```
5. Open Claude Code in that folder and run:
   ```
   /superpowers-autopilot PRD.md
   ```

Features 1 and 2 contain deliberate ambiguities — vague storage requirements, undefined validation rules, subjective UX directives ("best approach", "industry standard"). You'll see the design review catch each one, send it to the consultant, and apply the answer before planning begins. Feature 3 is intentionally clear, so the skill proceeds directly to planning with no consultation needed.

It's the fastest way to understand what the skill actually does end-to-end.

---

## Usage

Open Claude Code in your project and run:

```
/superpowers-autopilot path/to/PRD.md
```

Or just describe what you want — the skill is selected automatically based on intent:

```
"implement everything in docs/PRD.md autonomously, no manual steps"
"run autopilot on my PRD"
"PRD to production, zero manual steps"
```

Claude Code matches your message against each skill's description and picks the best fit. You don't need to type `/superpowers-autopilot` explicitly — any phrasing that conveys "implement a PRD automatically" will trigger this skill.

**Recommended first run:** Install the guard hook with `scripts/install.sh`, restart Claude Code once, then invoke the skill.

**Fallback behavior:** If the hook was not installed yet, the skill installs it on first invocation and asks you to restart before continuing. This is a safety net, not the recommended onboarding path.

**After restart:** Claude will:
1. Parse your PRD and extract the feature list
2. Ask which consultant to use when stuck (Claude Opus recommended). This is the only operational choice before the autonomous run starts.
3. Create `.claude/autopilot-state.json` to track progress
4. Create a git branch `autopilot/YYYYMMDD`
5. For each feature:
   - Review the spec for ambiguities, resolve via consultant
   - Create a plan via `writing-plans`
   - Execute via `subagent-driven-development`
   - Run tests
   - Commit
6. Print a summary report when done

After step 2, autopilot no longer asks the user for per-feature guidance. Ambiguities, plan gaps, and retries go to the selected consultant or to self-reasoning fallback.

---

## PRD Format Support

The parser handles two markdown-based formats automatically:

**Markdown headers** (most common):
```markdown
## Features

### F1: User Authentication
- OAuth2 with Google
- Acceptance: login completes in <2s

### F2: Dashboard
- Real-time updates
- Acceptance: data refreshes within 500ms
```

**Superpowers spec doc** — use the spec generated by `superpowers:brainstorming` (saved at `docs/superpowers/specs/`) directly as your PRD input.

---

## Safety Rails

Autopilot won't go rogue:

- **Guard hook** — blocks 4 interactive Superpowers skills during the run; automatically OFF between runs
- **Circuit breaker** — pauses after 3 consecutive feature failures, asks for your input
- **Test regression protection** — automatically reverts if existing tests break after a feature
- **Per-feature commits** — each feature is its own git commit, easy to revert individually
- **Dedicated branch** — never touches `main` directly

### How the guard hook works

During setup, `scripts/install.sh` registers a PreToolUse hook that blocks four Superpowers skills that would otherwise hijack the autonomous loop. If setup was skipped, the first invocation installs the same hook as a fallback and asks for a restart before continuing:

| Blocked skill | Why |
|---|---|
| `superpowers:brainstorming` | Has aggressive "MUST use before any creative work" directive that hijacks the loop |
| `superpowers:finishing-a-development-branch` | Triggers manual PR review flow incompatible with automation |
| `superpowers:executing-plans` | Opens interactive selection; autopilot owns execution mode |
| `superpowers:using-git-worktrees` | Forks the working tree mid-feature, breaking the commit sequence |

The guard is **OFF by default** — it only activates when autopilot is running (Phase 0 creates `.claude/autopilot-active`; Phase 5 removes it). You can invoke all these skills normally at any other time.

To uninstall: `./scripts/install.sh --uninstall`

---

## How It Handles Being Stuck

The autopilot consults a second opinion in three situations:
1. **Ambiguous spec** — contradictory or vague requirements in the PRD
2. **Plan validation fails** — generated plan has gaps or placeholders
3. **Task fails twice** — same implementation task fails on retry

There are two levels, detected automatically at startup:

**Level 1 — External CLI** (real second opinion, isolated subprocess):

| Consultant | How it's invoked |
|---|---|
| `claude:opus` | `claude -p --model claude-opus-4-6` ⭐ recommended |
| `claude:sonnet` | `claude -p --model claude-sonnet-4-6` |
| `codex` | `echo … \| codex exec - --full-auto` (`codex exec`; `-p` is `--profile`) |
| `gemini` | `gemini -p "…" --approval-mode plan` |
| `copilot` | `copilot -p "…" -s --no-ask-user` |
| `cursor` | `cursor agent -p --mode ask` (Agent CLI, not IDE `cursor`) |

**Level 2 — Self-reasoning** (fallback when no external CLI is available):
The model reasons through the blocker inline — listing options, trade-offs, and chosen approach. Less independent than a real second opinion, but documented and logged the same way.

Every consultation automatically includes full project context — README, current feature spec, and current plan — so the consultant has everything it needs to give a relevant answer, not just generic advice.

All consultations are logged in `.claude/autopilot-state.json` with type (`external` or `self`), timestamps, and full Q&A.

---

## File Structure

```
superpowers-autopilot/
├── SKILL.md                          # Main skill (read this to understand the loop)
├── scripts/
│   ├── install.sh                    # Installs the project guard hook during setup; fallback on first run
│   ├── autopilot-guard.sh            # PreToolUse hook: blocks 4 skills during runs
│   ├── parse-prd.sh                  # Extract features from PRD.md
│   ├── state-manager.sh              # Read/write .claude/autopilot-state.json
│   ├── detect-consultants.sh         # Detect available consultant CLIs
│   ├── build-context.sh              # Assemble project context for consultant calls
│   ├── consult.sh                    # Call consultant with full project context
│   └── check-tests.sh                # Run tests, detect regressions
├── references/
│   ├── prd-formats.md                # Supported PRD formats
│   ├── consultant-patterns.md        # When/how to consult external models
│   └── safety-rails.md               # Circuit breaker & rollback logic
└── templates/
    ├── autopilot-state.template.json  # Initial state structure
    └── feature-context.template.md    # Per-feature planning prompt
```

---

## Contributing

PRs are welcome. A few things to know:

- Open an issue first for anything beyond small fixes — I want to discuss direction before you invest time
- The skill follows [Superpowers skill conventions](https://github.com/obra/superpowers)
- Test your changes against a real PRD before submitting

---

## License

MIT — use it, fork it, build on it.

---

*Built for the Claude Code + Superpowers ecosystem*
