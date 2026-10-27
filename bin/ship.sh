#!/usr/bin/env bash
# Finish a story run without an agent: file each minor finding whose fix needs someone other than
# the developer (its needs: a person, an outside admin) as a story for a person in the sprint; in
# stage mvp, file the story's other open minors as one issue for after the MVP (in no sprint,
# compasso::after-mvp); write the story's metrics and decision record, and commit them with any
# lessons. Every other finding was fixed in the story (review-gate.sh). Each filed finding's
# acceptance line is the one its reviewer wrote; Verify is the repo's test command and the story's.
#
#   ship.sh --repo R --run DIR
#
# DIR/story.json names the story and its feature; DIR/findings.json gets each
# filed minor marked {status: "followup", followup_iid}. The builder has already
# committed the code (DIR/commit-msg.txt) and written DIR/changes.md; DIR/record.json
# (optional) holds the run's decisions, takeaways, constraints and missing points.
# Exit: 0 | 1 a tracker or git step failed | 2 usage or missing input
set -u
case "${1:-}" in -h|--help) sed -n '2,/^set -u/s/^# \{0,1\}//p' "$0"; exit 0 ;; esac   # the header above is the help

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
stage="$("$BIN/config.sh" get --repo "$REPO" .stage)"
# Verify of anything filed: commands that run, never a description of one
verify="$(jq -c --arg t "$test_cmd" '[$t, (.story.verify // [])[]] | map(select(. != "")) | reduce .[] as $c ([]; if index([$c]) then . else . + [$c] end)' "$RUN/story.json")"
[ "$verify" != "[]" ] || { echo "ship: no test command and no story Verify - a filed finding would have nothing to run" >&2; exit 2; }
L="$("$BIN/locale.sh" --repo "$REPO")" || exit 2   # follow-ups in the project's language

# minors someone else fixes, not filed yet -> stories for a person, under the feature (or the story), in its sprint
for id in $(jq -r 'to_entries[] | select(.value.severity == "minor" and (.value.needs // "") != "" and (
    (.value.by == "reviewer" and .value.status == "open")
    or (.value.by == "security" and .value.status == "followup" and .value.verified_by == "security" and .value.followup_iid == null))) | .key' "$RUN/findings.json"); do
  f="$(jq -c ".[$id]" "$RUN/findings.json")"
  body="$RUN/followup-$id.md"
  jq -r -L "$BIN" --argjson L "$L" --argjson verify "$verify" --argjson story "$iid" 'include "i18n";
    "**\(md("as"))** \(.needs) **\(md("i_want"))** \(.fix // t("followup_want")) **\(md("so_that"))** " + tf("followup_so"; {summary: (.summary | ascii_downcase | sub("\\.$"; ""))}) + ".",
    "", "## \(md("acceptance"))", "- [ ] \(.acceptance)",
    "", "## \(md("verify"))", ($verify[] | "- `\(.)`"),
    "", "**\(md("tests")):** unit", "", "<!-- compasso:followup story=\($story) -->"' <<<"$f" > "$body"
  title="$(jq -r '.summary | if length > 80 then .[0:77] + "..." else . end' <<<"$f")"
  new="$("$BIN/tracker.sh" followup --repo "$REPO" --parent "${feature:-$iid}" --title "$title" \
          --body-file "$body" --labels owner::human)" || { echo "ship: could not file the follow-up for finding $id" >&2; exit 1; }
  jq --argjson i "$id" --argjson n "$new" '.[$i] += {status: "followup", followup_iid: $n}' "$RUN/findings.json" > "$RUN/findings.new" \
    && mv "$RUN/findings.new" "$RUN/findings.json"
  echo "ship: minor finding filed for $(jq -r .needs <<<"$f") as #$new"
done

# mvp: the open minors nobody else fixes wait for after the MVP, together, in no sprint
if [ "$stage" = mvp ]; then
  later="$(jq -c '[to_entries[] | select(.value.severity == "minor" and .value.followup_iid == null and (.value.needs // "") == ""
      and (if .value.by == "security" then (.value.verified_by == "security" and .value.status == "fixed") | not else .value.status == "open" end)) | .key]' "$RUN/findings.json")"
  if [ "$later" != "[]" ]; then
    body="$RUN/after-mvp.md"
    jq -r -L "$BIN" --argjson L "$L" --argjson verify "$verify" --argjson later "$later" --slurpfile s "$RUN/story.json" 'include "i18n";
      ($s[0].iid) as $story |
      "**\(md("as"))** \(t("minors_as")) **\(md("i_want"))** \(tf("minors_want"; {story: $story})) **\(md("so_that"))** \(t("minors_so")).",
      "", "## \(md("acceptance"))", (.[$later[]] | "- [ ] \(.acceptance)"),
      "", "## \(md("verify"))", ($verify[] | "- `\(.)`"),
      "", "**\(md("tests")):** unit", "", "<!-- compasso:after-mvp story=\($story) -->"' "$RUN/findings.json" > "$body"
    title="$(jq -r -L "$BIN" --argjson L "$L" 'include "i18n"; tf("minors_title"; {story: .iid, title: .title})' "$RUN/story.json")"
    new="$("$BIN/tracker.sh" followup --repo "$REPO" --parent "${feature:-$iid}" --title "$title" \
            --body-file "$body" --labels compasso::after-mvp --milestone none)" || { echo "ship: could not file the minor findings for after the MVP" >&2; exit 1; }
    jq --argjson later "$later" --argjson n "$new" 'reduce $later[] as $i (.; .[$i] += {status: "followup", followup_iid: $n})' "$RUN/findings.json" > "$RUN/findings.new" \
      && mv "$RUN/findings.new" "$RUN/findings.json"
    echo "ship: $(jq length <<<"$later") minor findings filed for after the MVP as #$new"
  fi
fi

"$BIN/story-metrics.sh" write --run "$RUN" --repo "$REPO" >/dev/null || exit 1
"$BIN/record.sh" story --repo "$REPO" --run "$RUN" >/dev/null || exit 1
git -C "$REPO" add ".compasso/metrics/$iid.json" .compasso/records || exit 1
[ -d "$REPO/docs/learnings" ] && git -C "$REPO" add docs/learnings
if ! git -C "$REPO" diff --cached --quiet >/dev/null; then
  git -C "$REPO" commit -q -m "Record the metrics, decisions and lessons of #$iid" || { echo "ship: could not commit the metrics" >&2; exit 1; }
fi
echo "ship: #$iid ready for its merge request"
