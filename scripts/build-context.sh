#!/usr/bin/env bash
# build-context.sh — Assemble project context for consultant consultations
# Usage: ./scripts/build-context.sh
# Output: formatted context block to stdout
#
# Collects:
#   1. Project description (README, first 60 lines)
#   2. Current feature spec from .claude/autopilot-state.json
#   3. Current plan content (if plan_path is set in state)

set -euo pipefail

STATE_FILE=".claude/autopilot-state.json"

python_state() {
  python3 - "$@" <<'PYEOF'
import json
import sys

mode = sys.argv[1]
state_file = sys.argv[2]

with open(state_file) as f:
    state = json.load(f)

if mode == "current-feature":
    current_id = state.get("current_feature")
    if not current_id:
        print("(no current feature in state)")
        sys.exit(0)

    feature = next((feat for feat in state.get("features", []) if feat.get("id") == current_id), None)
    if feature is None:
        print("(could not read feature from state)")
        sys.exit(0)

    print(f"ID: {feature.get('id', '')}")
    print(f"Name: {feature.get('name', '')}")
    print(f"Status: {feature.get('status', '')}")
    print(f"Attempts: {feature.get('attempts', 0)}")
    print("")
    print("Spec:")
    print(feature.get("spec") or feature.get("body") or "(no spec)")
    print("")
    print("Acceptance criteria:")
    for item in feature.get("acceptance_criteria", []):
        print(f"  - {item}")
elif mode == "plan-path":
    current_id = state.get("current_feature")
    if not current_id:
        sys.exit(0)

    feature = next((feat for feat in state.get("features", []) if feat.get("id") == current_id), None)
    if feature is None:
        sys.exit(0)

    print(feature.get("plan_path") or "")
PYEOF
}

# ── 1. Project description ──────────────────────────────────────────────────
echo "=== PROJECT ==="

# Try README variants in order of preference
readme=""
for f in README.md README.rst README.txt readme.md; do
  if [[ -f "$f" ]]; then
    readme="$f"
    break
  fi
done

if [[ -n "$readme" ]]; then
  echo "Source: $readme"
  head -60 "$readme"
else
  # Fallback: package.json description
  if [[ -f "package.json" ]]; then
    desc=$(python3 - <<'PYEOF'
import json
try:
    with open("package.json") as f:
        data = json.load(f)
    print(data.get("description", ""))
except Exception:
    print("")
PYEOF
)
    name=$(python3 - <<'PYEOF'
import json
try:
    with open("package.json") as f:
        data = json.load(f)
    print(data.get("name", ""))
except Exception:
    print("")
PYEOF
)
    [[ -n "$name" ]] && echo "Project: $name"
    [[ -n "$desc" ]] && echo "Description: $desc"
  # Fallback: pyproject.toml
  elif [[ -f "pyproject.toml" ]]; then
    grep -E '^(name|description)\s*=' pyproject.toml 2>/dev/null || true
  else
    echo "(no project description found)"
  fi
fi

echo ""

# ── 2. Current feature ──────────────────────────────────────────────────────
echo "=== CURRENT FEATURE ==="

if [[ ! -f "$STATE_FILE" ]]; then
  echo "(.claude/autopilot-state.json not found)"
else
  python_state current-feature "$STATE_FILE" 2>/dev/null || echo "(could not read feature from state)"
fi

echo ""

# ── 3. Current plan ─────────────────────────────────────────────────────────
echo "=== CURRENT PLAN ==="

if [[ -f "$STATE_FILE" ]]; then
  plan_path=$(python_state plan-path "$STATE_FILE" 2>/dev/null || true)

  if [[ -n "$plan_path" && -f "$plan_path" ]]; then
    echo "Source: $plan_path"
    cat "$plan_path"
  else
    echo "(no plan available yet)"
  fi
else
  echo "(no plan available yet)"
fi
