#!/usr/bin/env bash
# autopilot.sh — single entrypoint for runtime automation commands
#
# Usage:
#   ./scripts/autopilot.sh detect-consultants
#   ./scripts/autopilot.sh state <subcommand> [...]
#   ./scripts/autopilot.sh consult "<question>" "<context>"
#   ./scripts/autopilot.sh build-context
#   ./scripts/autopilot.sh parse-prd <path>
#   ./scripts/autopilot.sh check-tests
#   ./scripts/autopilot.sh runtime-state
#   ./scripts/autopilot.sh current-branch
#   ./scripts/autopilot.sh guard-status
#   ./scripts/autopilot.sh resume-check
#   ./scripts/autopilot.sh verify-install
#   ./scripts/autopilot.sh startup-status
#   ./scripts/autopilot.sh start-run <prd-path> <consultant>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_ROOT="${AUTOPILOT_SKILL_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
COMMAND="${1:-}"
shift || true

usage() {
  cat >&2 <<'EOF'
Usage:
  ./scripts/autopilot.sh detect-consultants
  ./scripts/autopilot.sh state <subcommand> [...]
  ./scripts/autopilot.sh consult "<question>" "<context>"
  ./scripts/autopilot.sh build-context
  ./scripts/autopilot.sh parse-prd <path>
  ./scripts/autopilot.sh check-tests
  ./scripts/autopilot.sh runtime-state
  ./scripts/autopilot.sh current-branch
  ./scripts/autopilot.sh guard-status
  ./scripts/autopilot.sh resume-check
  ./scripts/autopilot.sh verify-install
  ./scripts/autopilot.sh startup-status
  ./scripts/autopilot.sh start-run <prd-path> <consultant>
EOF
}

runtime_state() {
  if [[ -f ".claude/autopilot-state.json" ]]; then
    cat ".claude/autopilot-state.json"
  else
    echo "not initialized — fresh run"
  fi
}

current_branch() {
  local branch=""
  branch=$(git branch --show-current 2>/dev/null || true)
  if [[ -n "$branch" ]]; then
    echo "$branch"
  else
    echo "unknown"
  fi
}

guard_status() {
  if [[ -f ".claude/autopilot-active" ]]; then
    echo "ACTIVE — interactive skills blocked"
  else
    echo "INACTIVE — will activate in Phase 0"
  fi
}

resume_check() {
  if [[ -f "autopilot-state.json" && ! -f ".claude/autopilot-state.json" ]]; then
    mkdir -p ".claude"
    mv "autopilot-state.json" ".claude/autopilot-state.json"
  fi

  if [[ -f ".claude/autopilot-state.json" ]]; then
    exec "$SCRIPT_DIR/state-manager.sh" pending-count
  else
    echo "0"
  fi
}

hook_installed() {
  local settings_file=".claude/settings.json"
  local guard_dest=".claude/hooks/autopilot-guard.sh"

  [[ -f "$guard_dest" ]] || return 1
  [[ -f "$settings_file" ]] || return 1

  python3 - "$settings_file" <<'PYEOF'
import json
import sys

with open(sys.argv[1]) as f:
    data = json.load(f)

hooks = data.get("hooks", {}).get("PreToolUse", [])
for entry in hooks:
    for hook in entry.get("hooks", []):
        if hook.get("command", "").endswith("autopilot-guard.sh"):
            sys.exit(0)
sys.exit(1)
PYEOF
}

verify_install() {
  if hook_installed; then
    echo "already-installed"
    exit 0
  fi

  exec "$SKILL_ROOT/scripts/install.sh"
}

startup_status() {
  local pending_count="0"
  local install_status=""
  local consultants_json=""

  pending_count="$(resume_check)"
  if [[ "$pending_count" != "0" ]]; then
    python3 - "$pending_count" <<'PYEOF'
import json
import sys

pending_count = int(sys.argv[1])
print(json.dumps({
    "mode": "resume",
    "pending_count": pending_count,
}))
PYEOF
    return 0
  fi

  if hook_installed; then
    install_status="already-installed"
  else
    install_status="$("$SKILL_ROOT/scripts/install.sh")"
  fi

  if [[ "$install_status" == "installed" ]]; then
    python3 <<'PYEOF'
import json

print(json.dumps({
    "mode": "fresh",
    "pending_count": 0,
    "install_status": "installed",
    "restart_required": True,
}))
PYEOF
    return 0
  fi

  consultants_json="$("$SCRIPT_DIR/detect-consultants.sh")"
  python3 - "$consultants_json" <<'PYEOF'
import json
import sys

consultants = json.loads(sys.argv[1])
print(json.dumps({
    "mode": "fresh",
    "pending_count": 0,
    "install_status": "already-installed",
    "restart_required": False,
    "consultants": consultants,
}))
PYEOF
}

next_branch_name() {
  local base="autopilot/$(date +%Y%m%d)"
  local candidate="$base"
  local suffix=2

  while git show-ref --verify --quiet "refs/heads/$candidate"; do
    candidate="${base}-${suffix}"
    suffix=$((suffix + 1))
  done

  printf '%s\n' "$candidate"
}

start_run() {
  local prd_path="${1:-}"
  local consultant="${2:-}"
  local branch=""

  if [[ -z "$prd_path" || -z "$consultant" ]]; then
    echo "Usage: ./scripts/autopilot.sh start-run <prd-path> <consultant>" >&2
    exit 1
  fi

  branch="$(next_branch_name)"
  "$SCRIPT_DIR/state-manager.sh" init "$prd_path" "$branch" >/dev/null
  "$SCRIPT_DIR/state-manager.sh" set-consultant "$consultant" >/dev/null
  git checkout -b "$branch" >/dev/null 2>&1
  mkdir -p ".claude"
  touch ".claude/autopilot-active"

  python3 - ".claude/autopilot-state.json" "$consultant" "$branch" <<'PYEOF'
import json
import sys

state_file, consultant, branch = sys.argv[1:]
with open(state_file) as f:
    state = json.load(f)

queue = [{"id": feat["id"], "name": feat["name"]} for feat in state["features"]]
print(json.dumps({
    "branch": branch,
    "consultant": consultant,
    "queued_features": queue,
}))
PYEOF
}

case "$COMMAND" in
  detect-consultants)
    exec "$SCRIPT_DIR/detect-consultants.sh" "$@"
    ;;
  state)
    exec "$SCRIPT_DIR/state-manager.sh" "$@"
    ;;
  consult)
    exec "$SCRIPT_DIR/consult.sh" "$@"
    ;;
  build-context)
    exec "$SCRIPT_DIR/build-context.sh" "$@"
    ;;
  parse-prd)
    exec "$SCRIPT_DIR/parse-prd.sh" "$@"
    ;;
  check-tests)
    exec "$SCRIPT_DIR/check-tests.sh" "$@"
    ;;
  runtime-state)
    runtime_state
    ;;
  current-branch)
    current_branch
    ;;
  guard-status)
    guard_status
    ;;
  resume-check)
    resume_check
    ;;
  verify-install)
    verify_install
    ;;
  startup-status)
    startup_status
    ;;
  start-run)
    start_run "$@"
    ;;
  ""|-h|--help|help)
    usage
    exit 0
    ;;
  *)
    usage
    exit 1
    ;;
esac
