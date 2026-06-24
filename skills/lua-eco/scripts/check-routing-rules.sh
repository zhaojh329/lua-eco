#!/usr/bin/env bash
set -euo pipefail

BASE="$(cd "$(dirname "$0")/.." && pwd)"
RULE_FILE="$BASE/references/10-capability-matrix-and-routing-guards.md"
MANIFEST_FILE="$BASE/references/90-public-api-manifest.md"
QUICK_REF="$BASE/references/91-api-quick-reference.md"
SKELETON_FILE="$BASE/references/94-program-skeleton.md"
SHAPE_FILE="$BASE/references/95-high-risk-api-shapes.md"

echo 'Checking capability matrix file...'
[[ -f "$RULE_FILE" ]] || { echo 'Missing capability matrix file'; exit 1; }

echo 'Checking routing guard key entries...'
grep -q 'General Selection Flow' "$RULE_FILE" || { echo 'Missing General Selection Flow'; exit 1; }
grep -q 'Primary' "$RULE_FILE" || { echo 'Missing Primary definition'; exit 1; }
grep -q 'Secondary' "$RULE_FILE" || { echo 'Missing Secondary definition'; exit 1; }
grep -q 'Anti-pattern' "$RULE_FILE" || { echo 'Missing Anti-pattern definition'; exit 1; }
grep -q 'Symbol Gate' "$RULE_FILE" || { echo 'Missing Symbol Gate'; exit 1; }
grep -q 'Shape Gate' "$RULE_FILE" || { echo 'Missing Shape Gate'; exit 1; }
grep -q 'Signature Gate' "$RULE_FILE" || { echo 'Missing Signature Gate'; exit 1; }
grep -q 'Example Gate' "$RULE_FILE" || { echo 'Missing Example Gate'; exit 1; }
grep -q 'Output Gate' "$RULE_FILE" || { echo 'Missing Output Gate'; exit 1; }
grep -q 'Evidence Priority' "$RULE_FILE" || { echo 'Missing Evidence Priority'; exit 1; }

echo 'Checking public API manifest...'
[[ -f "$MANIFEST_FILE" ]] || { echo 'Missing public API manifest'; exit 1; }
grep -q '^## eco.socket$' "$MANIFEST_FILE" || { echo 'Public API manifest is missing eco.socket'; exit 1; }
grep -q '^- `connect_tcp`' "$MANIFEST_FILE" || { echo 'Public API manifest is missing socket connect_tcp'; exit 1; }
grep -q '^- `sleep`' "$MANIFEST_FILE" || { echo 'Public API manifest is missing eco.sleep'; exit 1; }
if grep -Eq '[A-Za-z0-9_./-]+\.(lua|c):[0-9]+:' "$MANIFEST_FILE"; then
  echo 'Public API manifest must not contain source filenames or line numbers'
  exit 1
fi
if grep -q 'luaopen_eco' "$MANIFEST_FILE"; then
  echo 'Public API manifest must not contain C loader implementation symbols'
  exit 1
fi

echo 'Checking API quick reference...'
[[ -f "$QUICK_REF" ]] || { echo 'Missing API quick reference'; exit 1; }
grep -q '^## eco.socket$' "$QUICK_REF" || { echo 'API quick reference is missing eco.socket'; exit 1; }
grep -q '^- `connect_tcp`' "$QUICK_REF" || { echo 'API quick reference is missing socket connect_tcp'; exit 1; }
grep -q 'Official docs root: https://zhaojh329.github.io/lua-eco/' "$QUICK_REF" || { echo 'API quick reference has unexpected docs root'; exit 1; }
if grep -Eq '[A-Za-z0-9_./-]+\.(lua|c):[0-9]+:' "$QUICK_REF"; then
  echo 'API quick reference must not contain source filenames or line numbers'
  exit 1
fi

echo 'Checking program skeleton...'
[[ -f "$SKELETON_FILE" ]] || { echo 'Missing program skeleton reference'; exit 1; }
grep -q 'trace_hook' "$SKELETON_FILE" || { echo 'Program skeleton is missing trace hook'; exit 1; }
grep -q "log.set_ident('task-specific-ident')" "$SKELETON_FILE" || { echo 'Program skeleton is missing task-specific ident placeholder'; exit 1; }

echo 'Checking high-risk shape reference...'
[[ -f "$SHAPE_FILE" ]] || { echo 'Missing high-risk shape reference'; exit 1; }
grep -q '^## eco.http.client$' "$SHAPE_FILE" || { echo 'High-risk shapes missing eco.http.client'; exit 1; }
grep -q 'resp.code' "$SHAPE_FILE" || { echo 'High-risk shapes missing resp.code guidance'; exit 1; }
grep -q 'status_code' "$SHAPE_FILE" || { echo 'High-risk shapes missing status_code rejection'; exit 1; }
grep -q '^## eco.websocket$' "$SHAPE_FILE" || { echo 'High-risk shapes missing eco.websocket'; exit 1; }
grep -q '^## eco.sys$' "$SHAPE_FILE" || { echo 'High-risk shapes missing eco.sys'; exit 1; }

echo 'Routing rule checks passed.'
