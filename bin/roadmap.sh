#!/usr/bin/env bash
# The roadmap: backlog features placed into sprints by dependency and capacity, MVP first.
#
#   roadmap.sh propose --repo R [--start N] [--capacity H] [--write]
#       Places every backlog feature not already in a sprint numbered below N into sprints
#       N, N+1, ... : MVP features first, each after the features it depends on, each sprint
#       within H hours (default: sprint.capacity_hours). Sprints below N are kept as they are,
#       so re-planning at sprint close only moves what is still ahead. A goal is kept when its
#       sprint keeps the same features. Prints the roadmap; --write saves .compasso/roadmap.yaml.
#   roadmap.sh check --repo R         capacity, dependency order, the MVP line, a goal per sprint
#   roadmap.sh next  --repo R         the next sprint to plan (after the one in plan.yaml), with its
#                                     features as the backlog describes them -> JSON
# Exit: 0 | 1 invalid (check) or the backlog does not pass backlog-check | 2 usage | 3 nothing to plan
set -u

BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CMD="${1:-}"; shift || true
REPO="." START="" CAP="" WRITE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --start) START="$2"; shift 2 ;;
    --capacity) CAP="$2"; shift 2 ;;
    --write) WRITE=1; shift ;;
    *) echo "roadmap: unknown argument '$1'" >&2; exit 2 ;;
  esac
done
B="$REPO/.compasso/backlog.yaml" RM="$REPO/.compasso/roadmap.yaml" PLAN="$REPO/.compasso/plan.yaml"
"$BIN/backlog-check.sh" --repo "$REPO" >/dev/null || { echo "roadmap: the backlog does not pass backlog-check - run bin/backlog-check.sh --repo $REPO" >&2; exit 1; }
backlog="$(yq -o=json . "$B")"
old=null; [ -f "$RM" ] && old="$(yq -o=json . "$RM")"
planned() { [ -f "$PLAN" ] && yq -r '.epic.sprint.number // ""' "$PLAN" 2>/dev/null; }

case "$CMD" in
  propose)
    if [ -z "$START" ]; then p="$(planned)"; if [ -n "$p" ]; then START=$((p + 1)); else START=1; fi; fi
    [ -n "$CAP" ] || CAP="$("$BIN/config.sh" get --repo "$REPO" .sprint.capacity_hours)"
    out="$(jq -n --argjson b "$backlog" --argjson r "$old" --argjson cap "$CAP" --argjson start "$START" \
      '{b: $b, r: $r, cap: $cap, start: $start, mode: "propose"}' | jq -f "$BIN/roadmap.jq")" || exit 1
    if [ "$WRITE" -eq 1 ]; then
      printf '%s' "$out" | yq -P '.' > "$RM" || exit 1
      echo "roadmap: wrote .compasso/roadmap.yaml"
    fi
    jq -r --argjson b "$backlog" '
      ($b.features | map({key: .key, value: .}) | from_entries) as $by
      | .mvp_sprint as $m
      | .sprints[] | "S\(.number)\(if .number == $m then " (MVP)" else "" end) · \(.hours)h of \($cap // "")\(if .goal != "" then " · \(.goal)" else "" end)",
        (.features[] | "  \(.) \($by[.].title) · \($by[.].size_h)h\(if $by[.].mvp then "" else " · after MVP" end)")' --argjson cap "$CAP" <<<"$out" ;;
  check)
    [ -f "$RM" ] || { echo "roadmap: no .compasso/roadmap.yaml - run /compasso:roadmap" >&2; exit 3; }
    res="$(jq -n --argjson b "$backlog" --argjson r "$old" '{b: $b, r: $r, cap: 0, start: 0, mode: "check"}' | jq -f "$BIN/roadmap.jq")" || exit 1
    jq -r '(.errors[] | "ERROR  \(.)"), (.notes[] | "note   \(.)")' <<<"$res"
    [ "$(jq '.errors | length' <<<"$res")" -eq 0 ] ;;
  next)
    [ -f "$RM" ] || { echo "roadmap: no .compasso/roadmap.yaml - run /compasso:roadmap" >&2; exit 3; }
    p="$(planned)"; [ -n "$p" ] || p=-1
    out="$(jq -n --argjson b "$backlog" --argjson r "$old" --argjson p "$p" '
      ($b.features | map({key: .key, value: .}) | from_entries) as $by
      | [$r.sprints[] | select(.number > $p)] | sort_by(.number) | .[0] // empty
      | . + {mvp: (.number == $r.mvp_sprint), features: [.features[] | $by[.]]}')" || exit 1
    [ -n "$out" ] || { echo "roadmap: every sprint in the roadmap is planned - refine it with /compasso:roadmap" >&2; exit 3; }
    printf '%s\n' "$out" ;;
  *) echo "usage: roadmap.sh propose|check|next --repo R ..." >&2; exit 2 ;;
esac
