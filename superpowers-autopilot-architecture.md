# 🚀 Superpowers Autopilot — Plugin Architecture

## Concept

A Claude Code plugin that wraps Obra/Superpowers with an autonomous outer loop,
turning the manual "select feature → plan → execute → repeat" cycle into a
fully autonomous pipeline. When stuck, it consults Codex CLI as a "second opinion"
instead of asking the human.

**Tagline**: _"From PRD to Production — Zero Human Intervention"_

---

## The Problem It Solves

```
TODAY (manual):
┌─────────────────────────────────────────────────────────────────┐
│ PRD.md ──► [YOU pick feature] ──► Superpowers brainstorm       │
│         ──► [YOU approve] ──► writing-plans                    │
│         ──► [YOU say "go"] ──► subagent-driven-development     │
│         ──► [YOU come back] ──► next feature ──► repeat        │
└─────────────────────────────────────────────────────────────────┘
     4 manual interventions per feature × N features = bottleneck
```

```
WITH AUTOPILOT:
┌─────────────────────────────────────────────────────────────────┐
│ PRD.md ──► autopilot-loop reads features                       │
│         ──► invokes Superpowers writing-plans (auto)           │
│         ──► invokes subagent-driven-development (auto)         │
│         ──► [stuck?] ──► asks Codex for second opinion         │
│         ──► marks done ──► next feature ──► repeat             │
│         ──► [all done] ──► EXIT + summary report               │
└─────────────────────────────────────────────────────────────────┘
     0 manual interventions. You sleep, it ships.
```

---

## Architecture Overview

```
┌──────────────────────────────────────────────────────────────┐
│                    SUPERPOWERS AUTOPILOT                      │
│                                                              │
│  ┌────────────┐    ┌──────────────┐    ┌─────────────────┐  │
│  │  PRD Parser │───►│ Feature Queue │───►│ Orchestrator    │  │
│  │             │    │              │    │ (outer loop)    │  │
│  └────────────┘    └──────────────┘    └────────┬────────┘  │
│                                                  │           │
│                    ┌─────────────────────────────┼───────┐   │
│                    │         PER FEATURE         ▼       │   │
│                    │  ┌─────────────────────────────┐    │   │
│                    │  │  1. Context Injection        │    │   │
│                    │  │     (feature spec → prompt)  │    │   │
│                    │  └──────────┬──────────────────┘    │   │
│                    │             ▼                        │   │
│                    │  ┌─────────────────────────────┐    │   │
│                    │  │  2. Superpowers:writing-plans│    │   │
│                    │  │     (native skill invocation)│    │   │
│                    │  └──────────┬──────────────────┘    │   │
│                    │             ▼                        │   │
│                    │  ┌─────────────────────────────┐    │   │
│                    │  │  3. Plan Validator           │    │   │
│                    │  │     (sanity check tasks)     │    │   │
│                    │  └──────────┬──────────────────┘    │   │
│                    │             ▼                        │   │
│                    │  ┌─────────────────────────────┐    │   │
│                    │  │  4. Superpowers:subagent-    │    │   │
│                    │  │     driven-development       │    │   │
│                    │  │     (execution engine)       │    │   │
│                    │  └──────────┬──────────────────┘    │   │
│                    │             │                        │   │
│                    │             ▼                        │   │
│                    │  ┌─────────────────────────────┐    │   │
│                    │  │  5. Codex Consultant         │    │   │
│                    │  │     (on-demand, when stuck)  │    │   │
│                    │  │     codex -p "question"      │    │   │
│                    │  └──────────┬──────────────────┘    │   │
│                    │             ▼                        │   │
│                    │  ┌─────────────────────────────┐    │   │
│                    │  │  6. Feature Completion Gate  │    │   │
│                    │  │     (tests pass? commit!)    │    │   │
│                    │  └─────────────────────────────┘    │   │
│                    └─────────────────────────────────────┘   │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐    │
│  │  State Manager (autopilot-state.json)                │    │
│  │  - feature_queue: [{name, status, attempt, notes}]   │    │
│  │  - current_feature: string                           │    │
│  │  - codex_consultations: [{question, answer, time}]   │    │
│  │  - circuit_breaker: {failures: 0, max: 3}            │    │
│  └──────────────────────────────────────────────────────┘    │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐    │
│  │  Safety Rails                                        │    │
│  │  - Max iterations per feature (default: 5)           │    │
│  │  - Circuit breaker (3 consecutive failures → pause)  │    │
│  │  - Cost tracking (token budget per feature)           │    │
│  │  - Rollback on test regression                       │    │
│  └──────────────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────────────┘
```

---

## Plugin Structure (Claude Code Native)

```
superpowers-autopilot/
├── SKILL.md                          # Main skill (orchestrator logic)
├── scripts/
│   ├── parse-prd.sh                  # Extract features from PRD.md
│   ├── codex-consult.sh              # Wrapper for `codex -p "question"`
│   ├── check-tests.sh                # Run test suite, return pass/fail
│   └── state-manager.sh              # Read/write autopilot-state.json
├── references/
│   ├── prd-formats.md                # Supported PRD formats & parsing rules
│   ├── codex-patterns.md             # When/how to consult Codex effectively
│   └── safety-rails.md               # Circuit breaker & rollback logic
└── templates/
    ├── autopilot-state.template.json  # Initial state file template
    └── feature-context.template.md    # Context injection per feature
```

---

## Core Flow — Step by Step

### Phase 0: Initialize
```
User: /superpowers-autopilot "path/to/PRD.md"
```

1. Parse PRD → extract feature list with acceptance criteria
2. Create `autopilot-state.json` in project root
3. Create git branch: `autopilot/$(date +%Y%m%d)`
4. Display feature queue to user → "Starting. I'll work through these autonomously."

### Phase 1: Feature Loop (Outer)
```
FOR each feature in queue WHERE status != "done":
    set current_feature
    → Phase 2
```

### Phase 2: Planning (via Superpowers)
```
1. Inject feature context into prompt:
   "I'm implementing feature: {name}
    Spec: {acceptance_criteria}
    Constraints: {from PRD}
    Existing code context: {relevant files}"

2. Invoke Superpowers writing-plans skill
   → Generates task list with file paths, test commands, code

3. Validate plan:
   - Has at least 1 test per task?
   - File paths exist or will be created?
   - No circular dependencies?
   
   IF validation fails → consult Codex (Phase 2b)
```

### Phase 2b: Codex Consultation (When Stuck)
```
TRIGGER CONDITIONS:
  - Plan validation fails
  - Subagent fails same task 2x
  - Test suite regresses after implementation
  - Ambiguous requirement in PRD

ACTION:
  question = format_question(context, error, feature_spec)
  answer = $(codex -p "$question" --approval-mode full-auto)
  
  Log to state: codex_consultations[]
  Apply answer → retry failed step
```

### Phase 3: Execution (via Superpowers)
```
1. Invoke subagent-driven-development with generated plan
2. Each task:
   a. Subagent implements (TDD: red → green → refactor)
   b. Code review subagent validates
   c. IF fail after 2 attempts → Codex Consultation
   d. IF pass → next task

3. After all tasks:
   a. Run full test suite
   b. IF all pass → git commit with conventional message
   c. IF regression → rollback last task, Codex Consultation
```

### Phase 4: Feature Completion
```
1. Mark feature as "done" in state
2. Update progress: "✅ Feature {N}/{total}: {name} complete"
3. Git commit: "feat({feature-name}): implement per PRD spec"
4. → back to Phase 1 (next feature)
```

### Phase 5: All Done
```
1. Generate summary report:
   - Features implemented: N/N
   - Codex consultations: M (with Q&A log)
   - Test coverage: X%
   - Total time: H hours
   - Token usage estimate
   
2. Create PR if on feature branch
3. EXIT
```

---

## PRD Format Support

The parser should handle multiple PRD formats:

### Format A: Markdown Headers
```markdown
## Features
### F1: User Authentication
- OAuth2 with Google/GitHub
- JWT token management
- Acceptance: login flow completes in <2s

### F2: Dashboard
- Real-time data display
- Acceptance: updates within 500ms
```

### Format B: YAML Frontmatter + Sections
```yaml
---
features:
  - id: F1
    name: User Authentication
    priority: high
    acceptance_criteria:
      - OAuth2 login works
      - JWT tokens refresh automatically
---
```

### Format C: Superpowers Native (brainstorm output)
Parse the design document that Superpowers brainstorming generates,
extract the "what we're building" sections as features.

---

## Codex Consultation Protocol

### When to Ask Codex
| Situation                  | Question Template                                  |
|----------------------------|----------------------------------------------------|
| Ambiguous requirement      | "Given this spec: {spec}, what's the best approach |
|                            |  for {ambiguity}? Context: {tech_stack}"           |
| Implementation stuck       | "This test fails: {error}. Code: {snippet}.        |
|                            |  What's wrong?"                                    |
| Architecture decision      | "For {feature}, should I use {option_A} or         |
|                            |  {option_B}? PRD says: {relevant_section}"         |
| Test regression            | "After implementing {task}, these tests broke:     |
|                            |  {failures}. How to fix without reverting?"         |

### Why Codex (not Gemini, not Claude)?
- Different model = genuinely different perspective (not echo chamber)
- Codex CLI has `--approval-mode full-auto` → no human needed
- Fast responses for targeted questions
- Cost-effective for short consultations

### Configurable Consultant
```json
{
  "consultant": {
    "primary": "codex -p",
    "fallback": "gemini -p",
    "max_consultations_per_feature": 5,
    "timeout_seconds": 120
  }
}
```

---

## State Management

### autopilot-state.json
```json
{
  "prd_path": "docs/PRD.md",
  "started_at": "2026-04-07T10:00:00Z",
  "branch": "autopilot/20260407",
  "features": [
    {
      "id": "F1",
      "name": "User Authentication",
      "status": "done",
      "attempts": 1,
      "plan_path": "docs/plans/F1-auth-plan.md",
      "commit_sha": "abc123",
      "codex_consultations": []
    },
    {
      "id": "F2",
      "name": "Dashboard",
      "status": "in_progress",
      "attempts": 2,
      "plan_path": "docs/plans/F2-dashboard-plan.md",
      "commit_sha": null,
      "codex_consultations": [
        {
          "question": "Should I use WebSocket or SSE for real-time?",
          "answer": "SSE is simpler and sufficient for one-directional updates...",
          "timestamp": "2026-04-07T11:32:00Z"
        }
      ]
    },
    {
      "id": "F3",
      "name": "Export to PDF",
      "status": "queued",
      "attempts": 0,
      "plan_path": null,
      "commit_sha": null,
      "codex_consultations": []
    }
  ],
  "circuit_breaker": {
    "consecutive_failures": 0,
    "max_before_pause": 3
  },
  "stats": {
    "features_done": 1,
    "features_total": 3,
    "total_codex_consultations": 1,
    "started_at": "2026-04-07T10:00:00Z"
  }
}
```

---

## Safety Rails

### Circuit Breaker
- 3 consecutive failures on same feature → PAUSE
- Log detailed error → notify user (if notification hook exists)
- Skip to next feature OR wait for human input
- Configurable: `"max_before_pause": 3`

### Cost Guard
- Track token usage per feature (estimated from subagent calls)
- If feature exceeds budget → pause and report
- Default budget: configurable per feature priority

### Test Regression Protection
- Before each feature: snapshot test results
- After feature: compare → if ANY existing test broke → auto-rollback
- Never let a new feature break existing functionality

### Rollback Strategy
- Each feature on its own git commit
- If feature fails completely → `git revert` → mark as "failed"
- Move to next feature, don't block the queue

---

## LinkedIn Post Draft

> 🚀 Am construit un plugin care face Superpowers fully autonomous.
>
> Superpowers (de @Jesse Vincent) e excelent la planning: brainstorm →
> spec → TDD plan. Dar între cicluri, tot tu ești bottleneck-ul.
>
> "superpowers-autopilot" adaugă un outer loop care:
> 📋 Citește PRD-ul și extrage features automat
> 🔄 Invocă Superpowers writing-plans + execution per feature
> 🤖 Când e blocat, consultă Codex CLI ca "second opinion"
> ✅ Marchează done, commit, next feature, repeat
> 🛡️ Circuit breaker + test regression protection
>
> De la PRD la cod testat — zero intervenție umană.
>
> Pipeline-ul multi-model (Claude orchestrează, Codex consultă)
> e un pattern pe care l-am validat în producție.
>
> Open source pe GitHub. Feedback welcome!
>
> #ClaudeCode #Superpowers #AutonomousCoding #AI #OpenSource

---

## Development Plan (meta — for building the plugin itself)

### Sprint 1: Core Loop (MVP)
- [ ] PRD parser (markdown headers format)
- [ ] State manager (read/write JSON)
- [ ] Orchestrator loop (feature queue → planning → execution)
- [ ] Integration with Superpowers writing-plans
- [ ] Integration with Superpowers subagent-driven-development
- [ ] Basic circuit breaker

### Sprint 2: Codex Integration
- [ ] Codex consultation wrapper script
- [ ] Trigger conditions (stuck detection)
- [ ] Question formatting templates
- [ ] Consultation logging to state

### Sprint 3: Safety & Polish
- [ ] Test regression detection
- [ ] Git rollback on failure
- [ ] Cost tracking (estimated)
- [ ] Summary report generation
- [ ] Support for YAML PRD format

### Sprint 4: Multi-Consultant & Community
- [ ] Configurable consultant (Codex / Gemini / local model)
- [ ] Notification hooks (Discord, Slack)
- [ ] Plugin marketplace submission
- [ ] Documentation & examples

---

## Name Ideas

| Name                     | Vibe                              |
|--------------------------|-----------------------------------|
| superpowers-autopilot    | Clear, descriptive                |
| superpowers-unleashed    | Marketing-friendly                |
| superloop                | Short, memorable                  |
| prd-to-prod              | Describes the full pipeline       |
| autonomous-superpowers   | Explicit about what it adds       |
| superpowers-ralph        | Nod to the Ralph loop technique   |

---

*Architecture by Rares — Cluj-Napoca, April 2026*
*Built for the Claude Code ecosystem*
