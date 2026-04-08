#!/usr/bin/env bash
# check-tests.sh — Run the project's test suite and report pass/fail
# Usage: ./scripts/check-tests.sh [--snapshot | --compare]
#
# Modes:
#   (default)   Run tests, print result, exit 0 on pass / 1 on fail
#   --snapshot  Capture current test results to .autopilot-test-snapshot.json
#   --compare   Run tests and compare to snapshot; exit 2 if regression detected

set -euo pipefail

MODE="${1:-run}"
SNAPSHOT_FILE=".autopilot-test-snapshot.json"

# Auto-detect test runner
detect_test_runner() {
  if [[ -f "package.json" ]]; then
    if grep -q '"vitest"' package.json 2>/dev/null; then echo "vitest"
    elif grep -q '"jest"' package.json 2>/dev/null; then echo "jest"
    elif grep -q '"test"' package.json 2>/dev/null; then echo "npm"
    fi
  elif [[ -f "pyproject.toml" ]] || [[ -f "pytest.ini" ]]; then
    echo "pytest"
  elif [[ -f "Cargo.toml" ]]; then
    echo "cargo"
  elif [[ -f "go.mod" ]]; then
    echo "go"
  elif [[ -f "Makefile" ]] && grep -q "^test:" Makefile 2>/dev/null; then
    echo "make"
  else
    echo "unknown"
  fi
}

run_tests() {
  local runner
  runner=$(detect_test_runner)
  local output exit_code=0

  case "$runner" in
    vitest)  output=$(npx vitest run --reporter=json 2>&1) || exit_code=$? ;;
    jest)    output=$(npx jest --json 2>&1) || exit_code=$? ;;
    npm)     output=$(npm test 2>&1) || exit_code=$? ;;
    pytest)  output=$(python3 -m pytest --tb=short -q 2>&1) || exit_code=$? ;;
    cargo)   output=$(cargo test 2>&1) || exit_code=$? ;;
    go)      output=$(go test ./... 2>&1) || exit_code=$? ;;
    make)    output=$(make test 2>&1) || exit_code=$? ;;
    unknown)
      echo "Warning: Could not detect test runner. Set TEST_CMD env var." >&2
      if [[ -n "${TEST_CMD:-}" ]]; then
        output=$(eval "$TEST_CMD" 2>&1) || exit_code=$?
      else
        echo '{"passed": true, "runner": "unknown", "note": "no test runner detected"}'
        return 0
      fi
      ;;
  esac

  echo "$output"
  return $exit_code
}

capture_failing_tests() {
  local output="$1"
  # Extract failing test names (works for most runners)
  echo "$output" | grep -E '(FAIL|✗|×|ERROR|failed)' | head -20 || true
}

case "$MODE" in
  run|--run)
    echo "Running tests..."
    if output=$(run_tests 2>&1); then
      echo "✅ All tests passing"
      echo "$output" | tail -5
      exit 0
    else
      echo "❌ Tests failed:"
      capture_failing_tests "$output"
      exit 1
    fi
    ;;

  --snapshot)
    echo "Capturing test snapshot..."
    if output=$(run_tests 2>&1); then
      STATUS="passing"
    else
      STATUS="failing"
    fi
    FAILING=$(capture_failing_tests "$output" || echo "")
    python3 - "$SNAPSHOT_FILE" "$STATUS" "$FAILING" <<'PYEOF'
import sys, json
from datetime import datetime, timezone
snapshot_file, status, failing = sys.argv[1:]
snapshot = {
    "captured_at": datetime.now(timezone.utc).isoformat(),
    "status": status,
    "failing_tests": [l for l in failing.splitlines() if l.strip()]
}
with open(snapshot_file, 'w') as f:
    json.dump(snapshot, f, indent=2)
print(f"Snapshot saved to {snapshot_file} (status: {status})")
PYEOF
    ;;

  --compare)
    if [[ ! -f "$SNAPSHOT_FILE" ]]; then
      echo "No snapshot found. Run --snapshot first." >&2
      exit 1
    fi
    echo "Running tests and comparing to snapshot..."
    if output=$(run_tests 2>&1); then
      CURRENT_STATUS="passing"
    else
      CURRENT_STATUS="failing"
    fi
    CURRENT_FAILING=$(capture_failing_tests "$output" || echo "")

    python3 - "$SNAPSHOT_FILE" "$CURRENT_STATUS" "$CURRENT_FAILING" <<'PYEOF'
import sys, json
snapshot_file, current_status, current_failing_str = sys.argv[1:]

with open(snapshot_file) as f:
    snapshot = json.load(f)

prev_failing = set(snapshot.get("failing_tests", []))
curr_failing = set(l for l in current_failing_str.splitlines() if l.strip())

new_failures = curr_failing - prev_failing

if new_failures:
    print(f"🔴 REGRESSION DETECTED: {len(new_failures)} new test(s) failing:")
    for t in sorted(new_failures):
        print(f"  - {t}")
    sys.exit(2)
elif current_status == "failing" and snapshot["status"] == "failing":
    print("⚠️  Tests were already failing before this feature. No regression.")
    sys.exit(0)
else:
    print("✅ No regression detected.")
    sys.exit(0)
PYEOF
    ;;

  *)
    echo "Usage: check-tests.sh [--snapshot | --compare]"
    exit 1
    ;;
esac
