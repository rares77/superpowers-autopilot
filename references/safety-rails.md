# Safety Rails

Autopilot runs autonomously. These mechanisms prevent it from causing damage.

---

## Circuit Breaker

**Purpose:** Stop cascading failures before they waste compute and corrupt the repo.

**Logic:**
```
consecutive_failures tracks how many features in a row have failed.

Before each feature:
  if consecutive_failures >= max_before_pause (default: 3):
    PAUSE — print summary, wait for user

After successful feature:
  reset consecutive_failures to 0

After failed feature:
  increment consecutive_failures
```

**When paused:**
```
⚠️  Circuit breaker triggered after 3 consecutive failures.

Failed features:
  ❌ F2: Dashboard — plan validation failed twice
  ❌ F3: Export PDF — subagent stuck on wkhtmltopdf dependency
  ❌ F4: Notifications — test regression not resolved

Remaining queued:
  ⏳ F5: Settings page
  ⏳ F6: Admin panel

Options:
  1. Fix the issues manually and run: /superpowers-autopilot --resume
  2. Skip failed features: /superpowers-autopilot --skip-failed --resume
  3. Abort: /superpowers-autopilot --abort
```

**Configuration:**
```json
"circuit_breaker": {
  "consecutive_failures": 0,
  "max_before_pause": 3
}
```

---

## Test Regression Protection

**Purpose:** Never let a new feature break existing functionality.

**Flow:**
```
Before each feature → scripts/check-tests.sh --snapshot
  (saves .autopilot-test-snapshot.json)

After execution → scripts/check-tests.sh --compare
  - No new failures? → commit and continue
  - New failures? → git revert last commit, Codex Consultation, retry once
  - Still failing after retry? → mark feature "failed", restore snapshot baseline
```

**Key property:** The snapshot captures which tests were *already* failing before autopilot started.
This means autopilot won't get stuck on pre-existing failures — only *new* regressions count.

---

## Rollback Strategy

**Each feature gets its own commit.** This is intentional — it makes rollback surgical.

```bash
# Revert a specific failed feature without touching others:
git revert <commit-sha-of-failed-feature> --no-edit
```

**Autopilot never force-pushes.** All work is on a dedicated branch (`autopilot/YYYYMMDD`).
The main branch is never touched directly.

**If a feature is marked "failed":**
- Its commit is reverted automatically
- State records `status: "failed"` with the reason
- Autopilot continues to the next feature

---

## Cost Guard (Optional)

Prevent runaway token usage per feature.

**Enable via environment variable:**
```bash
export AUTOPILOT_MAX_TOKENS_PER_FEATURE=50000
```

**How it works:**
- Estimated token usage is tracked per subagent call
- If a feature exceeds the budget, it's paused and flagged
- Autopilot doesn't abort — it marks the feature `"over_budget"` and moves on

**This is a soft limit** — it's a warning system, not a hard cutoff.
Setting it too low will cause features to be skipped prematurely.

---

## Retries and Limits

| Operation | Max attempts | On exhaustion |
|-----------|-------------|---------------|
| Planning (writing-plans) | 2 | Codex consultation, then skip |
| Per-task execution | 2 | Codex consultation, then skip task |
| Codex consultation per feature | 5 | Self-reason, continue |
| Full feature | 3 (attempts field) | Mark failed, increment circuit breaker |

These defaults are conservative. Increase them for complex features by editing the state directly.
