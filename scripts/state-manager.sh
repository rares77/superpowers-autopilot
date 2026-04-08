#!/usr/bin/env bash
# state-manager.sh — Read/write autopilot-state.json
# Usage:
#   ./scripts/state-manager.sh get <key>
#   ./scripts/state-manager.sh init <prd-path> <branch> <features-json>
#   ./scripts/state-manager.sh set-current-feature <feature-id>
#   ./scripts/state-manager.sh set-feature-status <feature-id> <status>
#   ./scripts/state-manager.sh set-plan-path <feature-id> <path>
#   ./scripts/state-manager.sh set-commit <feature-id> <sha>
#   ./scripts/state-manager.sh set-consultant <consultant>
#   ./scripts/state-manager.sh increment consecutive_failures
#   ./scripts/state-manager.sh reset-failures
#   ./scripts/state-manager.sh reset-in-progress   # reset interrupted features to queued
#   ./scripts/state-manager.sh pending-count       # count queued+in_progress features
#   ./scripts/state-manager.sh append-codex <feature-id> "<question>" "<answer>"
#
# All writes use Python (read → modify → write) — no /tmp files needed.

set -euo pipefail

STATE_FILE="${AUTOPILOT_STATE:-autopilot-state.json}"
COMMAND="${1:-}"
shift || true

require_state() {
  if [[ ! -f "$STATE_FILE" ]]; then
    echo "Error: $STATE_FILE not found. Run 'init' first." >&2
    exit 1
  fi
}

case "$COMMAND" in
  init)
    PRD_PATH="$1"
    BRANCH="$2"
    FEATURES_JSON="$3"
    TOTAL=$(echo "$FEATURES_JSON" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))")
    python3 - "$PRD_PATH" "$BRANCH" "$FEATURES_JSON" "$TOTAL" "$STATE_FILE" <<'PYEOF'
import sys, json
from datetime import datetime, timezone

prd_path, branch, features_json_str, total, state_file = sys.argv[1:]
features = json.loads(features_json_str)

state = {
    "prd_path": prd_path,
    "started_at": datetime.now(timezone.utc).isoformat(),
    "branch": branch,
    "features": features,
    "circuit_breaker": {
        "consecutive_failures": 0,
        "max_before_pause": 3
    },
    "stats": {
        "features_done": 0,
        "features_failed": 0,
        "features_total": int(total),
        "total_codex_consultations": 0
    }
}

with open(state_file, 'w') as f:
    json.dump(state, f, indent=2)
print(f"Initialized {state_file} with {total} features.")
PYEOF
    ;;

  get)
    require_state
    KEY="$1"
    python3 -c "
import json, sys
with open('$STATE_FILE') as f:
    state = json.load(f)
keys = '$KEY'.split('.')
val = state
for k in keys:
    val = val[k]
print(json.dumps(val, indent=2) if isinstance(val, (dict,list)) else val)
"
    ;;

  set-feature-status)
    require_state
    FEATURE_ID="$1"
    STATUS="$2"
    python3 - "$STATE_FILE" "$FEATURE_ID" "$STATUS" <<'PYEOF'
import sys, json
from datetime import datetime, timezone

state_file, feature_id, status = sys.argv[1:]
with open(state_file) as f:
    state = json.load(f)

for feat in state["features"]:
    if feat["id"] == feature_id:
        feat["status"] = status
        if status == "in_progress":
            feat["attempts"] = feat.get("attempts", 0) + 1
        break

if status == "done":
    state["stats"]["features_done"] += 1
elif status == "failed":
    state["stats"]["features_failed"] += 1

with open(state_file, 'w') as f:
    json.dump(state, f, indent=2)
print(f"Feature {feature_id} → {status}")
PYEOF
    ;;

  set-commit)
    require_state
    FEATURE_ID="$1"
    SHA="$2"
    python3 - "$STATE_FILE" "$FEATURE_ID" "$SHA" <<'PYEOF'
import sys, json
state_file, feature_id, sha = sys.argv[1:]
with open(state_file) as f:
    state = json.load(f)
for feat in state["features"]:
    if feat["id"] == feature_id:
        feat["commit_sha"] = sha
        break
with open(state_file, 'w') as f:
    json.dump(state, f, indent=2)
PYEOF
    ;;

  increment)
    require_state
    FIELD="$1"
    if [[ "$FIELD" == "consecutive_failures" ]]; then
      python3 - "$STATE_FILE" <<'PYEOF'
import sys, json
state_file = sys.argv[1]
with open(state_file) as f:
    state = json.load(f)
state["circuit_breaker"]["consecutive_failures"] += 1
val = state["circuit_breaker"]["consecutive_failures"]
with open(state_file, 'w') as f:
    json.dump(state, f, indent=2)
print(f"consecutive_failures = {val}")
PYEOF
    fi
    ;;

  set-consultant)
    require_state
    CONSULTANT="$1"
    python3 - "$STATE_FILE" "$CONSULTANT" <<'PYEOF'
import sys, json
state_file, consultant = sys.argv[1:]
with open(state_file) as f:
    state = json.load(f)
state["consultant"] = consultant
with open(state_file, 'w') as f:
    json.dump(state, f, indent=2)
print(f"Consultant set to: {consultant}")
PYEOF
    ;;

  set-current-feature)
    require_state
    FEATURE_ID="$1"
    python3 - "$STATE_FILE" "$FEATURE_ID" <<'PYEOF'
import sys, json
state_file, feature_id = sys.argv[1:]
with open(state_file) as f:
    state = json.load(f)
state["current_feature"] = feature_id
with open(state_file, 'w') as f:
    json.dump(state, f, indent=2)
print(f"Current feature → {feature_id}")
PYEOF
    ;;

  set-plan-path)
    require_state
    FEATURE_ID="$1"
    PLAN_PATH="$2"
    python3 - "$STATE_FILE" "$FEATURE_ID" "$PLAN_PATH" <<'PYEOF'
import sys, json
state_file, feature_id, plan_path = sys.argv[1:]
with open(state_file) as f:
    state = json.load(f)
for feat in state["features"]:
    if feat["id"] == feature_id:
        feat["plan_path"] = plan_path
        break
with open(state_file, 'w') as f:
    json.dump(state, f, indent=2)
print(f"Plan path for {feature_id} → {plan_path}")
PYEOF
    ;;

  reset-in-progress)
    require_state
    python3 - "$STATE_FILE" <<'PYEOF'
import sys, json
state_file = sys.argv[1]
with open(state_file) as f:
    state = json.load(f)
reset = []
for feat in state["features"]:
    if feat.get("status") == "in_progress":
        feat["status"] = "queued"
        reset.append(feat["id"])
with open(state_file, 'w') as f:
    json.dump(state, f, indent=2)
if reset:
    print(f"Reset to queued: {', '.join(reset)}")
else:
    print("No in_progress features found.")
PYEOF
    ;;

  pending-count)
    require_state
    python3 - "$STATE_FILE" <<'PYEOF'
import sys, json
state_file = sys.argv[1]
with open(state_file) as f:
    state = json.load(f)
count = sum(1 for f in state["features"] if f.get("status") in ("queued", "in_progress"))
print(count)
PYEOF
    ;;

  reset-failures)
    require_state
    python3 - "$STATE_FILE" <<'PYEOF'
import sys, json
state_file = sys.argv[1]
with open(state_file) as f:
    state = json.load(f)
state["circuit_breaker"]["consecutive_failures"] = 0
with open(state_file, 'w') as f:
    json.dump(state, f, indent=2)
print("consecutive_failures reset to 0")
PYEOF
    ;;

  append-codex)
    require_state
    FEATURE_ID="$1"
    QUESTION="$2"
    ANSWER="$3"
    python3 - "$STATE_FILE" "$FEATURE_ID" "$QUESTION" "$ANSWER" <<'PYEOF'
import sys, json
from datetime import datetime, timezone

state_file, feature_id, question, answer = sys.argv[1:]
with open(state_file) as f:
    state = json.load(f)

entry = {
    "question": question,
    "answer": answer,
    "timestamp": datetime.now(timezone.utc).isoformat()
}

for feat in state["features"]:
    if feat["id"] == feature_id:
        feat.setdefault("codex_consultations", []).append(entry)
        break

state["stats"]["total_codex_consultations"] += 1

with open(state_file, 'w') as f:
    json.dump(state, f, indent=2)
print(f"Logged Codex consultation for {feature_id}")
PYEOF
    ;;

  *)
    echo "Unknown command: $COMMAND"
    echo "Usage: state-manager.sh {init|get|set-current-feature|set-feature-status|set-plan-path|set-commit|set-consultant|increment|reset-failures|append-codex}"
    exit 1
    ;;
esac
