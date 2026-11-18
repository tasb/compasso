#!/usr/bin/env bash
# A read-only readout of where the project stands, as bin/run.sh sees it. It writes nothing.
#
#   status.sh --repo R [--json]
#
# From one tracker snapshot (tracker.sh snapshot): the stage, the default branch's pipeline, what waits for a
# person (needs::human issues), the open merge requests, the open stories and bugs by developer, and the job
# bin/run.sh would start next for the tech lead and for each developer (bin/next.jq). From this machine's
# runner files (.compasso/runs/runner): its last runs, and the jobs skipped until a person answers.
# Exit: 0 | 1 the tracker could not be read (this machine's runs are still shown) | 2 usage
set -u
case "${1:-}" in -h|--help) sed -n '2,/^set -u/s/^# \{0,1\}//p' "$0"; exit 0 ;; esac   # the header above is the help

BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="." JSON=0
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --json) JSON=1; shift ;;
    *) echo "status: unknown argument '$1'" >&2; exit 2 ;;
  esac
done
"$BIN/version.sh"   # warns on stderr when an older Compasso runs than the newest installed
cfg() { "$BIN/config.sh" get --repo "$REPO" "$1"; }
DIR="$REPO/.compasso/runs/runner"
n="$(cfg '.run.failures // 2')"
stuck='[]'; [ -s "$DIR/failures.json" ] && stuck="$(jq -c --argjson n "$n" '[to_entries[] | select(.value >= $n) | .key]' "$DIR/failures.json")"
runs='[]'; [ -s "$DIR/events.jsonl" ] && runs="$(tail -n 5 "$DIR/events.jsonl" | jq -s -c .)"
devs="$(yq -o=json -I0 '.team.developers // []' "$REPO/.compasso/project.yaml")"

rc=0
e="$(mktemp)"
if snap="$("$BIN/tracker.sh" snapshot --repo "$REPO" 2>"$e")"; then err=""
else rc=1; err="$(tail -1 "$e")"; snap='null'; fi
rm -f "$e"

# next.jq reads its role from named arguments: run it once per role
if [ "$snap" != null ]; then
  nx() { jq -c -L "$BIN" --arg role "$1" --arg name "$2" --argjson devs "$devs" --argjson queue "$(cfg '.team.queue.min // 2')" \
    --arg stage "$(cfg .stage)" --argjson audited "$([ -f "$DIR/audited" ] && echo true || echo false)" --argjson skip "$stuck" \
    'include "next"; next | if .job then {job, iids, mrs} else null end' <<<"$snap"; }
  nexts="$(nx lead "" | jq -c '{lead: .}')"
  for d in $(jq -r '.[]' <<<"$devs"); do nexts="$(jq -c --arg d "$d" --argjson j "$(nx dev "$d")" '. + {($d): $j}' <<<"$nexts")"; done
fi

out="$(jq -n -c --argjson s "$snap" --arg err "$err" --arg stage "$(cfg '.stage // "production"')" --argjson runs "$runs" --argjson stuck "$stuck" \
  --argjson next "${nexts:-null}" '
  {stage: $stage, runs: $runs, stuck: $stuck}
  + if $s == null then {tracker: $err} else {
      main: $s.main.pipeline,
      asks: [$s.issues[] | select(.kind == "ask") | {iid, title, web_url, for: .ask_for}],
      mrs: [$s.mrs[] | {iid, story, draft, rework, pipeline}],
      work: [$s.issues[] | select(.kind == "story" or .kind == "bug") | {iid, title, kind, state, dev, needs_human, blocked_by}],
      later: ([$s.issues[] | select(.kind == "later") | .iid][0] // null),
      next: $next
    } end')" || exit 1

if [ "$JSON" -eq 1 ]; then echo "$out"; exit "$rc"; fi
jq -r '
  def job: if . == null then "nothing" else "\(.job) \((.iids // []) | map("#\(.)") | join(" "))\(if (.mrs // []) | length > 0 then " " + (.mrs | map("!\(.)") | join(" ")) else "" end)" end;
  "Stage: \(.stage)",
  if .tracker then "Tracker: \(.tracker)" else
    "Main: \(.main)",
    "Waiting for a person: \(if (.asks | length) == 0 then "nothing" else "" end)",
    (.asks[] | "  #\(.iid) \(.title)\(if .for then " (holds #\(.for))" else "" end) \(.web_url)"),
    "Merge requests: \(if (.mrs | length) == 0 then "none" else "" end)",
    (.mrs[] | "  !\(.iid) #\(.story // "?") \(if .draft then "draft" elif .rework then "sent back for rework" elif .pipeline == "failed" then "pipeline failed" elif .pipeline == "success" then "green, waits for review" else "pipeline \(.pipeline)" end)"),
    "Stories and bugs: \(if (.work | length) == 0 then "none open" else "" end)",
    (.work | group_by(.dev // "") | .[] | "  \(.[0].dev // "nobody"): " + (map("#\(.iid) \(if .needs_human then "waits for a person" elif (.blocked_by | length) > 0 then "blocked by \(.blocked_by | map("#\(.)") | join(" "))" else .state // "new" end)") | join(", "))),
    (if .later then "After-MVP list: #\(.later)" else empty end),
    "Next job:",
    (.next | to_entries[] | "  \(.key): \(.value | job)")
  end,
  (if (.stuck | length) > 0 then "Skipped until a person answers: \(.stuck | join(", "))" else empty end),
  "Last runs here: \(if (.runs | length) == 0 then "none" else "" end)",
  (.runs[] | "  \(.at) \(.role)\(if .name then " " + .name else "" end) \(.job // "idle") \(.key // "") \(.result) \(.seconds)s")
' <<<"$out"
exit "$rc"
