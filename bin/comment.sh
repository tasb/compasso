#!/usr/bin/env bash
# Render the feature flow's comments in the approved formats.
#
#   comment.sh qa   --file QA.json                      one Questions and answers comment
#   comment.sh plan --repo R --feature F-1 --approver U --security-file S [--date D]
#
# QA.json: {round, user, date, items: [{question, answer}]}
# plan: rows come from .compasso/plan.yaml (the feature's stories, with their GitLab
# iids), the critical path from plan-check on that feature alone; S holds the
# security review's result as markdown ("no findings" or one bullet per finding).
# Exit: 0 | 1 input problem
set -u

BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CMD="${1:-}"; shift || true
REPO="." FILE="" FEATURE="" APPROVER="" SECURITY="" DATE="$(date +%Y-%m-%d)"
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --file) FILE="$2"; shift 2 ;;
    --feature) FEATURE="$2"; shift 2 ;;
    --approver) APPROVER="$2"; shift 2 ;;
    --security-file) SECURITY="$2"; shift 2 ;;
    --date) DATE="$2"; shift 2 ;;
    *) echo "comment: unknown argument '$1'" >&2; exit 1 ;;
  esac
done

case "$CMD" in
  qa)
    [ -f "$FILE" ] || { echo "comment: qa needs --file" >&2; exit 1; }
    jq -e '(.items | length) > 0 and .round and .user and .date' "$FILE" >/dev/null ||
      { echo "comment: $FILE needs round, user, date and at least one item" >&2; exit 1; }
    jq -r '
      "**Questions and answers** · round \(.round) · answered by @\(.user) in the agent, \(.date)",
      "",
      (.items | to_entries[] | "\(.key + 1). \(.value.question)\\\n   → \(.value.answer)"),
      "",
      "<!-- compasso:qa round=\(.round) -->"' "$FILE"
    ;;
  plan)
    plan="$REPO/.compasso/plan.yaml"
    [ -f "$plan" ] && [ -n "$FEATURE" ] && [ -n "$APPROVER" ] && [ -f "$SECURITY" ] ||
      { echo "comment: plan needs the plan file, --feature, --approver and --security-file" >&2; exit 1; }
    one="$(mktemp)"; trap 'rm -f "$one"' EXIT
    # the feature alone: dependencies outside it become #iid references, and only its blockers stay
    yq -o=json '.' "$plan" | jq --arg k "$FEATURE" '
      ([.features[].stories[] | {key: .key, value: .gitlab}] | from_entries) as $iid
      | (.features | map(select(.key == $k))) as $f
      | ([$f[].stories[].key]) as $mine
      | .features = ($f | map(.stories |= map(.depends_on = ((.depends_on // []) | map(
          if startswith("#") or (. as $d | $mine | index($d)) then . else "#\($iid[.])" end)))))
      | ([.features[].stories[] | (.blocked_by // [])[]]) as $used
      | .blockers = ((.blockers // []) | map(select(.key as $b | $used | index($b))))' > "$one"
    [ "$(yq '.features | length' "$one")" -eq 1 ] || { echo "comment: no feature $FEATURE in $plan" >&2; exit 1; }
    check="$("$BIN/plan-check.sh" --repo "$REPO" --plan "$one" --json)" || { echo "comment: the plan does not pass plan-check" >&2; exit 1; }
    jq -rn --argjson p "$(yq -o=json '.' "$plan")" --argjson c "$check" --arg k "$FEATURE" \
          --arg who "$APPROVER" --arg date "$DATE" --rawfile sec "$SECURITY" '
      ([$p.features[].stories[] | {key: .key, value: .gitlab}] + [($p.blockers // [])[] | {key: .key, value: .gitlab}] | from_entries) as $iid
      | def ref: if startswith("#") then . else "#\($iid[.] // .)" end;
      ($p.features[] | select(.key == $k)) as $f
      | "**Plan** · \($f.stories | length) \(if ($f.stories | length) == 1 then "story" else "stories" end) · \($c.totals.epic)h · critical path \($c.critical.hours)h",
        "",
        "| Story | h | Owner | Depends on |",
        "|---|---|---|---|",
        ($f.stories[] | "| #\(.gitlab // "?") \(.title) | \(.estimate_h) | \(.owner) | "
           + ((((.depends_on // []) + (.blocked_by // [])) | map(ref) | join(", ")) as $d | if $d == "" then "—" else $d end) + " |"),
        "",
        ($sec | sub("\\s+$"; "")) as $s | (if ($s | startswith("- ")) then "**Security:**\n\($s)" else "**Security:** \($s)" end),
        "",
        "**Approved:** by @\($who) in the agent, \($date)"'
    ;;
  *) echo "usage: comment.sh qa|plan ..." >&2; exit 1 ;;
esac
