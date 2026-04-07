#!/usr/bin/env bash
# codex-consult.sh — Get a "second opinion" from an external CLI model
# Usage: ./scripts/codex-consult.sh "<question>" "<context>"
# Output: Model's answer to stdout
# Exit codes: 0 = success, 2 = consultant unavailable/failed
#
# Consultant is read from AUTOPILOT_CONSULTANT env var (set in autopilot-state.json).
# Supported values: codex | gemini | claude | none

set -euo pipefail

QUESTION="${1:-}"
CONTEXT="${2:-}"
TIMEOUT="${AUTOPILOT_CONSULTANT_TIMEOUT:-120}"
CONSULTANT="${AUTOPILOT_CONSULTANT:-none}"

if [[ -z "$QUESTION" ]]; then
  echo "Error: question required" >&2
  exit 1
fi

FULL_PROMPT="$QUESTION

Context:
$CONTEXT

Please give a concise, actionable answer. Focus on the specific decision or fix needed."

case "$CONSULTANT" in
  codex)
    if ! command -v codex &>/dev/null; then
      echo "Error: codex CLI not found." >&2; exit 2
    fi
    echo "$FULL_PROMPT" | timeout "$TIMEOUT" codex -p --approval-mode full-auto
    ;;

  gemini)
    if ! command -v gemini &>/dev/null; then
      echo "Error: gemini CLI not found." >&2; exit 2
    fi
    echo "$FULL_PROMPT" | timeout "$TIMEOUT" gemini -p
    ;;

  claude)
    if ! command -v claude &>/dev/null; then
      echo "Error: claude CLI not found." >&2; exit 2
    fi
    # Use Opus for second opinions — more capable than the orchestrating model,
    # giving a genuine upgrade in reasoning, not just an isolated context.
    echo "$FULL_PROMPT" | timeout "$TIMEOUT" claude -p --model claude-opus-4-6
    ;;

  none)
    echo "No external consultant configured. Claude will reason independently." >&2
    exit 2
    ;;

  *)
    echo "Error: Unknown consultant '$CONSULTANT'. Valid: codex | gemini | claude | none" >&2
    exit 1
    ;;
esac
