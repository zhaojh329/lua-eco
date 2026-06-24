#!/usr/bin/env bash
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"

echo '[1/5] Checking directory structure'
[[ -f "$SKILL_DIR/SKILL.md" ]] || { echo 'Missing SKILL.md'; exit 1; }
[[ -d "$SKILL_DIR/references" ]] || { echo 'Missing references'; exit 1; }
[[ -d "$SKILL_DIR/scripts" ]] || { echo 'Missing scripts'; exit 1; }

echo '[2/5] Checking core references'
for f in \
  00-activation-and-global-rules.md \
  01-core-and-concurrency.md \
  02-files-processes-system.md \
  03-networking-and-transport.md \
  04-http-websocket-mqtt.md \
  05-platform-integration-and-devices.md \
  06-netlink-family.md \
  07-encoding-and-digests.md \
  08-api-coverage-checklist.md \
  09-code-review-template.md \
  10-capability-matrix-and-routing-guards.md \
  11-regression-prompts.md \
  90-public-api-manifest.md \
  91-api-quick-reference.md \
  95-high-risk-api-shapes.md \
  92-usage-patterns.md \
  93-common-mistakes.md \
  94-program-skeleton.md; do
  [[ -f "$SKILL_DIR/references/$f" ]] || { echo "Missing $f"; exit 1; }
done

echo '[3/5] Checking required scripts'
for f in \
  audit-public-api.sh \
  check-routing-rules.sh \
  update-api-reference.sh \
  validate-skill.sh; do
  [[ -x "$SKILL_DIR/scripts/$f" ]] || { echo "Missing executable script $f"; exit 1; }
done

echo '[4/5] Optional skills-ref validation'
if command -v skills-ref >/dev/null 2>&1; then
  skills-ref validate "$SKILL_DIR"
else
  echo 'skills-ref is not installed; skipping schema validation.'
fi

echo '[5/5] Running routing rule checks'
"$SKILL_DIR/scripts/check-routing-rules.sh"

echo 'Validation complete.'
