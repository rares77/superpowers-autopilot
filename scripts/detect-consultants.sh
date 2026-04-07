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

available=("\"claude\"")  # always available — we're running inside Claude Code
unavailable=()

for cli in codex gemini; do
  if command -v "$cli" &>/dev/null; then
    available+=("\"$cli\"")
  else
    unavailable+=("\"$cli\"")
  fi
done

# Recommended priority: codex > gemini > claude
# (codex/gemini = different model = genuinely fresh perspective)
# claude = same model but isolated context, valid fallback
recommended="claude"
for preferred in codex gemini; do
  if command -v "$preferred" &>/dev/null; then
    recommended="$preferred"
    break
  fi
done

available_json=$(IFS=,; echo "[${available[*]:-}]")
unavailable_json=$(IFS=,; echo "[${unavailable[*]:-}]")

echo "{\"available\": $available_json, \"unavailable\": $unavailable_json, \"recommended\": \"$recommended\"}"
