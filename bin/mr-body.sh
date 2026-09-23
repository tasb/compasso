#!/usr/bin/env bash
# Build a merge request description in the approved format from a story run.
#
#   mr-body.sh --story F --run DIR
#
# Reads F (from `gitlab.sh story`), DIR/changes.md (one behaviour change per line,
# written by the shipper), DIR/findings.json and DIR/coverage.json.
# Exit: 0 | 2 missing input
set -u

STORY="" RUN=""
while [ $# -gt 0 ]; do
  case "$1" in
    --story) STORY="$2"; shift 2 ;;
    --run) RUN="$2"; shift 2 ;;
    *) echo "mr-body: unknown argument '$1'" >&2; exit 2 ;;
  esac
done
for f in "$STORY" "$RUN/changes.md" "$RUN/findings.json"; do
  [ -f "$f" ] || { echo "mr-body: missing $f" >&2; exit 2; }
done
cov="$RUN/coverage.json"; [ -f "$cov" ] || cov=/dev/null

jq -rn --slurpfile s "$STORY" --slurpfile f "$RUN/findings.json" --rawfile changes "$RUN/changes.md" \
  --slurpfile c <(cat "$cov"; [ "$cov" = /dev/null ] && echo '{"status":"not-measured"}') '
  $s[0] as $s | $f[0] as $f | $c[0] as $c
  | ($f | map(select(.by == "reviewer"))) as $r
  | ($f | map(select(.by == "security"))) as $sec
  | "Closes #\($s.iid)",
    "",
    "## Changes",
    ($changes | split("\n") | map(sub("^-\\s*"; "") | select(. != "")) | map("- " + .) | join("\n")),
    "",
    "## How to test",
    ($s.story.verify | to_entries | map("\(.key + 1). `\(.value)`") | join("\n")),
    "",
    "## Review",
    "- Reviewer: " + (
        ([$r[] | select(.status == "fixed")] | length) as $fixed
        | ([$r[] | select(.status == "followup") | .followup_iid | select(. != null) | "#\(.)"]) as $fu
        | ([$r[] | select(.status == "open")] | length) as $open
        | [ (if $fixed > 0 then "\($fixed) findings fixed" else empty end),
            (if ($fu | length) > 0 then "minors → \($fu | join(", "))" else empty end),
            (if $open > 0 then "\($open) open" else empty end) ]
        | if length == 0 then "no findings" else join(" · ") end),
    "- Security: " + (if ($sec | length) == 0 then "no findings"
        else "\n" + ($sec | map("  - [\(.severity)] \(.summary) — " +
          (if .verified_by == "security" and .status != "open" then "fixed, verified by security" else "open" end)) | join("\n")) end),
    "- Coverage: " + (if $c.status == "ok" then "\($c.percent)% of changed lines (min \($c.min)%)"
        elif $c.status == "below" then "below min: \($c.percent)% of \($c.min)% · uncovered: \($c.uncovered | join(", "))"
        else "not measured" end),
    "",
    "<!-- compasso:story=\($s.story.key // $s.iid) -->"'
