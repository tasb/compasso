#!/usr/bin/env bash
# Finish a story run without an agent: file the open minor findings as backlog
# stories, write the story's metrics, and commit the metrics and any lessons.
#
#   ship.sh --repo R --run DIR
#
# DIR/story.json names the story and its feature; DIR/findings.json gets each
# filed minor marked {status: "followup", followup_iid}. The builder has already
# committed the code (DIR/commit-msg.txt) and written DIR/changes.md.
# Exit: 0 | 1 a tracker or git step failed | 2 usage or missing input
set -u

BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="." RUN=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --run) RUN="$2"; shift 2 ;;
    *) echo "ship: unknown argument '$1'" >&2; exit 2 ;;
  esac
done
for f in story.json findings.json changes.md; do
  [ -f "$RUN/$f" ] || { echo "ship: missing $RUN/$f" >&2; exit 2; }
done
[ -s "$RUN/changes.md" ] || { echo "ship: $RUN/changes.md is empty - the builder writes one line per behaviour change" >&2; exit 2; }
iid="$(jq -r .iid "$RUN/story.json")"; feature="$(jq -r '.feature // empty' "$RUN/story.json")"
test_cmd="$("$BIN/config.sh" get --repo "$REPO" .commands.test)"

# open minors -> backlog stories under the feature (or under the story when it has no feature)
for id in $(jq -r 'to_entries[] | select(.value.by == "reviewer" and .value.severity == "minor" and .value.status == "open") | .key' "$RUN/findings.json"); do
  f="$(jq -c ".[$id]" "$RUN/findings.json")"
  body="$RUN/followup-$id.md"
  jq -r --arg cmd "$test_cmd" --argjson story "$iid" '
    "**As** a maintainer **I want** \(.fix // "this finding addressed") **so that** \(.summary | ascii_downcase | sub("\\.$"; "")) no longer applies.",
    "", "## Acceptance",
    "- [ ] Given \(if .file then "`\(.file)\(if .line then ":\(.line)" else "" end)`" else "the code from #\($story)" end), When it is reviewed again, Then the finding \"\(.summary)\" no longer applies",
    "", "## Verify", "- `\(if $cmd == "" then "the repo tests" else $cmd end)`",
    "", "**Tests:** unit", "", "<!-- compasso:followup story=\($story) -->"' <<<"$f" > "$body"
  title="$(jq -r '.summary | if length > 80 then .[0:77] + "..." else . end' <<<"$f")"
  new="$("$BIN/tracker.sh" followup --repo "$REPO" --parent "${feature:-$iid}" --title "$title" \
          --body-file "$body" --labels owner::either --milestone none)" || { echo "ship: could not file the follow-up for finding $id" >&2; exit 1; }
  jq --argjson i "$id" --argjson n "$new" '.[$i] += {status: "followup", followup_iid: $n}' "$RUN/findings.json" > "$RUN/findings.new" \
    && mv "$RUN/findings.new" "$RUN/findings.json"
  echo "ship: minor finding filed as #$new"
done

"$BIN/story-metrics.sh" write --run "$RUN" --repo "$REPO" >/dev/null || exit 1
git -C "$REPO" add ".compasso/metrics/$iid.json" || exit 1
[ -d "$REPO/docs/learnings" ] && git -C "$REPO" add docs/learnings
if ! git -C "$REPO" diff --cached --quiet; then
  git -C "$REPO" commit -q -m "Record the metrics and lessons of #$iid" || { echo "ship: could not commit the metrics" >&2; exit 1; }
fi
echo "ship: #$iid ready for its merge request"
