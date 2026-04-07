#!/usr/bin/env bash
# codex-consult.sh — Consult Codex CLI (or fallback) for a second opinion
# Usage: ./scripts/codex-consult.sh "<question>" "<context>"
# Output: Codex's answer to stdout, exit code 0 on success
#
# Consultant priority (configurable via AUTOPILOT_CONSULTANT env var):
#   1. codex -p    (OpenAI Codex CLI)
#   2. gemini -p   (Google Gemini CLI)
#   Falls back gracefully if neither is installed.

set -euo pipefail

QUESTION="${1:-}"
CONTEXT="${2:-}"
TIMEOUT="${AUTOPILOT_CONSULTANT_TIMEOUT:-120}"
CONSULTANT="${AUTOPILOT_CONSULTANT:-auto}"

if [[ -z "$QUESTION" ]]; then
  echo "Error: question required" >&2
  exit 1
fi

FULL_PROMPT="$QUESTION

Context:
$CONTEXT

Please give a concise, actionable answer. Focus on the specific decision or fix needed."

consult_codex() {
  echo "$FULL_PROMPT" | timeout "$TIMEOUT" codex -p --approval-mode full-auto 2>/dev/null
}

consult_gemini() {
  echo "$FULL_PROMPT" | timeout "$TIMEOUT" gemini -p 2>/dev/null
}

run_consultant() {
  local consultant="$1"
  case "$consultant" in
    codex)
      if command -v codex &>/dev/null; then
        consult_codex
        return 0
      fi
      return 1
      ;;
    gemini)
      if command -v gemini &>/dev/null; then
        consult_gemini
        return 0
      fi
      return 1
      ;;
  esac
}

# Auto-detect best available consultant
if [[ "$CONSULTANT" == "auto" ]]; then
  if command -v codex &>/dev/null; then
    CONSULTANT="codex"
  elif command -v gemini &>/dev/null; then
    CONSULTANT="gemini"
  else
    CONSULTANT="none"
  fi
fi

case "$CONSULTANT" in
  codex|gemini)
    if run_consultant "$CONSULTANT"; then
      exit 0
    else
      echo "Warning: $CONSULTANT not available or timed out." >&2
      exit 2
    fi
    ;;
  none)
    echo "No external consultant available (codex/gemini not installed)." >&2
    echo "Proceeding with Claude's own reasoning for: $QUESTION"
    exit 2
    ;;
  *)
    echo "Error: Unknown consultant '$CONSULTANT'. Set AUTOPILOT_CONSULTANT=codex|gemini|auto" >&2
    exit 1
    ;;
esac
