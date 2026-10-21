#!/usr/bin/env bash
# Decide from a findings file whether review still blocks.
#
#   review-gate.sh --findings F [--for review|merge] [--comment]
#
# F is a JSON array of {by: reviewer|security, severity: blocker|major|minor,
# status: open|fixed|followup, verified_by?, needs?, file?, line?, summary, fix?}.
# needs names who the fix depends on when it is not the developer (a person, an outside admin):
# only such a minor finding becomes a follow-up; every other finding is fixed in the story.
# A security finding counts as resolved only when security itself verified it
# (verified_by: security), whoever changed its status: fixed, or followup (security
# accepts the deferral), which only a minor finding with needs may be.
#   review: blocks while any blocker or major finding is open
#   merge:  also blocks while any other finding is open, minors too, except a reviewer's minor with needs
# --comment prints every finding as a merge request comment instead (same exit codes).
# Exit: 0 clear | 1 blocked (open findings listed) | 2 malformed findings
set -u
case "${1:-}" in -h|--help) sed -n '2,/^set -u/s/^# \{0,1\}//p' "$0"; exit 0 ;; esac   # the header above is the help

BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
F="" FOR=review COMMENT=0 REPO="."
while [ $# -gt 0 ]; do
  case "$1" in
    --findings) F="$2"; shift 2 ;;
    --for) FOR="$2"; shift 2 ;;
    --repo) REPO="$2"; shift 2 ;;   # for --comment: the project's language
    --comment) COMMENT=1; shift ;;
    *) echo "review-gate: unknown argument '$1'" >&2; exit 2 ;;
  esac
done
case "$FOR" in review|merge) : ;; *) echo "review-gate: --for must be review or merge" >&2; exit 2 ;; esac
[ -f "$F" ] || { echo "review-gate: no findings file '$F'" >&2; exit 2; }

bad="$(jq -r 'if type != "array" then "not an array" else
  (to_entries[] | .key as $i | .value
   | select((.by | IN("reviewer", "security") | not)
         or (.severity | IN("blocker", "major", "minor") | not)
         or (.status | IN("open", "fixed", "followup") | not)
         or ((.summary // "") == ""))
   | "finding \($i + 1) needs by, severity, status and summary")
  end' "$F" 2>/dev/null)" || { echo "review-gate: $F is not valid JSON" >&2; exit 2; }
[ -z "$bad" ] || { printf 'review-gate: %s\n' "$bad" >&2; exit 2; }

open="$(jq -r --arg for "$FOR" '
  # someone else fixes it; a follow-up filed before needs was asked for stays filed
  def elsewhere: .severity == "minor" and ((.needs // "") != "" or .followup_iid != null);
  map(. + {open: (if .by == "security" then (.verified_by == "security" and (.status == "fixed" or (.status == "followup" and elsewhere))) | not
          else .status == "open" and (elsewhere | not) end)})
  | map(select(.open and (.severity != "minor" or $for == "merge")))
  | .[] | "  - [\(.by)/\(.severity)] \(.summary)" + (if .file then " (\(.file)\(if .line then ":\(.line)" else "" end))" else "" end)' "$F")"

if [ "$COMMENT" -eq 1 ]; then
  L="$("$BIN/locale.sh" --repo "$REPO")" || exit 2
  jq -r -L "$BIN" --argjson L "$L" --arg blocks "$([ -n "$open" ] && echo yes || echo no)" 'include "i18n";
    tf("review_title"; {n: length}), "",
    (if length == 0 then "- " + t("no_findings_cap") else
      (sort_by({blocker: 0, major: 1, minor: 2}[.severity]) | .[]
       | "- [\(t("by_" + .by))/\(t("sev_" + .severity))] \(.summary)"
         + (if .file then " (`\(.file)\(if .line then ":\(.line)" else "" end)`)" else "" end)
         + (if .fix then " — \(t("fix")): \(.fix)" else "" end)
         + (if .status != "open" then " — \(t("st_" + .status))" else "" end)) end),
    "", "**\(t("blocks")):** \(t($blocks))"' "$F"
  [ -z "$open" ]; exit $?
fi

if [ -n "$open" ]; then
  printf 'review-gate: open findings block the %s:\n%s\n' "$FOR" "$open"
  exit 1
fi
echo "review-gate: clear for $FOR"
