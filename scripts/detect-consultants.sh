#!/usr/bin/env bash
# detect-consultants.sh — Detect which second-opinion CLIs are available
# Usage: ./scripts/detect-consultants.sh
# Output: JSON object with available consultants and recommended default
#
# Example output:
# {
#   "available": ["claude", "codex", "copilot"],
#   "unavailable": ["gemini", "cursor"],
#   "recommended": "claude"
# }

set -euo pipefail

available=("\"claude\"")  # always available — we're running inside Claude Code
unavailable=()

for cli in codex gemini cursor; do
  if command -v "$cli" &>/dev/null; then
    available+=("\"$cli\"")
  else
    unavailable+=("\"$cli\"")
  fi
done

# Check gh copilot (gh extension, not a standalone binary)
if command -v gh &>/dev/null && gh extension list 2>/dev/null | grep -q copilot; then
  available+=("\"copilot\"")
else
  unavailable+=("\"copilot\"")
fi

# Always recommend claude (Opus) as default — it's a more capable model
# than the orchestrating instance, giving a real reasoning upgrade.
# codex/gemini/copilot/cursor are alternatives if the user prefers a different model family.
recommended="claude"

available_json=$(IFS=,; echo "[${available[*]:-}]")
unavailable_json=$(IFS=,; echo "[${unavailable[*]:-}]")

echo "{\"available\": $available_json, \"unavailable\": $unavailable_json, \"recommended\": \"$recommended\"}"
