# superpowers-autopilot

> From PRD to production — zero human intervention.

A [Claude Code](https://claude.ai/code) skill that wraps [Superpowers](https://github.com/obra/superpowers) with an autonomous outer loop, turning the manual "pick feature → plan → execute → repeat" cycle into a fully automated pipeline.

---

## The Problem

Using Superpowers today looks like this:

```
PRD.md → [YOU pick feature] → brainstorm → [YOU approve] → writing-plans
       → [YOU say "go"] → subagent-driven-development → [YOU come back] → repeat
```

That's **4 manual touchpoints per feature**. If your PRD has 10 features, you're the bottleneck.

## The Solution

```
PRD.md → autopilot reads features
       → invokes writing-plans (auto)
       → invokes subagent-driven-development (auto)
       → [stuck?] → asks Codex for a second opinion
       → marks done → commits → next feature → repeat
       → [all done] → summary report + PR
```

**Zero manual interventions. You sleep, it ships.**

---

## Requirements

- [Claude Code](https://claude.ai/code) with Superpowers installed
- Superpowers skills available: `superpowers:writing-plans`, `superpowers:subagent-driven-development`
- A git repository with a PRD.md
- Optional: `codex` or `gemini` CLI for second-opinion consultations when stuck

---

## Installation

### Per-project (recommended for first use)

```bash
cd your-project
mkdir -p .claude/skills
git clone https://github.com/YOUR_USERNAME/superpowers-autopilot .claude/skills/superpowers-autopilot
```

### Global (available in all your projects)

```bash
git clone https://github.com/YOUR_USERNAME/superpowers-autopilot ~/.claude/skills/superpowers-autopilot
```

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
2. Create `autopilot-state.json` to track progress
3. Create a git branch `autopilot/YYYYMMDD`
4. Loop through each feature: plan → execute → test → commit
5. Consult Codex when stuck (if installed)
6. Print a summary report when done

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

**Superpowers brainstorm output** — paste the output of `superpowers:brainstorming` directly as your PRD.

---

## Safety Rails

Autopilot won't go rogue:

- **Circuit breaker** — pauses after 3 consecutive feature failures, asks for your input
- **Test regression protection** — snapshots your test suite before each feature; automatically reverts if existing tests break
- **Per-feature commits** — each feature is its own git commit, easy to revert individually
- **Dedicated branch** — never touches `main` directly

---

## How It Handles Being Stuck

When a plan fails validation or a subagent fails twice on the same task, autopilot consults an external model (Codex or Gemini CLI) for a second opinion — a different model means a genuinely different perspective, not an echo chamber.

If no external CLI is available, Claude reasons through it independently and documents its thinking in the state file.

All consultations are logged in `autopilot-state.json`.

---

## File Structure

```
superpowers-autopilot/
├── SKILL.md                          # Main skill (read this to understand the loop)
├── scripts/
│   ├── parse-prd.sh                  # Extract features from PRD.md
│   ├── state-manager.sh              # Read/write autopilot-state.json
│   ├── codex-consult.sh              # Wrapper for codex/gemini CLI
│   └── check-tests.sh                # Run tests, detect regressions
├── references/
│   ├── prd-formats.md                # Supported PRD formats
│   ├── codex-patterns.md             # When/how to consult Codex
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
- Test your changes against the fixtures in `evals/fixtures/` before submitting

---

## License

MIT — use it, fork it, build on it.

---

*Built for the Claude Code + Superpowers ecosystem — Cluj-Napoca, April 2026*
