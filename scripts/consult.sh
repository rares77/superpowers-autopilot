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
#   codex          — OpenAI Codex CLI (`codex exec`, not `codex -p` — -p is --profile)
#   gemini         — Google Gemini CLI
#   copilot        — GitHub Copilot CLI (standalone)
#   cursor         — Cursor Agent CLI (`cursor agent -p`, not IDE `cursor`)
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
    timeout "$TIMEOUT" claude -p --model claude-opus-4-6 -- "$FULL_PROMPT"
    ;;

  claude:sonnet)
    if ! command -v claude &>/dev/null; then
      echo "Error: claude CLI not found." >&2; exit 2
    fi
    timeout "$TIMEOUT" claude -p --model claude-sonnet-4-6 -- "$FULL_PROMPT"
    ;;

  codex)
    if ! command -v codex &>/dev/null; then
      echo "Error: codex CLI not found." >&2; exit 2
    fi
    # Non-interactive: `codex exec` (prompt via stdin or `-`). Global `-p` is --profile, not print mode.
    echo "$FULL_PROMPT" | timeout "$TIMEOUT" codex exec - --full-auto
    ;;

  gemini)
    if ! command -v gemini &>/dev/null; then
      echo "Error: gemini CLI not found." >&2; exit 2
    fi
    # Headless: -p/--prompt; plan = read-only tools (fits advisory Q&A)
    timeout "$TIMEOUT" gemini -p "$FULL_PROMPT" --approval-mode plan
    ;;

  copilot)
    if ! command -v copilot &>/dev/null; then
      echo "Error: copilot CLI not found." >&2; exit 2
    fi
    timeout "$TIMEOUT" copilot -p "$FULL_PROMPT" -s --no-ask-user
    ;;

  cursor)
    if ! command -v cursor &>/dev/null || ! cursor agent -h &>/dev/null; then
      echo "Error: Cursor Agent not found (need \`cursor\` with \`cursor agent\` subcommand)." >&2; exit 2
    fi
    # IDE binary is \`cursor\`; headless agent is \`cursor agent -p\`. ask mode = read-only Q&A.
    timeout "$TIMEOUT" cursor agent -p --mode ask -- "$FULL_PROMPT"
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
