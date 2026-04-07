# Codex Consultation Patterns

When to call Codex and how to phrase the question effectively.
Used by `scripts/codex-consult.sh` and referenced in SKILL.md Phase 2b.

---

## When to Consult

| Situation | Trigger condition |
|-----------|------------------|
| Plan validation fails | Plan has no tests, missing files, or circular deps |
| Subagent stuck | Same task fails 2× in a row |
| Test regression | Existing tests break after implementation |
| Ambiguous requirement | PRD has conflicting or unclear acceptance criteria |
| Architecture decision | Multiple valid approaches, not clear which fits the stack |

**Don't consult for:** obvious syntax errors, missing imports, typos. Fix those directly.

---

## Question Templates

### Ambiguous Requirement
```
Given this spec: "{acceptance_criteria}"
and this tech stack: {detected_stack},
what's the most pragmatic interpretation of "{ambiguity}"?
Constraints: {constraints_from_prd}
Give a one-paragraph answer with a concrete recommendation.
```

### Implementation Stuck (test failing)
```
This test is failing:
---
{test_name}
Error: {error_message}
Relevant code:
{code_snippet_max_50_lines}
---
What's the root cause and what's the minimal fix?
Don't suggest rewriting the whole module.
```

### Architecture Decision
```
Implementing feature: {feature_name}
Tech stack: {stack}
Two options:
  A) {option_a} — pros: {pros_a}, cons: {cons_a}
  B) {option_b} — pros: {pros_b}, cons: {cons_b}
PRD says: "{relevant_prd_section}"
Which is better here, and why? One paragraph.
```

### Test Regression
```
After implementing "{task_name}", these previously-passing tests broke:
{failing_test_names}
The changes I made:
{git_diff_summary}
How do I fix the regression without reverting the feature?
```

---

## Formatting Rules

1. **Be specific** — include actual error messages, not paraphrases
2. **Cap code snippets** at 50 lines — Codex doesn't need the whole file
3. **One question per call** — don't bundle multiple decisions
4. **State constraints upfront** — "without changing the public API", "must work in Node 18"
5. **Ask for the reasoning** — "and why?" helps you evaluate if the answer applies

---

## Logging

Every consultation must be logged via state-manager:
```bash
./scripts/state-manager.sh append-codex "$FEATURE_ID" "$QUESTION" "$ANSWER"
```

This creates an audit trail in `autopilot-state.json` and increments `total_codex_consultations`.

---

## If Codex Is Unavailable

`codex-consult.sh` exits with code 2 when no consultant is available.
In this case: reason through it independently using Claude's own knowledge,
document your reasoning in the state as a "self-consultation", and continue.

The key insight is that Codex provides a *different perspective*, not necessarily a *better* one.
Claude's own reasoning is a valid fallback.
