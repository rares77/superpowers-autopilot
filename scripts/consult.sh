#!/usr/bin/env bash
# consult.sh — Get a second opinion from an external CLI model
# Usage: ./scripts/consult.sh "<question>" "<trigger context>"
# Output: Model's answer to stdout
# Exit codes: 0 = success, 2 = consultant unavailable/failed
#
# AUTOPILOT_CONSULTANT controls which consultant to use.
# Supported values:
#   claude:opus    — claude CLI with Opus model (recommended, reasoning upgrade)
#   claude:sonnet  — claude CLI with Sonnet model (same family as orchestrator)
#   codex          — OpenAI codex CLI
#   gemini         — Google gemini CLI
#   copilot        — copilot CLI (standalone)
#   cursor         — cursor CLI
#   self           — no external CLI; caller handles self-reasoning

set -euo pipefail

QUESTION="${1:-}"
TRIGGER_CONTEXT="${2:-}"
TIMEOUT="${AUTOPILOT_CONSULTANT_TIMEOUT:-120}"
CONSULTANT="${AUTOPILOT_CONSULTANT:-self}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -z "$QUESTION" ]]; then
  echo "Error: question required" >&2
  exit 1
fi

# Build project context (README + current feature + current plan)
PROJECT_CONTEXT=$("$SCRIPT_DIR/build-context.sh" 2>/dev/null || echo "(context unavailable)")

FULL_PROMPT="[PROJECT CONTEXT]
$PROJECT_CONTEXT

[TRIGGER CONTEXT]
$TRIGGER_CONTEXT

[QUESTION]
$QUESTION

Please give a concise, actionable answer. Focus on the specific decision or fix needed."

case "$CONSULTANT" in
  claude:opus)
    if ! command -v claude &>/dev/null; then
      echo "Error: claude CLI not found." >&2; exit 2
    fi
    echo "$FULL_PROMPT" | timeout "$TIMEOUT" claude -p --model claude-opus-4-6
    ;;

  claude:sonnet)
    if ! command -v claude &>/dev/null; then
      echo "Error: claude CLI not found." >&2; exit 2
    fi
    echo "$FULL_PROMPT" | timeout "$TIMEOUT" claude -p --model claude-sonnet-4-6
    ;;

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

  copilot)
    if ! command -v copilot &>/dev/null; then
      echo "Error: copilot CLI not found." >&2; exit 2
    fi
    echo "$FULL_PROMPT" | timeout "$TIMEOUT" copilot -p
    ;;

  cursor)
    if ! command -v cursor &>/dev/null; then
      echo "Error: cursor CLI not found." >&2; exit 2
    fi
    echo "$FULL_PROMPT" | timeout "$TIMEOUT" cursor -p
    ;;

  self)
    # No external consultant — caller (SKILL.md) handles self-reasoning inline.
    exit 2
    ;;

  *)
    echo "Error: Unknown consultant '$CONSULTANT'." >&2
    echo "Valid: claude:opus | claude:sonnet | codex | gemini | copilot | cursor | self" >&2
    exit 1
    ;;
esac
