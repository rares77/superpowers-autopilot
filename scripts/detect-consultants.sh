#!/usr/bin/env bash
# detect-consultants.sh — Detect which second-opinion consultants are available
# Usage: ./scripts/detect-consultants.sh
#
# Output: JSON with available consultants and recommended default.
# Each entry in "available" is a consultant ID usable by consult.sh.
#
# Two levels:
#   Level 1 — External CLI (isolated subprocess, real second opinion)
#             claude:opus, claude:sonnet, codex, gemini, copilot, cursor
#   Level 2 — Self-reasoning (same model, same session, no CLI needed)
#             Used automatically when no external CLI is found.
#
# Example output (external CLI found):
# {
#   "available": ["claude:opus", "claude:sonnet", "codex"],
#   "unavailable": ["gemini", "copilot", "cursor"],
#   "recommended": "claude:opus",
#   "self_reasoning_only": false
# }
#
# Example output (nothing found):
# {
#   "available": [],
#   "unavailable": ["claude", "codex", "gemini", "copilot", "cursor"],
#   "recommended": "self",
#   "self_reasoning_only": true
# }

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib/cli-paths.sh
source "$SCRIPT_DIR/lib/cli-paths.sh"

available=()
unavailable=()
recommended=""

# claude CLI — if available, offer both Opus (upgrade) and Sonnet (same family)
if cli_ok claude; then
  available+=("\"claude:opus\"")   # Opus = genuine reasoning upgrade
  available+=("\"claude:sonnet\"") # Sonnet = same model family as orchestrator
else
  unavailable+=("\"claude\"")
fi

# codex (OpenAI)
if cli_ok codex; then
  available+=("\"codex\"")
else
  unavailable+=("\"codex\"")
fi

# gemini (Google)
if cli_ok gemini; then
  available+=("\"gemini\"")
else
  unavailable+=("\"gemini\"")
fi

# copilot — standalone CLI (not gh copilot)
if cli_ok copilot; then
  available+=("\"copilot\"")
else
  unavailable+=("\"copilot\"")
fi

# Cursor Agent — requires `cursor agent` (headless); plain `cursor` is the IDE launcher
cursor_bin="$(resolve_cli cursor || true)"
if [[ -n "$cursor_bin" ]] && "$cursor_bin" agent -h &>/dev/null; then
  available+=("\"cursor\"")
else
  unavailable+=("\"cursor\"")
fi

# Pick recommended: prefer claude:opus, else first available, else self
if [[ " ${available[*]:-} " == *'"claude:opus"'* ]]; then
  recommended="claude:opus"
elif [[ ${#available[@]} -gt 0 ]]; then
  # strip quotes from first entry
  recommended=$(echo "${available[0]}" | tr -d '"')
else
  recommended="self"
fi

self_reasoning_only="false"
if [[ ${#available[@]} -eq 0 ]]; then
  self_reasoning_only="true"
fi

available_json=$(IFS=,; echo "[${available[*]:-}]")
unavailable_json=$(IFS=,; echo "[${unavailable[*]:-}]")

echo "{\"available\": $available_json, \"unavailable\": $unavailable_json, \"recommended\": \"$recommended\", \"self_reasoning_only\": $self_reasoning_only}"
