#!/usr/bin/env bash
# Render a sprint report as one self-contained HTML page.
#
#   report.sh --data F --out O
#
# F (JSON, written by metrics.sh collect): {sprint, delivery, flow, quality, agents}.
# Exit: 0 written | 1 invalid data
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DATA="" OUT="" REPO="."
while [ $# -gt 0 ]; do
  case "$1" in
    --data) DATA="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --repo) REPO="$2"; shift 2 ;;   # the project's language for the page's labels
    *) echo "report: unknown argument '$1'" >&2; exit 1 ;;
  esac
done
[ -f "$DATA" ] && [ -n "$OUT" ] || { echo "report: needs --data and --out" >&2; exit 1; }
problems="$(jq -r '
  (["sprint", "delivery", "flow", "quality", "agents"][] as $k | select(has($k) | not) | "\($k) is required"),
  (["number", "goal", "start", "end", "capacity_h", "status", "generated"][] as $k
    | select((.sprint // {}) | has($k) | not) | "sprint.\($k) is required")' "$DATA" 2>/dev/null)" ||
  { echo "report: $DATA is not valid JSON" >&2; exit 1; }
[ -z "$problems" ] || { printf 'report: %s\n' "$problems" >&2; exit 1; }

# "</" would end the script element early; ENVIRON keeps awk from reading escapes
# the page's labels in the project's language; labels in the data win
L="$("$ROOT/bin/locale.sh" --repo "$REPO")" || exit 1
tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
jq -c --argjson L "$L" '. + {ui: ($L.ui.report + (.ui // {})), language: (.language // $L.lang)}' "$DATA" > "$tmp" || exit 1
"$ROOT/bin/html-inject.sh" --template "$ROOT/templates/report.html" --marker __REPORT_DATA__ --data "$tmp" \
  --lang "$(jq -r .language "$tmp")" --title "$(jq -r '.sprint.number as $n | .ui.title | gsub("\\{n\\}"; ($n | tostring))' "$tmp")" --out "$OUT" || exit 1
echo "report: wrote $OUT"
