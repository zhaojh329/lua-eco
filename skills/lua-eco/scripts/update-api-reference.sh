#!/usr/bin/env bash
set -euo pipefail

SKILL="$(cd "$(dirname "$0")/.." && pwd)"
REPO="${LUA_ECO_REPO:-/home/zjh/work/lua-eco}"
DOCS_URL="${LUA_ECO_DOCS_URL:-https://zhaojh329.github.io/lua-eco/}"
OUT="$SKILL/references/91-api-quick-reference.md"
MANIFEST="$SKILL/references/90-public-api-manifest.md"
CHECK=0
SOURCE=""

usage() {
  cat <<'EOF'
Usage: update-api-reference.sh [--check] [--source PATH_OR_URL]

Generate references/91-api-quick-reference.md from LDoc search data.
By default, the script prefers local docs and falls back to GitHub Pages.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check)
      CHECK=1
      shift
      ;;
    --source)
      SOURCE="${2:-}"
      [[ -n "$SOURCE" ]] || { echo '--source requires a value'; exit 1; }
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1"
      usage
      exit 1
      ;;
  esac
done

command -v python3 >/dev/null 2>&1 || { echo 'python3 is required'; exit 1; }

DATA="$(mktemp)"
trap 'rm -f "$DATA"' EXIT

fetch() {
  local src="$1"

  if [[ "$src" == http://* || "$src" == https://* ]]; then
    curl -fsSL "$src" > "$DATA"
  else
    cp "$src" "$DATA"
  fi
}

if [[ -n "$SOURCE" ]]; then
  fetch "$SOURCE"
else
  found=0
  for dir in \
    "${LUA_ECO_DOCS_DIR:-}" \
    "$REPO/docs" \
    "$REPO/build/docs" \
    "$REPO/doc" \
    "$REPO/build/doc"; do
    [[ -n "$dir" ]] || continue
    if [[ -f "$dir/ldoc_search_data.js" ]]; then
      cp "$dir/ldoc_search_data.js" "$DATA"
      found=1
      break
    fi
  done

  if [[ "$found" -eq 0 ]]; then
    curl -fsSL "${DOCS_URL%/}/ldoc_search_data.js" > "$DATA"
  fi
fi

python3 - "$DATA" "$OUT" "$MANIFEST" "$DOCS_URL" "$CHECK" <<'PY'
import difflib
import json
import re
import sys
from pathlib import Path
from urllib.parse import urljoin

data_path = Path(sys.argv[1])
out_path = Path(sys.argv[2])
manifest_path = Path(sys.argv[3])
docs_url = sys.argv[4].rstrip("/") + "/"
check = sys.argv[5] == "1"

text = data_path.read_text(encoding="utf-8")
match = re.search(r"window\.ldocSearchData\s*=\s*(\[.*?\]);", text, re.S)
if not match:
    raise SystemExit("Could not find window.ldocSearchData array")

entries = json.loads(match.group(1))

def one_line(value):
    return re.sub(r"\s+", " ", (value or "").strip())

def canonical(module, symbol, title):
    if module == "eco.time" and symbol.startswith("timer_methods:"):
        symbol = "timer:" + symbol.split(":", 1)[1]
        title = title.replace("timer_methods:", "timer:", 1)
    if module == "eco.mqtt" and symbol.startswith("methods:"):
        symbol = "client:" + symbol.split(":", 1)[1]
        title = title.replace("methods:", "client:", 1)
    return symbol, title

def read_manifest(path):
    module = None
    result = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.startswith("## eco"):
            module = line[3:].strip()
            result.setdefault(module, set())
        elif module and line.startswith("- `"):
            symbol = line.split("`", 2)[1]
            result.setdefault(module, set()).add(symbol)
    return result

manifest = read_manifest(manifest_path)
by_module = {module: [] for module in manifest}
seen = set()

for item in entries:
    module = item.get("module", "")
    if not (module == "eco" or module.startswith("eco.")):
        continue

    symbol = one_line(item.get("symbol"))
    title = one_line(item.get("title"))
    kind = one_line(item.get("kind"))
    summary = one_line(item.get("summary"))
    url = urljoin(docs_url, item.get("url", ""))
    symbol, title = canonical(module, symbol, title)
    key = (module, symbol)

    if key in seen:
        continue

    seen.add(key)
    by_module.setdefault(module, []).append({
        "symbol": symbol,
        "title": title,
        "kind": kind,
        "summary": summary,
        "url": url,
    })

for module, symbols in manifest.items():
    by_module.setdefault(module, [])
    for symbol in sorted(symbols):
        key = (module, symbol)
        if key in seen:
            continue
        seen.add(key)
        by_module[module].append({
            "symbol": symbol,
            "title": symbol,
            "kind": "Manifest",
            "summary": "Listed in the public API manifest; no LDoc search entry is currently available.",
            "url": docs_url,
        })

lines = [
    "# API Quick Reference (Generated)",
    "",
    "Generated from lua-eco LDoc search data and merged with the public API manifest.",
    f"Official docs root: {docs_url}",
    "",
    "Do not edit by hand. Run `scripts/update-api-reference.sh`.",
    "",
]

for module in sorted(by_module):
    rows = sorted(by_module[module], key=lambda row: (row["symbol"].lower(), row["title"].lower()))
    if not rows:
        continue

    lines.append(f"## {module}")
    for row in rows:
        title = row["title"] or row["symbol"]
        kind = row["kind"] or "API"
        summary = row["summary"] or "No summary available."
        url = row["url"]
        lines.append(f"- `{row['symbol']}` - {title} [{kind}]. {summary} Docs: {url}")
    lines.append("")

content = "\n".join(lines).rstrip() + "\n"

if check:
    current = out_path.read_text(encoding="utf-8") if out_path.exists() else ""
    if current != content:
        diff = difflib.unified_diff(
            current.splitlines(keepends=True),
            content.splitlines(keepends=True),
            fromfile=str(out_path),
            tofile="generated",
        )
        sys.stdout.writelines(diff)
        raise SystemExit("API quick reference is out of date")
else:
    out_path.write_text(content, encoding="utf-8")
PY
