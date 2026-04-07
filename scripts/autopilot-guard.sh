#!/usr/bin/env bash
# autopilot-guard.sh — PreToolUse hook for superpowers-autopilot
#
# Blocks Superpowers interactive skills during an active autopilot run.
# Activated by Phase 0 (touch .claude/autopilot-active)
# Deactivated by Phase 5 (rm .claude/autopilot-active)
#
# Exit codes: 0 = allow, 2 = deny

set -euo pipefail

# Only active when autopilot is running
if [[ ! -f ".claude/autopilot-active" ]]; then
  exit 0
fi

# Read tool info from stdin (Claude Code passes JSON)
INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | python3 -c "
import json, sys
d = json.load(sys.stdin)
print(d.get('tool_name', ''))
" 2>/dev/null || echo "")

# Only intercept Skill tool calls
if [[ "$TOOL_NAME" != "Skill" ]]; then
  exit 0
fi

SKILL_NAME=$(echo "$INPUT" | python3 -c "
import json, sys
d = json.load(sys.stdin)
print(d.get('tool_input', {}).get('skill', ''))
" 2>/dev/null || echo "")

# Skills blocked during autonomous autopilot operation
# These have hard user-approval gates incompatible with automation
BLOCKED_SKILLS=(
  "superpowers:brainstorming"
  "brainstorming"
  "superpowers:finishing-a-development-branch"
  "finishing-a-development-branch"
  "superpowers:executing-plans"
  "executing-plans"
  "superpowers:using-git-worktrees"
  "using-git-worktrees"
)

for blocked in "${BLOCKED_SKILLS[@]}"; do
  if [[ "$SKILL_NAME" == "$blocked" ]]; then
    echo "🚫 Autopilot guard: '$SKILL_NAME' is blocked during autonomous operation." >&2
    echo "   Autopilot handles this internally. Deactivate guard to use it manually." >&2
    exit 2
  fi
done

exit 0
