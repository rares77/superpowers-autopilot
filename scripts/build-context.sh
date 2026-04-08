#!/usr/bin/env bash
# build-context.sh — Assemble project context for consultant consultations
# Usage: ./scripts/build-context.sh
# Output: formatted context block to stdout
#
# Collects:
#   1. Project description (README, first 60 lines)
#   2. Current feature spec from .claude/autopilot-state.json
#   3. Current plan content (if plan_path is set in state)

set -euo pipefail

STATE_FILE=".claude/autopilot-state.json"

# ── 1. Project description ──────────────────────────────────────────────────
echo "=== PROJECT ==="

# Try README variants in order of preference
readme=""
for f in README.md README.rst README.txt readme.md; do
  if [[ -f "$f" ]]; then
    readme="$f"
    break
  fi
done

if [[ -n "$readme" ]]; then
  echo "Source: $readme"
  head -60 "$readme"
else
  # Fallback: package.json description
  if [[ -f "package.json" ]] && command -v jq &>/dev/null; then
    desc=$(jq -r '.description // empty' package.json 2>/dev/null || true)
    name=$(jq -r '.name // empty' package.json 2>/dev/null || true)
    [[ -n "$name" ]] && echo "Project: $name"
    [[ -n "$desc" ]] && echo "Description: $desc"
  # Fallback: pyproject.toml
  elif [[ -f "pyproject.toml" ]]; then
    grep -E '^(name|description)\s*=' pyproject.toml 2>/dev/null || true
  else
    echo "(no project description found)"
  fi
fi

echo ""

# ── 2. Current feature ──────────────────────────────────────────────────────
echo "=== CURRENT FEATURE ==="

if [[ ! -f "$STATE_FILE" ]]; then
  echo "(.claude/autopilot-state.json not found)"
else
  if ! command -v jq &>/dev/null; then
    echo "(jq not available — cannot parse state)"
  else
    current_id=$(jq -r '.current_feature // empty' "$STATE_FILE" 2>/dev/null || true)

    if [[ -z "$current_id" ]]; then
      echo "(no current feature in state)"
    else
      jq -r --arg id "$current_id" '
        .features[] | select(.id == $id) |
        "ID: \(.id)",
        "Name: \(.name)",
        "Status: \(.status)",
        "Attempts: \(.attempts // 0)",
        "",
        "Spec:",
        (.spec // "(no spec)"),
        "",
        "Acceptance criteria:",
        ((.acceptance_criteria // []) | .[] | "  - \(.)")
      ' "$STATE_FILE" 2>/dev/null || echo "(could not read feature from state)"
    fi
  fi
fi

echo ""

# ── 3. Current plan ─────────────────────────────────────────────────────────
echo "=== CURRENT PLAN ==="

if [[ -f "$STATE_FILE" ]] && command -v jq &>/dev/null; then
  current_id=$(jq -r '.current_feature // empty' "$STATE_FILE" 2>/dev/null || true)
  plan_path=""
  if [[ -n "$current_id" ]]; then
    plan_path=$(jq -r --arg id "$current_id" '
      .features[] | select(.id == $id) | .plan_path // empty
    ' "$STATE_FILE" 2>/dev/null || true)
  fi

  if [[ -n "$plan_path" && -f "$plan_path" ]]; then
    echo "Source: $plan_path"
    cat "$plan_path"
  else
    echo "(no plan available yet)"
  fi
else
  echo "(no plan available yet)"
fi
