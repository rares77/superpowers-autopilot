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
# shellcheck source=./lib/cli-paths.sh
source "$SCRIPT_DIR/lib/cli-paths.sh"

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

CODEX_CONSULT_PROMPT="You are an external consultant for a separate orchestrator.
Answer the QUESTION directly and concisely.
Do not inspect repository files.
Do not invoke skills.
Do not run shell commands or tools unless absolutely required.
Do not propose workflows, planning rituals, or process advice.
If options are provided, choose one explicitly and justify it briefly."

GEMINI_PRIMARY_MODEL="${AUTOPILOT_GEMINI_PRIMARY_MODEL:-gemini-3-pro-preview}"
GEMINI_FALLBACK_MODEL="${AUTOPILOT_GEMINI_FALLBACK_MODEL:-gemini-2.5-pro}"

run_codex_consult() {
  local codex_bin="$1"
  local temp_dir=""
  local output_file=""
  local stdout_file=""
  local stderr_file=""
  local status=0
  local prompt=""

  temp_dir="$(mktemp -d)"
  output_file="$temp_dir/final.txt"
  stdout_file="$temp_dir/stdout.txt"
  stderr_file="$temp_dir/stderr.txt"
  prompt="$CODEX_CONSULT_PROMPT

$FULL_PROMPT"

  set +e
  printf '%s\n' "$prompt" | OTEL_SDK_DISABLED=true run_with_timeout "$TIMEOUT" "$codex_bin" exec - \
    --skip-git-repo-check \
    -C "$temp_dir" \
    --ephemeral \
    -o "$output_file" \
    --sandbox read-only \
    >"$stdout_file" 2>"$stderr_file"
  status=$?
  set -e

  if [[ $status -ne 0 ]]; then
    [[ -s "$stderr_file" ]] && cat "$stderr_file" >&2
    [[ -s "$stdout_file" ]] && cat "$stdout_file" >&2
    rm -rf "$temp_dir"
    exit 2
  fi

  if [[ ! -f "$output_file" ]]; then
    [[ -s "$stderr_file" ]] && cat "$stderr_file" >&2
    [[ -s "$stdout_file" ]] && cat "$stdout_file" >&2
    rm -rf "$temp_dir"
    exit 2
  fi

  cat "$output_file"
  rm -rf "$temp_dir"
}

run_gemini_consult() {
  local gemini_bin="$1"
  local temp_dir=""
  local stdout_file=""
  local stderr_file=""
  local status=0
  local model=""

  temp_dir="$(mktemp -d)"
  stdout_file="$temp_dir/stdout.txt"
  stderr_file="$temp_dir/stderr.txt"

  run_gemini_attempt() {
    model="$1"
    : >"$stdout_file"
    : >"$stderr_file"

    set +e
    run_with_timeout "$TIMEOUT" "$gemini_bin" --model "$model" -p "$FULL_PROMPT" --approval-mode plan \
      >"$stdout_file" 2>"$stderr_file"
    status=$?
    set -e

    return "$status"
  }

  if run_gemini_attempt "$GEMINI_PRIMARY_MODEL"; then
    cat "$stdout_file"
    rm -rf "$temp_dir"
    return 0
  fi

  if [[ "$GEMINI_FALLBACK_MODEL" != "$GEMINI_PRIMARY_MODEL" ]] && grep -Eqi \
    'RESOURCE_EXHAUSTED|MODEL_CAPACITY_EXHAUSTED|rateLimitExceeded|No capacity available for model|429' "$stderr_file"; then
    if run_gemini_attempt "$GEMINI_FALLBACK_MODEL"; then
      cat "$stdout_file"
      rm -rf "$temp_dir"
      return 0
    fi
  fi

  [[ -s "$stderr_file" ]] && cat "$stderr_file" >&2
  [[ -s "$stdout_file" ]] && cat "$stdout_file" >&2
  rm -rf "$temp_dir"
  exit 2
}

case "$CONSULTANT" in
  claude:opus)
    claude_bin="$(resolve_cli claude || true)"
    if [[ -z "$claude_bin" ]]; then
      echo "Error: claude CLI not found." >&2; exit 2
    fi
    run_with_timeout "$TIMEOUT" "$claude_bin" -p --model claude-opus-4-6 -- "$FULL_PROMPT"
    ;;

  claude:sonnet)
    claude_bin="$(resolve_cli claude || true)"
    if [[ -z "$claude_bin" ]]; then
      echo "Error: claude CLI not found." >&2; exit 2
    fi
    run_with_timeout "$TIMEOUT" "$claude_bin" -p --model claude-sonnet-4-6 -- "$FULL_PROMPT"
    ;;

  codex)
    codex_bin="$(resolve_cli codex || true)"
    if [[ -z "$codex_bin" ]]; then
      echo "Error: codex CLI not found." >&2; exit 2
    fi
    run_codex_consult "$codex_bin"
    ;;

  gemini)
    gemini_bin="$(resolve_cli gemini || true)"
    if [[ -z "$gemini_bin" ]]; then
      echo "Error: gemini CLI not found." >&2; exit 2
    fi
    # Force a stable Pro model first, then fall back on provider-side capacity errors.
    run_gemini_consult "$gemini_bin"
    ;;

  copilot)
    copilot_bin="$(resolve_cli copilot || true)"
    if [[ -z "$copilot_bin" ]]; then
      echo "Error: copilot CLI not found." >&2; exit 2
    fi
    run_with_timeout "$TIMEOUT" "$copilot_bin" -p "$FULL_PROMPT" -s --no-ask-user
    ;;

  cursor)
    cursor_bin="$(resolve_cli cursor || true)"
    if [[ -z "$cursor_bin" ]] || ! "$cursor_bin" agent -h &>/dev/null; then
      echo "Error: Cursor Agent not found (need \`cursor\` with \`cursor agent\` subcommand)." >&2; exit 2
    fi
    # IDE binary is \`cursor\`; headless agent is \`cursor agent -p\`. ask mode = read-only Q&A.
    run_with_timeout "$TIMEOUT" "$cursor_bin" agent -p --mode ask -- "$FULL_PROMPT"
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
