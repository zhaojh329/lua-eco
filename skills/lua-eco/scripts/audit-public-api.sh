#!/usr/bin/env bash
set -euo pipefail

REPO="${LUA_ECO_REPO:-/home/zjh/work/lua-eco}"
SKILL="$(cd "$(dirname "$0")/.." && pwd)"
MANIFEST="$SKILL/references/90-public-api-manifest.md"
QUICK_REF="$SKILL/references/91-api-quick-reference.md"
CHECKLIST="$SKILL/references/08-api-coverage-checklist.md"
SOURCE_API="/tmp/lua_eco_source_public_api.$$"
MANIFEST_API="/tmp/lua_eco_manifest_public_api.$$"
QUICK_API="/tmp/lua_eco_quick_public_api.$$"
MISSING_API="/tmp/lua_eco_missing_public_api.$$"
MISSING_QUICK_API="/tmp/lua_eco_missing_quick_public_api.$$"

trap 'rm -f "$SOURCE_API" "$MANIFEST_API" "$QUICK_API" "$MISSING_API" "$MISSING_QUICK_API"' EXIT

echo '[1/5] Extracting source annotations without file or line numbers'
cd "$REPO"
awk '
function emit(kind, mod, sym) {
  if (kind == "MODULE")
    print kind "\t" mod
  else if (mod != "" && sym != "")
    print kind "\t" mod "\t" sym
}
{
  line = $0
  if (match(line, /@module[[:space:]]+eco(\.[A-Za-z0-9_]+)*/)) {
    module = substr(line, RSTART, RLENGTH)
    sub(/^@module[[:space:]]+/, "", module)
    modules[module] = 1
  }
  if (match(line, /@function[[:space:]]+[A-Za-z0-9_:.]+/)) {
    symbol = substr(line, RSTART, RLENGTH)
    sub(/^@function[[:space:]]+/, "", symbol)
    if (module != "")
      funcs[module SUBSEP symbol] = 1
  }
}
END {
  for (module in modules)
    emit("MODULE", module, "")
  for (key in funcs) {
    split(key, parts, SUBSEP)
    emit("FUNC", parts[1], parts[2])
  }
}
' *.lua *.c http/*.lua nl/*.lua nl/*.c hash/*.lua hash/*.c 2>/dev/null | sort > "$SOURCE_API"

echo '[2/5] Reading public API manifest'
[[ -f "$MANIFEST" ]] || { echo 'Missing public API manifest'; exit 1; }
if grep -Eq '[A-Za-z0-9_./-]+\.(lua|c):[0-9]+:' "$MANIFEST"; then
  echo 'Manifest must not contain source filenames or line numbers'
  exit 1
fi
if grep -q 'luaopen_eco' "$MANIFEST"; then
  echo 'Manifest must not contain C loader implementation symbols'
  exit 1
fi

awk '
/^## eco([.]|$)/ {
  module = $2
  modules[module] = 1
  next
}
/^- `/ && module != "" {
  symbol = $0
  sub(/^- `/, "", symbol)
  sub(/`.*/, "", symbol)
  funcs[module SUBSEP symbol] = 1
}
END {
  for (module in modules)
    print "MODULE\t" module
  for (key in funcs) {
    split(key, parts, SUBSEP)
    print "FUNC\t" parts[1] "\t" parts[2]
  }
}
' "$MANIFEST" | sort > "$MANIFEST_API"

echo '[3/5] Reading API quick reference'
[[ -f "$QUICK_REF" ]] || { echo 'Missing API quick reference'; exit 1; }
if grep -Eq '[A-Za-z0-9_./-]+\.(lua|c):[0-9]+:' "$QUICK_REF"; then
  echo 'API quick reference must not contain source filenames or line numbers'
  exit 1
fi
if grep -q 'luaopen_eco' "$QUICK_REF"; then
  echo 'API quick reference must not contain C loader implementation symbols'
  exit 1
fi

awk '
/^## eco([.]|$)/ {
  module = $2
  modules[module] = 1
  next
}
/^- `/ && module != "" {
  symbol = $0
  sub(/^- `/, "", symbol)
  sub(/`.*/, "", symbol)
  funcs[module SUBSEP symbol] = 1
}
END {
  for (module in modules)
    print "MODULE\t" module
  for (key in funcs) {
    split(key, parts, SUBSEP)
    print "FUNC\t" parts[1] "\t" parts[2]
  }
}
' "$QUICK_REF" | sort > "$QUICK_API"

echo '[4/5] Comparing API coverage'
comm -23 "$SOURCE_API" "$MANIFEST_API" > "$MISSING_API"
if [[ -s "$MISSING_API" ]]; then
  echo 'Manifest is missing source-annotated public API entries:'
  cat "$MISSING_API"
  exit 1
fi

comm -23 "$MANIFEST_API" "$QUICK_API" > "$MISSING_QUICK_API"
if [[ -s "$MISSING_QUICK_API" ]]; then
  echo 'API quick reference is missing public manifest entries:'
  cat "$MISSING_QUICK_API"
  exit 1
fi

echo '[5/5] Checking coverage checklist'
[[ -f "$CHECKLIST" ]] || { echo 'Missing coverage checklist'; exit 1; }

for mod in \
  eco.time eco.sync eco.channel eco.file eco.sys eco.socket eco.ssl eco.dns eco.net eco.packet \
  eco.http.url eco.http.client eco.http.server eco.websocket eco.mqtt eco.ubus eco.uci eco.shared eco.log eco.termios eco.ssh \
  eco.nl eco.genl eco.rtnl eco.ip eco.nl80211 eco.encoding.base64 eco.encoding.hex eco.hash.md5 eco.hash.sha1 eco.hash.sha256 eco.hash.hmac; do
  grep -q "$mod" "$CHECKLIST" || { echo "Coverage checklist is missing module: $mod"; exit 1; }
  grep -q "^## $mod$" "$MANIFEST" || { echo "Public API manifest is missing module: $mod"; exit 1; }
  grep -q "^## $mod$" "$QUICK_REF" || { echo "API quick reference is missing module: $mod"; exit 1; }
done

SOURCE_COUNT=$(wc -l < "$SOURCE_API")
MANIFEST_COUNT=$(wc -l < "$MANIFEST_API")
QUICK_COUNT=$(wc -l < "$QUICK_API")
echo "Source annotation entries: $SOURCE_COUNT"
echo "Manifest entries: $MANIFEST_COUNT"
echo "Quick reference entries: $QUICK_COUNT"

echo 'Public API audit complete.'
