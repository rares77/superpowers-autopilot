#!/usr/bin/env bash

# Common CLI resolution helpers for app environments whose PATH may not include
# shell-managed locations like ~/.local/bin or ~/.nvm/.../bin.

resolve_cli() {
  local name="$1"
  local candidate=""
  local nvm_match=""

  if command -v "$name" >/dev/null 2>&1; then
    command -v "$name"
    return 0
  fi

  for candidate in \
    "$HOME/.local/bin/$name" \
    "/opt/homebrew/bin/$name" \
    "/usr/local/bin/$name"
  do
    if [[ -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  shopt -s nullglob
  for candidate in "$HOME"/.nvm/versions/node/*/bin/"$name"; do
    nvm_match="$candidate"
  done
  shopt -u nullglob

  if [[ -n "$nvm_match" && -x "$nvm_match" ]]; then
    printf '%s\n' "$nvm_match"
    return 0
  fi

  return 1
}

cli_ok() {
  local resolved=""
  resolved=$(resolve_cli "$1") || return 1
  "$resolved" --version >/dev/null 2>&1
}

run_with_timeout() {
  local seconds="$1"
  shift

  if command -v timeout >/dev/null 2>&1; then
    timeout "$seconds" "$@"
  elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$seconds" "$@"
  else
    "$@"
  fi
}
