#!/usr/bin/env bash
# autopilot-mode.sh — One-time setup for superpowers-autopilot
#
# Usage:
#   ./scripts/autopilot-mode.sh           # Install hook (run once after cloning)
#   ./scripts/autopilot-mode.sh --uninstall  # Remove hook and clean up
#
# What it does:
#   - Copies autopilot-guard.sh to .claude/hooks/
#   - Registers a PreToolUse hook in .claude/settings.json
#
# The guard activates/deactivates automatically during each run:
#   Phase 0: touch .claude/autopilot-active  → guard ON
#   Phase 5: rm .claude/autopilot-active     → guard OFF
#
# Blocked skills (only during active autopilot run):
#   superpowers:brainstorming, superpowers:finishing-a-development-branch,
#   superpowers:executing-plans, superpowers:using-git-worktrees

set -euo pipefail

HOOKS_DIR=".claude/hooks"
SETTINGS_FILE=".claude/settings.json"
GUARD_DEST="$HOOKS_DIR/autopilot-guard.sh"
SKILL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GUARD_SRC="$SKILL_ROOT/scripts/autopilot-guard.sh"

if [[ ! -d ".git" ]]; then
  echo "Error: run this from the project root (where .git/ is)" >&2
  exit 1
fi

install_hook() {
  mkdir -p "$HOOKS_DIR"

  cp "$GUARD_SRC" "$GUARD_DEST"
  chmod +x "$GUARD_DEST"

  # Register PreToolUse hook in settings.json
  if [[ -f "$SETTINGS_FILE" ]]; then
    if python3 -c "
import json
with open('$SETTINGS_FILE') as f:
    d = json.load(f)
hooks = d.get('hooks', {}).get('PreToolUse', [])
already = any(
    any(h.get('command', '').endswith('autopilot-guard.sh') for h in entry.get('hooks', []))
    for entry in hooks
)
exit(0 if already else 1)
" 2>/dev/null; then
      echo "ℹ Hook already registered in $SETTINGS_FILE"
      return
    fi

    python3 -c "
import json
with open('$SETTINGS_FILE') as f:
    d = json.load(f)
d.setdefault('hooks', {}).setdefault('PreToolUse', []).append({
    'matcher': 'Skill',
    'hooks': [{'type': 'command', 'command': '$GUARD_DEST'}]
})
with open('$SETTINGS_FILE', 'w') as f:
    json.dump(d, f, indent=2)
"
  else
    mkdir -p ".claude"
    python3 -c "
import json
d = {
    'hooks': {
        'PreToolUse': [{
            'matcher': 'Skill',
            'hooks': [{'type': 'command', 'command': '$GUARD_DEST'}]
        }]
    }
}
with open('$SETTINGS_FILE', 'w') as f:
    json.dump(d, f, indent=2)
"
  fi

  echo "✔ autopilot-mode installed"
  echo "  Guard script: $GUARD_DEST"
  echo "  Hook registered in: $SETTINGS_FILE"
  echo ""
  echo "  Blocked during autopilot runs (guard is OFF until /superpowers-autopilot runs):"
  echo "    • superpowers:brainstorming"
  echo "    • superpowers:finishing-a-development-branch"
  echo "    • superpowers:executing-plans"
  echo "    • superpowers:using-git-worktrees"
  echo ""
  echo "  ⚠ Restart Claude/Copilot once so the hook registration takes effect."
  echo "  After that, the guard activates/deactivates automatically — no more restarts needed."
}

uninstall_hook() {
  rm -f "$GUARD_DEST"
  rm -f ".claude/autopilot-active"

  if [[ -f "$SETTINGS_FILE" ]]; then
    python3 -c "
import json
with open('$SETTINGS_FILE') as f:
    d = json.load(f)
hooks = d.get('hooks', {}).get('PreToolUse', [])
d['hooks']['PreToolUse'] = [
    entry for entry in hooks
    if not any(h.get('command', '').endswith('autopilot-guard.sh') for h in entry.get('hooks', []))
]
if not d['hooks']['PreToolUse']:
    del d['hooks']['PreToolUse']
if not d['hooks']:
    del d['hooks']
with open('$SETTINGS_FILE', 'w') as f:
    json.dump(d, f, indent=2)
" 2>/dev/null
  fi

  echo "✔ autopilot-mode uninstalled"
  echo "  All Superpowers skills restored."
}

case "${1:-install}" in
  --uninstall) uninstall_hook ;;
  install|*)   install_hook ;;
esac
