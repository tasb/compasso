#!/usr/bin/env bash
# Render a sprint report as one self-contained HTML page.
#
#   report.sh --data F --out O
#
# F (JSON, written by metrics.sh collect): {sprint, delivery, flow, quality, agents}.
# Exit: 0 written | 1 invalid data
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DATA="" OUT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --data) DATA="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
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
json="$(jq -c . "$DATA" | sed 's#</#<\\/#g')"
mkdir -p "$(dirname "$OUT")"
JSON="$json" awk '{ i = index($0, "__REPORT_DATA__"); if (i) { print substr($0, 1, i - 1) ENVIRON["JSON"] substr($0, i + 15) } else print }' \
  "$ROOT/templates/report.html" > "$OUT"
echo "report: wrote $OUT"
