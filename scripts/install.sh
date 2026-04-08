#!/usr/bin/env bash
# install.sh — Install the autopilot guard hook into the current project
#
# Recommended during project setup before the first skill invocation.
# The skill also invokes it as a fallback if the user skipped setup.
# Can be run manually:
#   ./scripts/install.sh            # Install
#   ./scripts/install.sh --uninstall  # Remove hook and clean up
#
# What it does:
#   - Copies autopilot-guard.sh to .claude/hooks/
#   - Registers a PreToolUse hook in .claude/settings.json
#
# Exit codes:
#   0 — already installed (no restart needed)
#   1 — just installed (Claude Code restart required)
#   2 — error

set -euo pipefail

HOOKS_DIR=".claude/hooks"
SETTINGS_FILE=".claude/settings.json"
GUARD_DEST="$HOOKS_DIR/autopilot-guard.sh"
SKILL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GUARD_SRC="$SKILL_ROOT/scripts/autopilot-guard.sh"

if [[ ! -d ".git" ]]; then
  echo "Error: run this from the project root (where .git/ is)" >&2
  exit 2
fi

is_installed() {
  [[ -f "$GUARD_DEST" ]] && python3 -c "
import json, sys
try:
    with open('$SETTINGS_FILE') as f:
        d = json.load(f)
    hooks = d.get('hooks', {}).get('PreToolUse', [])
    already = any(
        any(h.get('command', '').endswith('autopilot-guard.sh') for h in entry.get('hooks', []))
        for entry in hooks
    )
    sys.exit(0 if already else 1)
except Exception:
    sys.exit(1)
" 2>/dev/null
}

install_hook() {
  if is_installed; then
    echo "already-installed"
    exit 0
  fi

  mkdir -p "$HOOKS_DIR"
  cp "$GUARD_SRC" "$GUARD_DEST"
  chmod +x "$GUARD_DEST"

  if [[ -f "$SETTINGS_FILE" ]]; then
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

  echo "installed"
  exit 1  # caller should prompt for restart
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

  echo "✔ Guard hook uninstalled. All Superpowers skills restored."
}

case "${1:-install}" in
  --uninstall) uninstall_hook ;;
  install|*)   install_hook ;;
esac
