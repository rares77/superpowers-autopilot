#!/usr/bin/env bash
# autopilot.sh — single entrypoint for runtime automation commands
#
# Usage:
#   ./scripts/autopilot.sh detect-consultants
#   ./scripts/autopilot.sh state <subcommand> [...]
#   ./scripts/autopilot.sh consult "<question>" "<context>"
#   ./scripts/autopilot.sh build-context
#   ./scripts/autopilot.sh parse-prd <path>
#   ./scripts/autopilot.sh check-tests

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMAND="${1:-}"
shift || true

usage() {
  cat >&2 <<'EOF'
Usage:
  ./scripts/autopilot.sh detect-consultants
  ./scripts/autopilot.sh state <subcommand> [...]
  ./scripts/autopilot.sh consult "<question>" "<context>"
  ./scripts/autopilot.sh build-context
  ./scripts/autopilot.sh parse-prd <path>
  ./scripts/autopilot.sh check-tests
EOF
}

case "$COMMAND" in
  detect-consultants)
    exec "$SCRIPT_DIR/detect-consultants.sh" "$@"
    ;;
  state)
    exec "$SCRIPT_DIR/state-manager.sh" "$@"
    ;;
  consult)
    exec "$SCRIPT_DIR/consult.sh" "$@"
    ;;
  build-context)
    exec "$SCRIPT_DIR/build-context.sh" "$@"
    ;;
  parse-prd)
    exec "$SCRIPT_DIR/parse-prd.sh" "$@"
    ;;
  check-tests)
    exec "$SCRIPT_DIR/check-tests.sh" "$@"
    ;;
  ""|-h|--help|help)
    usage
    exit 0
    ;;
  *)
    usage
    exit 1
    ;;
esac
