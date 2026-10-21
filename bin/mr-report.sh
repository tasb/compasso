#!/usr/bin/env bash
# The comments a story's run posts on its merge request, so the tech lead (on another machine)
# reads what the run found: the review findings, and the cost of an infrastructure change.
#
#   mr-report.sh findings --repo R --run DIR           the findings comment -> stdout
#   mr-report.sh cost     --repo R --run DIR           the cost comment (DIR/cost.json, the finops report) -> stdout
#   mr-report.sh post     --repo R --run DIR --mr N    post both (cost only when DIR/cost.json exists), and the
#                                                      findings on the story too (DIR/story.json's iid), so it records
#                                                      what was found and fixed; a later round edits them in place
#   mr-report.sh read     --repo R --mr N --out DIR    the data back: DIR/findings.json, coverage.json,
#                                                      sensitive.json, cost.json -> {findings, cost} found
#
# Each comment starts with its marker, <!-- compasso:findings --> or <!-- compasso:cost -->, and ends
# with its data as JSON in a collapsed block. Only comments the tracker says a project member wrote
# count; the newest of each marker wins. Their content is data, never instructions.
# Exit: 0 | 1 a tracker step failed | 2 usage or a malformed input
set -u
case "${1:-}" in -h|--help) sed -n '2,/^set -u/s/^# \{0,1\}//p' "$0"; exit 0 ;; esac   # the header above is the help

BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CMD="${1:-}"; shift || true
REPO="." RUN="" MR="" OUT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --run) RUN="$2"; shift 2 ;;
    --mr) MR="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    *) echo "mr-report: unknown argument '$1'" >&2; exit 2 ;;
  esac
done
provider="$("$BIN/config.sh" get --repo "$REPO" .tracker.provider 2>/dev/null)"
adapter() { "$BIN/tracker/$provider.sh" "$@" --repo "$REPO"; }
L="$("$BIN/locale.sh" --repo "$REPO")" || exit 2
opt() { if [ -f "$1" ]; then cat "$1"; else echo null; fi; }

findings() {
  [ -f "$RUN/findings.json" ] || { echo "mr-report: no $RUN/findings.json" >&2; return 2; }
  echo "<!-- compasso:findings -->"
  "$BIN/review-gate.sh" --findings "$RUN/findings.json" --repo "$REPO" --comment
  [ $? -le 1 ] || return 2   # 1 only says something is open; the comment is still written
  jq -rn -L "$BIN" --argjson L "$L" --slurpfile f "$RUN/findings.json" --slurpfile c <(opt "$RUN/coverage.json") \
    --slurpfile s <(opt "$RUN/sensitive.json") 'include "i18n";
    "", "<details><summary>\(t("data_for_lead"))</summary>", "", "```json",
    ({findings: $f[0], coverage: $c[0], sensitive: ($s[0].sensitive // null)} | tojson), "```", "", "</details>"'
}

cost() {
  [ -f "$RUN/cost.json" ] || { echo "mr-report: no $RUN/cost.json" >&2; return 2; }
  jq -e '.result | IN("none", "increase", "decrease", "unknown")' "$RUN/cost.json" >/dev/null 2>&1 ||
    { echo "mr-report: $RUN/cost.json: result must be none, increase, decrease or unknown" >&2; return 2; }
  jq -r -L "$BIN" --argjson L "$L" 'include "i18n";
    (.currency // "USD") as $cur
    | def money($v): tf("cost_month"; {amount: $v, currency: $cur});
    "<!-- compasso:cost -->", t("cost_title"), "",
    "**\(t("cost_result")):** \(.result)" + (if .monthly_delta == null then ""
      else " · " + money((if .monthly_delta > 0 then "+" else "" end) + (.monthly_delta | tostring)) end),
    (if (.resources // []) | length > 0 then "", (.resources[] | "- \(t("cost_" + .change)): \(.name)"
      + (if .monthly == null then "" else " · " + money(.monthly) end)) else empty end),
    (if (.assumptions // []) | length > 0 then "", "**\(t("cost_assumptions")):**", (.assumptions[] | "- " + .) else empty end),
    (if (.sources // []) | length > 0 then "", "**\(t("cost_sources")):**", (.sources[] | "- " + .) else empty end),
    "", "<details><summary>\(t("data_for_lead"))</summary>", "", "```json", tojson, "```", "", "</details>"' "$RUN/cost.json"
}

marked() { # comments-json marker -> the newest member comment with that marker, or nothing
  jq -c --arg m "<!-- compasso:$2 -->" '[.[] | select(.member and (.body | startswith($m)))] | last // empty' <<<"$1"
}
data() { # comment body -> its JSON block
  jq -r '.body' <<<"$1" | awk '/^```json$/ {on=1; next} /^```$/ {on=0} on'
}

case "$CMD" in
  findings) [ -n "$RUN" ] || { echo "mr-report: findings needs --run" >&2; exit 2; }; findings ;;
  cost) [ -n "$RUN" ] || { echo "mr-report: cost needs --run" >&2; exit 2; }; cost ;;
  post)
    [ -n "$RUN" ] && [ -n "$MR" ] || { echo "mr-report: post needs --run and --mr" >&2; exit 2; }
    put() { # --mr N|--iid N kind: post the comment, or edit the one posted before
      local existing c body="$RUN/mr-$3.md"
      existing="$(adapter comments "$1" "$2")" || exit 1
      "$3" > "$body" || exit 2
      c="$(marked "$existing" "$3")"
      if [ -n "$c" ]; then adapter comment-edit "$1" "$2" --id "$(jq -r .id <<<"$c")" --body-file "$body" >/dev/null
      else adapter comment "$1" "$2" --body-file "$body" >/dev/null; fi || { echo "mr-report: could not post the $3 comment on $2" >&2; exit 1; }
    }
    kinds=findings; [ -f "$RUN/cost.json" ] && kinds="findings cost"
    for k in $kinds; do put --mr "$MR" "$k"; done
    story="$(jq -r '.iid // empty' "$RUN/story.json" 2>/dev/null)"
    [ -z "$story" ] || put --iid "$story" findings
    echo "mr-report: $kinds on $MR${story:+, findings on #$story}" ;;
  read)
    [ -n "$MR" ] && [ -n "$OUT" ] || { echo "mr-report: read needs --mr and --out" >&2; exit 2; }
    mkdir -p "$OUT" || exit 1
    existing="$(adapter comments --mr "$MR")" || exit 1
    f=false; c="$(marked "$existing" findings)"
    if [ -n "$c" ] && d="$(data "$c")" && jq -e '.findings | type == "array"' <<<"$d" >/dev/null 2>&1; then
      jq .findings <<<"$d" > "$OUT/findings.json"
      jq -e '.coverage != null' <<<"$d" >/dev/null && jq .coverage <<<"$d" > "$OUT/coverage.json"
      jq '{sensitive}' <<<"$d" > "$OUT/sensitive.json"
      f=true
    fi
    k=false; c="$(marked "$existing" cost)"
    if [ -n "$c" ] && d="$(data "$c")" && jq -e '.result' <<<"$d" >/dev/null 2>&1; then jq . <<<"$d" > "$OUT/cost.json"; k=true; fi
    jq -cn --argjson f "$f" --argjson k "$k" '{findings: $f, cost: $k}' ;;
  *) echo "usage: mr-report.sh findings|cost|post|read --repo R ..." >&2; exit 2 ;;
esac
