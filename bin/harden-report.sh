#!/usr/bin/env bash
# Render the Hardening comment from the checks' results.
#
#   harden-report.sh --results DIR --set code|live|all [--feature N] [--date D]
#
# DIR holds one JSON file per check, in the common format:
#   {check, title, ran: true|false, reason? (when not run),
#    counts: [{label, n}], gaps: [{summary, story?}]}
# Checks are listed in a fixed order: the code set (mutation, property, flaky,
# smells), then the live set (fuzz, zap, perf, a11y). A check of the chosen set
# with no result file is reported as not run.
# Exit: 0 | 2 usage or a malformed result
set -u

BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIR="" SET="code" FEATURE="" DATE="$(date +%Y-%m-%d)" REPO="."
while [ $# -gt 0 ]; do
  case "$1" in
    --results) DIR="$2"; shift 2 ;;
    --set) SET="$2"; shift 2 ;;
    --repo) REPO="$2"; shift 2 ;;
    --feature) FEATURE="$2"; shift 2 ;;
    --date) DATE="$2"; shift 2 ;;
    *) echo "harden-report: unknown argument '$1'" >&2; exit 2 ;;
  esac
done
[ -d "$DIR" ] || { echo "harden-report: no results folder '$DIR'" >&2; exit 2; }
case "$SET" in code|live|all) ;; *) echo "harden-report: --set is code, live or all" >&2; exit 2 ;; esac

results="$( (ls "$DIR"/*.json 2>/dev/null | xargs cat 2>/dev/null) | jq -sc .)" || { echo "harden-report: a result in $DIR is not valid JSON" >&2; exit 2; }
bad="$(jq -r '.[] | . as $r
  | select((.check | type) != "string" or (.title | type) != "string" or (.ran | type) != "boolean"
      or (.ran and ((.counts | type) != "array" or (.gaps | type) != "array"))
      or (.ran | not) and ((.reason // "") == "")
      or any(.counts[]?; (.label | type) != "string" or (.n | type) != "number")
      or any(.gaps[]?; (.summary // "") == ""))
  | "\(.check // "a result"): does not follow the result format"' <<<"$results")"
[ -z "$bad" ] || { printf 'harden-report: %s\n' "$bad" >&2; exit 2; }

L="$("$BIN/locale.sh" --repo "$REPO")" || exit 2
jq -rn -L "$BIN" --argjson L "$L" --argjson r "$results" --arg set "$SET" --arg feature "$FEATURE" --arg date "$DATE" 'include "i18n";
  {code: ["mutation", "property", "flaky", "smells"] | map([., t("check_" + .)]),
   live: ["fuzz", "zap", "perf", "a11y"] | map([., t("check_" + .)])} as $sets
  | (if $set == "all" then $sets.code + $sets.live else $sets[$set] end) as $order
  | tf("harden_title"; {set: t("set_" + $set), date: $date}), "",
    ($order[] | . as [$c, $t] | ([$r[] | select(.check == $c)][0]) as $x
     | if $x == null then "- \($t): \(t("not_run"))"
       elif ($x.ran | not) then "- \($t): \(t("not_run")) — \($x.reason)"
       else "- \($t): " + ([$x.counts[] | "\(.n) \(lbl(.label))"] | join(" · ")),
            ($x.gaps[] | "  - \(.summary)" + (if .story then " → #\(.story)" else "" end))
       end),
    "", "<!-- compasso:harden" + (if $feature != "" then " feature=\($feature)" else "" end) + " set=\($set) -->"'
