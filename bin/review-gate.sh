#!/usr/bin/env bash
# Decide from a findings file whether review still blocks.
#
#   review-gate.sh --findings F [--for review|merge] [--comment]
#
# F is a JSON array of {by: reviewer|security, severity: blocker|major|minor,
# status: open|fixed|followup, verified_by?, file?, line?, summary, fix?}.
# A security finding counts as resolved only when security itself verified it
# (verified_by: security), whoever changed its status.
#   review: blocks while any blocker or major finding is open
#   merge:  also blocks while any security finding, of any severity, is open
# --comment prints every finding as a merge request comment instead (same exit codes).
# Exit: 0 clear | 1 blocked (open findings listed) | 2 malformed findings
set -u

F="" FOR=review COMMENT=0
while [ $# -gt 0 ]; do
  case "$1" in
    --findings) F="$2"; shift 2 ;;
    --for) FOR="$2"; shift 2 ;;
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
  map(. + {open: (if .by == "security" then .verified_by != "security" or .status == "open" else .status == "open" end)})
  | map(select(.open and (.severity != "minor" or ($for == "merge" and .by == "security"))))
  | .[] | "  - [\(.by)/\(.severity)] \(.summary)" + (if .file then " (\(.file)\(if .line then ":\(.line)" else "" end))" else "" end)' "$F")"

if [ "$COMMENT" -eq 1 ]; then
  jq -r --arg blocks "$([ -n "$open" ] && echo yes || echo no)" '
    "**Review** · \(length) findings", "",
    (if length == 0 then "- No findings" else
      (sort_by({blocker: 0, major: 1, minor: 2}[.severity]) | .[]
       | "- [\(.by)/\(.severity)] \(.summary)"
         + (if .file then " (`\(.file)\(if .line then ":\(.line)" else "" end)`)" else "" end)
         + (if .fix then " — fix: \(.fix)" else "" end)
         + (if .status != "open" then " — \(.status)" else "" end)) end),
    "", "**Blocks:** \($blocks)"' "$F"
  [ -z "$open" ]; exit $?
fi

if [ -n "$open" ]; then
  printf 'review-gate: open findings block the %s:\n%s\n' "$FOR" "$open"
  exit 1
fi
echo "review-gate: clear for $FOR"
