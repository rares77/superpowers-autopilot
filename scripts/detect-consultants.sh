#!/usr/bin/env bash
# detect-consultants.sh — Detect which second-opinion CLIs are available
# Usage: ./scripts/detect-consultants.sh
# Output: JSON object with available consultants and recommended default
#
# Example output:
# {
#   "available": ["codex", "claude"],
#   "unavailable": ["gemini"],
#   "recommended": "codex"
# }

set -euo pipefail

available=()
unavailable=()

for cli in codex gemini claude; do
  if command -v "$cli" &>/dev/null; then
    available+=("\"$cli\"")
  else
    unavailable+=("\"$cli\"")
  fi
done

# Recommended priority: codex > gemini > claude > none
# (codex/gemini = genuinely different model = better second opinion)
recommended="none"
for preferred in codex gemini claude; do
  if command -v "$preferred" &>/dev/null; then
    recommended="$preferred"
    break
  fi
done

available_json=$(IFS=,; echo "[${available[*]:-}]")
unavailable_json=$(IFS=,; echo "[${unavailable[*]:-}]")

echo "{\"available\": $available_json, \"unavailable\": $unavailable_json, \"recommended\": \"$recommended\"}"
