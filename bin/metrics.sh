#!/usr/bin/env bash
# Collect a sprint's metrics into the report's data.
#
#   metrics.sh collect --repo R --out F [--today YYYY-MM-DD]
#
# Reads the sprint from .compasso/plan.yaml, its work items and their label history
# from GitLab, the last four sprints' done hours, the story metrics files in
# .compasso/metrics/, the testers' results in docs/releases/S<n>-results/, and the
# optional prices in metrics.prices. Render the result with report.sh.
# Exit: 0 | 1 input or tracker problem
set -u

BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CMD="${1:-}"; shift || true
REPO="." OUT="" TODAY="$(date -u +%Y-%m-%d)" NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --today) TODAY="$2"; NOW="$2T23:59:59Z"; shift 2 ;;   # everything is counted to the report's date
    *) echo "metrics: unknown argument '$1'" >&2; exit 1 ;;
  esac
done
[ "$CMD" = collect ] && [ -n "$OUT" ] || { echo "usage: metrics.sh collect --repo R --out F [--today D]" >&2; exit 1; }
"$BIN/config.sh" validate --repo "$REPO" >/dev/null || exit 1
PLAN="$REPO/.compasso/plan.yaml"
[ -f "$PLAN" ] || { echo "metrics: no $PLAN - run /compasso:plan" >&2; exit 1; }
cfg() { "$BIN/config.sh" get --repo "$REPO" "$1"; }
HOST="$(cfg .tracker.host)"; PID="$(cfg .tracker.project | sed 's#/#%2F#g')"
api() { glab api --hostname "$HOST" "$@"; }

n="$(yq -r .epic.sprint.number "$PLAN")"; ms="S$n"
"$BIN/tracker/gitlab.sh" check --repo "$REPO" >/dev/null || exit 1
sync="$("$BIN/tracker/gitlab.sh" sprint-sync --repo "$REPO" --milestone "$ms")" || exit 1

items="$(api --paginate "projects/$PID/issues?milestone=$ms&state=all&per_page=100" | jq -s 'add // []')" ||
  { echo "metrics: cannot read the work items of $ms" >&2; exit 1; }
with='[]'
for i in $(jq -r '.[] | select(.issue_type == "task") | .iid' <<<"$items"); do
  ev="$(api --paginate "projects/$PID/issues/$i/resource_label_events?per_page=100" | jq -s 'add // []')" || ev='[]'
  with="$(jq -c --argjson i "$i" --argjson ev "$ev" '. + [{iid: $i, label_events: $ev}]' <<<"$with")"
done
items="$(jq -c --argjson with "$with" 'map(. as $it | . + {label_events: ([$with[] | select(.iid == $it.iid) | .label_events][0] // [])})' <<<"$items")"

history='[]'
for k in 4 3 2 1; do
  p=$((n - k)); [ "$p" -ge 1 ] || continue
  done_h="$(api --paginate "projects/$PID/issues?milestone=S$p&state=closed&per_page=100" | jq -s '
    add // [] | map(select(.issue_type == "task" and ((.labels | index("type::blocker")) | not)))
    | if length == 0 then null else (map(.time_stats.time_estimate // 0) | add / 3600) end')" || done_h=null
  [ "$done_h" = null ] || history="$(jq -c --arg s "S$p" --argjson h "$done_h" '. + [{sprint: $s, done_h: ($h * 10 | round / 10)}]' <<<"$history")"
done

iids="$(jq -c '[.[].iid]' <<<"$items")"
files="$( (ls "$REPO"/.compasso/metrics/*.json 2>/dev/null | xargs cat 2>/dev/null) | jq -sc --argjson in "$iids" 'map(select(.iid as $i | $in | index($i)))')"
results="$( (ls "$REPO/docs/releases/$ms-results/"*.json 2>/dev/null | xargs cat 2>/dev/null) | jq -sc .)"
prices="$(yq -o=json '.metrics.prices // {}' "$REPO/.compasso/project.yaml")"
currency="$(cfg '.metrics.currency // "USD"')"
status="in progress"; [ "$(jq -r .sprint_done <<<"$sync")" = true ] && status=closed
sprint="$(yq -o=json '.epic' "$PLAN" | jq -c --argjson cap "$(cfg .sprint.capacity_hours)" --arg status "$status" \
  '{number: .sprint.number, goal, start: .sprint.start, end: .sprint.end, capacity_h: $cap, status: $status}')"

mkdir -p "$(dirname "$OUT")"
jq -n --argjson sprint "$sprint" --arg today "$TODAY" --arg now "$NOW" \
  --argjson items "$items" --argjson sync "$sync" --argjson history "$history" --argjson files "$files" \
  --argjson results "$results" --argjson prices "$prices" --arg currency "$currency" \
  -f "$BIN/metrics.jq" > "$OUT" || { echo "metrics: could not build the report data" >&2; exit 1; }
echo "metrics: wrote $OUT"
