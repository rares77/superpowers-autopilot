#!/usr/bin/env bash
# parse-prd.sh — Extract features from a PRD.md file
# Usage: ./scripts/parse-prd.sh path/to/PRD.md
# Output: JSON array of features to stdout
#
# Supports:
#   Format A — Markdown headers (## Features / ### F1: Name)
#   Format B — YAML frontmatter with features[] array
#   Format C — Superpowers brainstorm output (## What We're Building)

set -euo pipefail

PRD_PATH="${1:-}"
if [[ -z "$PRD_PATH" || ! -f "$PRD_PATH" ]]; then
  echo "Error: PRD file not found: $PRD_PATH" >&2
  exit 1
fi

PRD_CONTENT=$(cat "$PRD_PATH")

# Detect format
detect_format() {
  if echo "$PRD_CONTENT" | grep -q '^features:'; then
    echo "yaml"
  elif echo "$PRD_CONTENT" | grep -qE '^### (F[0-9]+:|Feature [0-9]+:)'; then
    echo "markdown-headers"
  elif echo "$PRD_CONTENT" | grep -qiE '^## (What We.re Building|Features)'; then
    echo "superpowers-brainstorm"
  else
    echo "markdown-headers"  # best-effort fallback
  fi
}

FORMAT=$(detect_format)

parse_markdown_headers() {
  python3 - "$PRD_PATH" <<'PYEOF'
import sys, re, json

with open(sys.argv[1]) as f:
    content = f.read()

features = []
# Match ### F1: Name or ### Feature 1: Name or ### 1. Name
pattern = re.compile(r'^#{2,4}\s+(?:F(\d+)|Feature\s+(\d+)|(\d+)\.?)\s*:?\s*(.+)$', re.MULTILINE)
sections = list(pattern.finditer(content))

for i, match in enumerate(sections):
    num = match.group(1) or match.group(2) or match.group(3) or str(i + 1)
    name = match.group(4).strip()
    start = match.end()
    end = sections[i + 1].start() if i + 1 < len(sections) else len(content)
    body = content[start:end].strip()

    # Extract acceptance criteria lines
    ac_lines = re.findall(r'^[-*]\s*(?:Acceptance|AC|criteria)?:?\s*(.+)$', body, re.MULTILINE | re.IGNORECASE)
    # Fallback: all bullet points
    if not ac_lines:
        ac_lines = re.findall(r'^[-*]\s+(.+)$', body, re.MULTILINE)

    features.append({
        "id": f"F{num}",
        "name": name,
        "status": "queued",
        "attempts": 0,
        "acceptance_criteria": ac_lines[:5],  # cap at 5
        "body": body[:500],
        "plan_path": None,
        "commit_sha": None,
        "consultations": []
    })

print(json.dumps(features, indent=2))
PYEOF
}

parse_yaml_frontmatter() {
  python3 - "$PRD_PATH" <<'PYEOF'
import sys, json, re

with open(sys.argv[1]) as f:
    content = f.read()

# Extract YAML frontmatter between --- markers
match = re.match(r'^---\s*\n(.*?)\n---', content, re.DOTALL)
if not match:
    print("[]")
    sys.exit(0)

yaml_block = match.group(1)

# Simple YAML features[] parser (avoids pyyaml dependency)
features = []
feature_blocks = re.split(r'\n  - ', yaml_block)
for block in feature_blocks[1:]:
    lines = block.strip().splitlines()
    f = {"status": "queued", "attempts": 0, "acceptance_criteria": [],
         "plan_path": None, "commit_sha": None, "consultations": []}
    for line in lines:
        m = re.match(r'\s*(id|name|priority):\s*(.+)', line)
        if m:
            f[m.group(1)] = m.group(2).strip()
        ac = re.match(r'\s*- (.+)', line)
        if ac and "acceptance" not in line.lower():
            f["acceptance_criteria"].append(ac.group(1).strip())
    if "id" in f and "name" in f:
        features.append(f)

print(json.dumps(features, indent=2))
PYEOF
}

parse_superpowers_brainstorm() {
  python3 - "$PRD_PATH" <<'PYEOF'
import sys, re, json

with open(sys.argv[1]) as f:
    content = f.read()

features = []
# Find sections under "What We're Building" or "Features"
section_match = re.search(r'^## (?:What We.re Building|Features)\s*\n(.*?)(?=^## |\Z)', content, re.MULTILINE | re.DOTALL | re.IGNORECASE)
if not section_match:
    print("[]")
    sys.exit(0)

section = section_match.group(1)
# Each ### or #### is a feature
blocks = re.split(r'^#{3,4}\s+', section, flags=re.MULTILINE)
for i, block in enumerate(blocks[1:], 1):
    lines = block.strip().splitlines()
    name = lines[0].strip().rstrip(':')
    body = '\n'.join(lines[1:]).strip()
    ac = re.findall(r'^[-*]\s+(.+)$', body, re.MULTILINE)
    features.append({
        "id": f"F{i}",
        "name": name,
        "status": "queued",
        "attempts": 0,
        "acceptance_criteria": ac[:5],
        "body": body[:500],
        "plan_path": None,
        "commit_sha": None,
        "consultations": []
    })

print(json.dumps(features, indent=2))
PYEOF
}

case "$FORMAT" in
  yaml)                  parse_yaml_frontmatter ;;
  superpowers-brainstorm) parse_superpowers_brainstorm ;;
  *)                     parse_markdown_headers ;;
esac
