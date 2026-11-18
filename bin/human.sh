#!/usr/bin/env bash
# The one way an agent reaches a person: a needs::human issue on the tracker.
#
#   human.sh ask --repo R --key K [--story N] --title T --from F
#
# F is JSON: {need, why: [...], steps: [...], meanwhile}. The issue says what is needed, why (the
# evidence), the numbered steps - closing the issue is always the last one - and what the agent does
# meanwhile. It goes to people.ask; the story N, when given, gets needs::human, so no job picks it up
# until the person closes the issue (bin/next.jq). Asking again with the same key and story updates
# the open issue. Prints {iid, web_url, created}.
#
# Exit: 0 ok | 1 usage, an incomplete question or a tracker failure
set -u
case "${1:-}" in -h|--help) sed -n '2,/^set -u/s/^# \{0,1\}//p' "$0"; exit 0 ;; esac   # the header above is the help

BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CMD="${1:-}"; shift || true
REPO="." KEY="" STORY="" TITLE="" FROM=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --key) KEY="$2"; shift 2 ;;
    --story) STORY="$2"; shift 2 ;;
    --title) TITLE="$2"; shift 2 ;;
    --from) FROM="$2"; shift 2 ;;
    *) echo "human: unknown argument '$1'" >&2; exit 1 ;;
  esac
done
[ "$CMD" = ask ] || { echo "usage: human.sh ask --repo R --key K [--story N] --title T --from F" >&2; exit 1; }
[ -n "$KEY" ] && [ -n "$TITLE" ] && [ -f "$FROM" ] || { echo "human: ask needs --key, --title and --from F (a file)" >&2; exit 1; }
case "$KEY$STORY" in *[!A-Za-z0-9_.-]*) echo "human: --key and --story take letters, digits, . _ -" >&2; exit 1 ;; esac

q="$(jq -c . "$FROM" 2>/dev/null)" || { echo "human: $FROM is not JSON" >&2; exit 1; }
for k in need why steps meanwhile; do
  jq -e --arg k "$k" '.[$k] | if type == "array" then length > 0 and all(.[]; type == "string" and . != "") else type == "string" and . != "" end' \
    <<<"$q" >/dev/null || { echo "human: the question needs $k" >&2; exit 1; }
done

LOC="$("$BIN/locale.sh" --repo "$REPO")" || exit 1
body="$(mktemp)"; trap 'rm -f "$body"' EXIT
jq -r -L "$BIN" --argjson L "$LOC" --arg key "$KEY" --arg story "$STORY" 'include "i18n";
  "<!-- compasso:ask story=\($story) key=\($key) -->",
  "**\(t("ask_need"))** \(.need)",
  (if $story == "" then empty else "**\(t("ask_story"))** #\($story)" end),
  "", "**\(t("ask_why"))**", (.why[] | "- \(.)"),
  "", "**\(t("ask_steps"))**", ((.steps + [t("ask_close")]) | to_entries[] | "\(.key + 1). \(.value)"),
  "", "**\(t("ask_meanwhile"))** \(.meanwhile)"' <<<"$q" > "$body"

"$BIN/tracker.sh" human-ask --repo "$REPO" --key "$KEY" ${STORY:+--iid "$STORY"} --title "$TITLE" --body-file "$body"
