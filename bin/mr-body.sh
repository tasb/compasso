#!/usr/bin/env bash
# Build a merge request description from a story run: what changed, how to test it and, when it was
# measured (stage production), the changed-line coverage. The review comes later, from the tech lead.
#
#   mr-body.sh --story F --run DIR [--repo R]
#
# Written in the project's language (bin/locale.sh); "Closes #<iid>" stays as it is: it is the
# keyword GitLab and GitHub close the story with.
# Reads F (from `tracker.sh story`), DIR/changes.md (one behaviour change per line) and DIR/coverage.json.
# Exit: 0 | 2 missing input
set -u
case "${1:-}" in -h|--help) sed -n '2,/^set -u/s/^# \{0,1\}//p' "$0"; exit 0 ;; esac   # the header above is the help

BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STORY="" RUN="" REPO="."
while [ $# -gt 0 ]; do
  case "$1" in
    --story) STORY="$2"; shift 2 ;;
    --run) RUN="$2"; shift 2 ;;
    --repo) REPO="$2"; shift 2 ;;
    *) echo "mr-body: unknown argument '$1'" >&2; exit 2 ;;
  esac
done
for f in "$STORY" "$RUN/changes.md"; do
  [ -f "$f" ] || { echo "mr-body: missing $f" >&2; exit 2; }
done
cov="$RUN/coverage.json"; [ -f "$cov" ] || cov=/dev/null

L="$("$BIN/locale.sh" --repo "$REPO")" || exit 2
jq -rn -L "$BIN" --argjson L "$L" --slurpfile s "$STORY" --rawfile changes "$RUN/changes.md" \
  --slurpfile c <(cat "$cov"; [ "$cov" = /dev/null ] && echo null) 'include "i18n";
  $s[0] as $s | $c[0] as $c
  | "Closes #\($s.iid)",
    "",
    "## \(t("changes"))",
    ($changes | split("\n") | map(sub("^-\\s*"; "") | select(. != "")) | map("- " + .) | join("\n")),
    "",
    "## \(t("how_to_test"))",
    ($s.story.verify | to_entries | map("\(.key + 1). `\(.value)`") | join("\n")),
    (if $c == null or $c.status == "skipped" then empty else
      "",
      "\(t("coverage")): " + (if $c.status == "ok" then tf("cov_ok"; {p: $c.percent, min: $c.min})
        elif $c.status == "below" then tf("cov_below"; {p: $c.percent, min: $c.min, list: ($c.uncovered | join(", "))})
        else t("not_measured") end) end),
    "",
    "<!-- compasso:story=\($s.story.key // $s.iid) -->"'
