#!/usr/bin/env bash
# Follow-ups filed before 3.1.0 went to no sprint (in a team project, also without labels), so the
# tech lead's queue never saw them. List the open ones, and with --apply move each into the sprint,
# where they are assigned like any story.
#
#   followups.sh --repo R [--milestone S<n>] [--apply]    the sprint defaults to .compasso/plan.yaml's
#
# Exit: 0 | 1 a tracker step failed or no such sprint | 2 usage | 6 this persona may not move work
set -u
case "${1:-}" in -h|--help) sed -n '2,/^set -u/s/^# \{0,1\}//p' "$0"; exit 0 ;; esac   # the header above is the help

BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="." MS="" APPLY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --milestone) MS="$2"; shift 2 ;;
    --apply) APPLY=1; shift ;;
    *) echo "followups: unknown argument '$1'" >&2; exit 2 ;;
  esac
done
[ -n "$MS" ] || MS="S$(yq -r '.epic.sprint.number // ""' "$REPO/.compasso/plan.yaml" 2>/dev/null)"
[ "$MS" != S ] || { echo "followups: needs --milestone or a .compasso/plan.yaml" >&2; exit 2; }

list="$("$BIN/tracker.sh" followups --repo "$REPO")" || exit $?
jq -r --arg ms "$MS" 'if length == 0 then "followups: no open follow-up outside a sprint"
  else "followups: \(length) open in no sprint, for \($ms):", (.[] | "  #\(.iid) \(.title) (from #\(.story))") end' <<<"$list"
[ "$(jq length <<<"$list")" -gt 0 ] || exit 0
if [ "$APPLY" -eq 0 ]; then echo "followups: nothing changed; run again with --apply to move them into $MS"; exit 0; fi
for i in $(jq -r '.[].iid' <<<"$list"); do
  "$BIN/tracker.sh" set-milestone --repo "$REPO" --iid "$i" --milestone "$MS" || exit $?
done
echo "followups: moved into $MS"
