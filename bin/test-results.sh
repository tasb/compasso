#!/usr/bin/env bash
# File a tester's results from the HTML test guide.
#
#   test-results.sh --repo R --guide GUIDE.json --results RESULTS.json [--epic N]
#
# Every scenario marked "doesn't work" becomes a Bug under its feature, in the Bug
# format and in the tester's words; "can't test" is listed in the summary. A summary
# comment goes on the epic (--epic, else plan.yaml's epic). Results already filed
# (same guide, scenario and tester) are skipped, so a file can be imported twice.
# Exit: 0 | 1 invalid input or tracker failure
set -u

BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="." GUIDE="" RESULTS="" EPIC=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --guide) GUIDE="$2"; shift 2 ;;
    --results) RESULTS="$2"; shift 2 ;;
    --epic) EPIC="$2"; shift 2 ;;
    *) echo "test-results: unknown argument '$1'" >&2; exit 1 ;;
  esac
done
[ -f "$GUIDE" ] && [ -f "$RESULTS" ] || { echo "test-results: needs --guide and --results" >&2; exit 1; }
jq -e . "$RESULTS" >/dev/null 2>&1 || { echo "test-results: $RESULTS is not valid JSON" >&2; exit 1; }

gid="$(jq -r .id "$GUIDE")"
problems="$(jq -r --slurpfile g "$GUIDE" '
  ([$g[0].features[].scenarios[].id]) as $known
  | (if .guide != $g[0].id then "these results are for guide \(.guide), not \($g[0].id)" else empty end),
    (if (.tester // "") == "" then "the results name no tester" else empty end),
    (.results[]? | select(.scenario as $s | $known | index($s) | not) | "unknown scenario \(.scenario)"),
    (.results[]? | select(.status | IN("pass", "fail", "blocked", "not-tested") | not) | "unknown status \(.status) for \(.scenario)"),
    (.results[]? | select(.status == "fail" and ((.comment // "") == "")) | "\(.scenario) failed without a comment")
' "$RESULTS")"
[ -z "$problems" ] || { printf 'test-results: %s\n' "$problems" >&2; exit 1; }

[ -n "$EPIC" ] || EPIC="$(yq -r '.epic.gitlab.issue // ""' "$REPO/.compasso/plan.yaml" 2>/dev/null)"
[ -n "$EPIC" ] && [ "$EPIC" != null ] || { echo "test-results: no epic to report on (pass --epic)" >&2; exit 1; }

tester="$(jq -r .tester "$RESULTS")"; date="$(jq -r .date "$RESULTS")"
slug="$(printf '%s' "$tester" | tr 'A-Z' 'a-z' | sed -E 's/[^a-z0-9]+/-/g; s/^-|-$//g')"
DIR="$REPO/.compasso/runs/guide-$gid"; mkdir -p "$DIR"
# keep the results where the sprint report reads them (committed with the guide)
mkdir -p "$REPO/docs/releases/$gid-results" && cp "$RESULTS" "$REPO/docs/releases/$gid-results/$slug.json" ||
  { echo "test-results: cannot keep the results in docs/releases/$gid-results" >&2; exit 1; }
LEDGER="$DIR/imported.json"; [ -f "$LEDGER" ] || echo '{}' > "$LEDGER"
filed='[]'

for sc in $(jq -r '.results[] | select(.status == "fail") | .scenario' "$RESULTS"); do
  key="$slug/$sc"
  prev="$(jq -r --arg k "$key" '.[$k] // empty' "$LEDGER")"
  if [ -n "$prev" ]; then
    filed="$(jq -c --arg s "$sc" --argjson i "$prev" '. + [{scenario: $s, iid: $i, new: false}]' <<<"$filed")"
    continue
  fi
  info="$(jq -c --arg s "$sc" '.features[] as $f | $f.scenarios[] | select(.id == $s) | {f: $f, s: .}' "$GUIDE")"
  body="$DIR/bug-$slug-$sc.md"
  jq -rn --argjson x "$info" --slurpfile r "$RESULTS" --arg gid "$gid" --arg slug "$slug" '
    $r[0] as $r | ($r.results[] | select(.scenario == $x.s.id)) as $res
    | "**Found in:** \($gid) test guide · **By:** \($r.tester) (business test, \($r.date))",
      "", "## Steps", ($x.s.steps | to_entries | map("\(.key + 1). \(.value)") | join("\n")),
      "", "## Expected", "- \($x.s.expected)",
      "", "## Actual", "- \($res.comment)",
      "", "## Evidence", "- Reported by \($r.tester) in the \($gid) test guide, scenario \"\($x.s.title)\"",
      "", "<!-- compasso:guide=\($gid) scenario=\($x.s.id) tester=\($slug) -->"' > "$body"
  title="$(jq -r '"\(.f.title): \(.s.title) does not work"' <<<"$info")"
  iid="$("$BIN/tracker/gitlab.sh" followup --repo "$REPO" --parent "$(jq -r .f.iid <<<"$info")" \
          --title "$title" --body-file "$body" --labels type::bug,severity::major,owner::agent)" ||
    { echo "test-results: could not file the bug for $sc" >&2; exit 1; }
  jq --arg k "$key" --argjson i "$iid" '.[$k] = $i' "$LEDGER" > "$LEDGER.new" && mv "$LEDGER.new" "$LEDGER"
  filed="$(jq -c --arg s "$sc" --argjson i "$iid" '. + [{scenario: $s, iid: $i, new: true}]' <<<"$filed")"
done

summary="$DIR/summary-$slug-$date.md"
jq -rn --slurpfile r "$RESULTS" --slurpfile g "$GUIDE" --argjson filed "$filed" --arg dw "Doesn't work" --arg ct "Can't test" '
  $r[0] as $r | ([$g[0].features[].scenarios[] | {key: .id, value: .title}] | from_entries) as $t
  | def n($s): [$r.results[] | select(.status == $s)] | length;
  "**Test results** · \($r.tester) · \($r.date)", "",
  "- Works: \(n("pass")) · \($dw): \(n("fail")) · \($ct): \(n("blocked")) · Not tested: \(n("not-tested"))",
  ($filed[] | "- \($dw): \($t[.scenario]) → #\(.iid)"),
  ($r.results[] | select(.status == "blocked") | "- \($ct): \($t[.scenario])" + (if (.comment // "") != "" then " — \(.comment)" else "" end))
' > "$summary"
"$BIN/tracker/gitlab.sh" comment --repo "$REPO" --iid "$EPIC" --body-file "$summary" >/dev/null ||
  { echo "test-results: could not post the summary on #$EPIC" >&2; exit 1; }
cat "$summary"
