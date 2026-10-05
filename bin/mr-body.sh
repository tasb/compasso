#!/usr/bin/env bash
# Build a merge request description in the approved format from a story run.
#
#   mr-body.sh --story F --run DIR [--repo R]
#
# Written in the project's language (bin/locale.sh); "Closes #<iid>" stays as it is: it is the
# keyword GitLab and GitHub close the story with.
# Reads F (from `gitlab.sh story`), DIR/changes.md (one behaviour change per line,
# written by the shipper), DIR/findings.json and DIR/coverage.json.
# Exit: 0 | 2 missing input
set -u

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
for f in "$STORY" "$RUN/changes.md" "$RUN/findings.json"; do
  [ -f "$f" ] || { echo "mr-body: missing $f" >&2; exit 2; }
done
cov="$RUN/coverage.json"; [ -f "$cov" ] || cov=/dev/null
risk="$RUN/risk.json"; [ -f "$risk" ] || risk=/dev/null

L="$("$BIN/locale.sh" --repo "$REPO")" || exit 2
jq -rn -L "$BIN" --argjson L "$L" --slurpfile s "$STORY" --slurpfile f "$RUN/findings.json" --rawfile changes "$RUN/changes.md" \
  --slurpfile c <(cat "$cov"; [ "$cov" = /dev/null ] && echo '{"status":"not-measured"}') \
  --slurpfile k <(cat "$risk"; [ "$risk" = /dev/null ] && echo null) 'include "i18n";
  $s[0] as $s | $f[0] as $f | $c[0] as $c | $k[0] as $k
  | ($f | map(select(.by == "reviewer"))) as $r
  | ($f | map(select(.by == "security"))) as $sec
  | "Closes #\($s.iid)",
    "",
    "## \(t("changes"))",
    ($changes | split("\n") | map(sub("^-\\s*"; "") | select(. != "")) | map("- " + .) | join("\n")),
    "",
    "## \(t("how_to_test"))",
    ($s.story.verify | to_entries | map("\(.key + 1). `\(.value)`") | join("\n")),
    "",
    "## \(t("review"))",
    "- \(t("reviewer")): " + (
        ([$r[] | select(.status == "fixed")] | length) as $fixed
        | ([$r[] | select(.status == "followup") | .followup_iid | select(. != null) | "#\(.)"]) as $fu
        | ([$r[] | select(.status == "open")] | length) as $open
        | [ (if $fixed > 0 then tf("findings_fixed"; {n: $fixed}) else empty end),
            (if ($fu | length) > 0 then tf("minors_to"; {list: ($fu | join(", "))}) else empty end),
            (if $open > 0 then tf("n_open"; {n: $open}) else empty end) ]
        | if length == 0 then t("no_findings") else join(" · ") end),
    "- \(t("security")): " + (if ($sec | length) == 0 then t("no_findings")
        else "\n" + ($sec | map("  - [\(t("sev_" + .severity))] \(.summary) — " +
          (if .verified_by == "security" and .status != "open" then t("fixed_verified") else t("open") end)) | join("\n")) end),
    "- \(t("coverage")): " + (if $c.status == "ok" then tf("cov_ok"; {p: $c.percent, min: $c.min})
        elif $c.status == "below" then tf("cov_below"; {p: $c.percent, min: $c.min, list: ($c.uncovered | join(", "))})
        else t("not_measured") end),
    (if $k == null then empty elif $k.level == "low"
      then "- \(t("merge")): " + tf("merge_low"; {lines: $k.changed_lines, files: $k.files})
      else "- \(t("merge")): " + tf("merge_person"; {reasons: ($k.reasons | join("; "))}) end),
    "",
    "<!-- compasso:story=\($s.story.key // $s.iid) -->"'
