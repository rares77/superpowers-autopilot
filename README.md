# superpowers-autopilot

> From PRD to production — zero human intervention.

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

Autopilot takes over Phase 2 entirely. Each feature goes through an autonomous design review, planning, execution, and test cycle:

```
PRD.md → autopilot reads features
       → [per feature]:
           → design review (resolves ambiguities via consultant)
           → writing-plans (auto)
           → subagent-driven-development (auto)
           → tests
       → main session commits → next feature → repeat
       → [all done] → summary report + PR
```

**Zero manual interventions. You sleep, it ships.**

> **Note:** Without a PRD, Superpowers works normally — brainstorming runs as usual, you interact with it, and it produces the PRD. Autopilot only kicks in when you have a PRD ready.

---

## Requirements

- [Claude Code](https://claude.ai/code) with Superpowers installed
- Superpowers skills available: `superpowers:writing-plans`, `superpowers:subagent-driven-development`
- A git repository with a PRD.md (typically the output of `superpowers:brainstorming`)
- Optional: a consultant CLI for second-opinion consultations when stuck (`claude`, `codex`, `gemini`, `gh copilot`, or `cursor`)

---

## Installation

### Per-project (recommended for first use)

```bash
cd your-project
mkdir -p .claude/skills
git clone https://github.com/rares77/superpowers-autopilot .claude/skills/superpowers-autopilot
.claude/skills/superpowers-autopilot/scripts/autopilot-mode.sh
```

### Global (available in all your projects)

```bash
git clone https://github.com/rares77/superpowers-autopilot ~/.claude/skills/superpowers-autopilot
```

For each project where you want to use autopilot, run the setup script from the project root:

```bash
~/.claude/skills/superpowers-autopilot/scripts/autopilot-mode.sh
```

### What does autopilot-mode.sh do?

It installs a **PreToolUse hook** that blocks four Superpowers interactive skills during autopilot runs:

| Blocked skill | Why |
|---|---|
| `superpowers:brainstorming` | Has aggressive "MUST use before any creative work" directive that hijacks the loop |
| `superpowers:finishing-a-development-branch` | Triggers manual PR review flow incompatible with automation |
| `superpowers:executing-plans` | Opens interactive selection; autopilot owns execution mode |
| `superpowers:using-git-worktrees` | Forks the working tree mid-feature, breaking the commit sequence |

**The guard is OFF by default.** It only activates when autopilot is running (Phase 0 creates `.claude/autopilot-active`; Phase 5 removes it). You can still invoke all these skills manually at any other time.

**One-time restart required** after running `autopilot-mode.sh` — Claude Code reads hook registrations at startup. After that, the guard activates and deactivates automatically with no further restarts.

To undo: `./scripts/autopilot-mode.sh --uninstall`

### Keeping it updated

```bash
# Per-project
cd your-project/.claude/skills/superpowers-autopilot && git pull

# Global
cd ~/.claude/skills/superpowers-autopilot && git pull
```

---

## Usage

Open Claude Code in your project and run:

```
/superpowers-autopilot path/to/PRD.md
```

Or just describe what you want:

```
"implement everything in docs/PRD.md autonomously, no manual steps"
```

Claude will:
1. Parse your PRD and extract the feature list
2. Ask which consultant to use when stuck (Claude Opus recommended)
3. Create `autopilot-state.json` to track progress
4. Create a git branch `autopilot/YYYYMMDD`
5. Activate the guard (`touch .claude/autopilot-active`)
6. For each feature:
   - Review the spec for ambiguities, resolve via consultant
   - Create a plan via `writing-plans`
   - Execute via `subagent-driven-development`
   - Run tests
   - Commit
7. Deactivate the guard (`rm .claude/autopilot-active`)
8. Print a summary report when done

---

## PRD Format Support

The parser handles three formats automatically:

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

**YAML frontmatter:**
```yaml
---
features:
  - id: F1
    name: User Authentication
    acceptance_criteria:
      - OAuth2 login works
---
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

---

## How It Handles Being Stuck

The autopilot consults an external model in three situations:
1. **Ambiguous spec** — contradictory or vague requirements in the PRD
2. **Plan validation fails** — generated plan has gaps or placeholders
3. **Task fails twice** — same implementation task fails on retry

A different model means a genuinely different perspective, not an echo chamber. Supported consultants: `claude` (Opus, recommended), `codex`, `gemini`, `gh copilot`, `cursor`.

If no external CLI is available, Claude reasons through it independently and documents its thinking in the state file.

All consultations are logged in `autopilot-state.json` with timestamps and full Q&A.

---

## File Structure

```
superpowers-autopilot/
├── SKILL.md                          # Main skill (read this to understand the loop)
├── scripts/
│   ├── autopilot-mode.sh             # One-time setup: installs the guard hook
│   ├── autopilot-guard.sh            # PreToolUse hook: blocks 4 skills during runs
│   ├── parse-prd.sh                  # Extract features from PRD.md
│   ├── state-manager.sh              # Read/write autopilot-state.json
│   ├── consult.sh                    # Wrapper for consultant CLIs
│   ├── detect-consultants.sh         # Detect available consultant CLIs
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
