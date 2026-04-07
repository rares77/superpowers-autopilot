#!/usr/bin/env bash
# setup.sh — Configure project settings for superpowers-autopilot
# Usage: ./scripts/setup.sh [--uninstall]
#
# Adds a permission deny rule for superpowers:brainstorming to prevent it
# from hijacking the autopilot loop. Brainstorming can still be invoked
# manually with /brainstorming when not using autopilot.

set -euo pipefail

SETTINGS_DIR=".claude"
SETTINGS_FILE="$SETTINGS_DIR/settings.json"
DENY_RULE="Skill(superpowers:brainstorming *)"

# Check if we're in a git repo root
if [[ ! -d ".git" ]]; then
  echo "Error: run this from the project root (where .git/ is)" >&2
  exit 1
fi

# Uninstall mode
if [[ "${1:-}" == "--uninstall" ]]; then
  if [[ -f "$SETTINGS_FILE" ]]; then
    # Remove the deny rule using python/node if available, or sed
    if command -v python3 &>/dev/null; then
      python3 -c "
import json, sys
with open('$SETTINGS_FILE') as f:
    data = json.load(f)
deny = data.get('permissions', {}).get('deny', [])
if '$DENY_RULE' in deny:
    deny.remove('$DENY_RULE')
    if not deny:
        data.get('permissions', {}).pop('deny', None)
    if not data.get('permissions'):
        data.pop('permissions', None)
    with open('$SETTINGS_FILE', 'w') as f:
        json.dump(data, f, indent=2)
    print('✔ Removed brainstorming deny rule from $SETTINGS_FILE')
else:
    print('ℹ No deny rule found — nothing to remove')
"
    else
      echo "Error: python3 needed for uninstall. Manually remove '$DENY_RULE' from $SETTINGS_FILE" >&2
      exit 1
    fi
  else
    echo "ℹ No $SETTINGS_FILE found — nothing to uninstall"
  fi
  exit 0
fi

# Install mode
mkdir -p "$SETTINGS_DIR"

if [[ -f "$SETTINGS_FILE" ]]; then
  # File exists — check if rule already present
  if grep -q "superpowers:brainstorming" "$SETTINGS_FILE" 2>/dev/null; then
    echo "ℹ Brainstorming deny rule already configured in $SETTINGS_FILE"
    exit 0
  fi

  # Add deny rule to existing settings
  if command -v python3 &>/dev/null; then
    python3 -c "
import json
with open('$SETTINGS_FILE') as f:
    data = json.load(f)
data.setdefault('permissions', {}).setdefault('deny', []).append('$DENY_RULE')
with open('$SETTINGS_FILE', 'w') as f:
    json.dump(data, f, indent=2)
"
  else
    echo "Error: python3 needed to merge settings. Manually add '$DENY_RULE' to deny list in $SETTINGS_FILE" >&2
    exit 1
  fi
else
  # Create new settings file
  cat > "$SETTINGS_FILE" << 'SETTINGS'
{
  "permissions": {
    "deny": ["Skill(superpowers:brainstorming *)"]
  }
}
SETTINGS
fi

echo "✔ Configured $SETTINGS_FILE — brainstorming auto-trigger disabled"
echo "  Manual invocation with /brainstorming still works."
echo "  To undo: ./scripts/setup.sh --uninstall"
