#!/usr/bin/env bash
# Strict orchestration: a budget of agent runs for one flow run (a story, a plan, a review...).
#
#   budget.sh claim --repo R --run DIR --role ROLE   before every dispatch of an agent, and before
#                                                    continuing one: records the run, or refuses it.
#                                                    On Claude Code the hook claims (--hook) and a claim by
#                                                    hand is refused: it would spend a second run
#   budget.sh show  --repo R --run DIR               runs used and left, per role
#   budget.sh rework --repo R --run DIR --iid N      the story came back on its open merge request: its rework
#                                                    starts a new budget (the spent one stays in DIR/budget-<n>.jsonl).
#                                                    Refused while the story is being built (compasso::building)
#   budget.sh reset --run DIR [--role ROLE]          start the budget again, or one role's: a person's decision only
#
# The limits are limits.agent_runs in .compasso/project.yaml: per role, and a total for every role
# together; in stage: mvp only mvp_total (default 40), for every role together. Claims are kept in
# DIR/budget.jsonl, so a flow that is restarted continues the same budget instead of starting afresh. With each agent's own turn limit (maxTurns), the work of a flow run is
# bounded: no agent loops without end, and none can start another.
# Exit: 0 claimed | 3 refused (the flow stops and hands back) | 1 usage or config
set -u
case "${1:-}" in -h|--help) sed -n '2,/^set -u/s/^# \{0,1\}//p' "$0"; exit 0 ;; esac   # the header above is the help

BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CMD="${1:-}"; shift || true
REPO="." RUN="" ROLE="" HOOK=0 IID=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --run) RUN="$2"; shift 2 ;;
    --role) ROLE="$2"; shift 2 ;;
    --hook) HOOK=1; shift ;;
    --iid) IID="$2"; shift 2 ;;
    *) echo "budget: unknown argument '$1'" >&2; exit 1 ;;
  esac
done
[ -n "$RUN" ] || { echo "budget: --run is required" >&2; exit 1; }
LEDGER="$RUN/budget.jsonl"
limits() { # in mvp only the total applies: mvp_total
  "$BIN/config.sh" validate --repo "$REPO" >/dev/null || exit 1
  yq -o=json '.' "$REPO/.compasso/project.yaml" | jq '.limits.agent_runs as $l |
    if .stage == "mvp" then {total: ($l.mvp_total // 40), roles: ($l | del(.total, .mvp_total) | keys)} else $l | del(.mvp_total) end'
}
used() { [ -f "$LEDGER" ] && jq -s --arg r "${1:-}" 'if $r == "" then length else map(select(.role == $r)) | length end' "$LEDGER" || echo 0; }

case "$CMD" in
  claim)
    [ -n "$ROLE" ] || { echo "budget: claim needs --role" >&2; exit 1; }
    # Claude Code sets CLAUDECODE in its sessions' commands; Codex claims by hand, as its hook only checks
    [ "${CLAUDECODE:-}" != 1 ] || [ "$HOOK" -eq 1 ] ||
      { echo "budget: not claimed - on Claude Code the hook claims the budget when compasso:$ROLE is dispatched (with the run folder in its prompt); a claim by hand would spend a second run" >&2; exit 1; }
    lim="$(limits)"
    cap="$(jq -r --arg r "$ROLE" 'if .roles then (if .roles | index($r) then "none" else empty end) else .[$r] // empty end' <<<"$lim")"
    [ -n "$cap" ] && [ "$ROLE" != total ] || { echo "budget: unknown role '$ROLE'" >&2; exit 1; }
    total="$(jq -r .total <<<"$lim")"; n="$(used "$ROLE")"; t="$(used)"
    if [ "$cap" != none ] && [ "$n" -ge "$cap" ]; then
      echo "budget: STOP - $ROLE has run $n times in this flow run (limit $cap). Hand back to a person; only a person resets the budget (bin/budget.sh reset --run $RUN)." >&2; exit 3
    fi
    if [ "$t" -ge "$total" ]; then
      echo "budget: STOP - $t agent runs in this flow run (limit $total). Hand back to a person; only a person resets the budget (bin/budget.sh reset --run $RUN)." >&2; exit 3
    fi
    mkdir -p "$RUN" && jq -cn --arg r "$ROLE" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{role: $r, at: $at}' >> "$LEDGER" || exit 1
    if [ "$cap" = none ]; then echo "budget: $ROLE run $((n + 1)) (all roles: $((t + 1)) of $total)"
    else echo "budget: $ROLE run $((n + 1)) of $cap (all roles: $((t + 1)) of $total)"; fi ;;
  show)
    lim="$(limits)"
    jq -r --argjson u "$( [ -f "$LEDGER" ] && jq -s 'group_by(.role) | map({key: .[0].role, value: length}) | from_entries' "$LEDGER" || echo '{}')" '
      if .roles then .roles[] | "\(.): \($u[.] // 0)"
      else to_entries[] | select(.key != "total") | "\(.key): \($u[.key] // 0) of \(.value)" end' <<<"$lim"
    echo "all roles: $(used) of $(jq -r .total <<<"$lim")" ;;
  rework)
    [ -n "$IID" ] || { echo "budget: rework needs --iid" >&2; exit 1; }
    "$BIN/tracker.sh" mr-of --repo "$REPO" --iid "$IID" >/dev/null 2>&1 ||
      { echo "budget: #$IID has no open merge request: there is no rework to start, and the budget continues" >&2; exit 1; }
    s="$("$BIN/tracker.sh" story --repo "$REPO" --iid "$IID")" || exit 1
    ! jq -e '.labels | index("compasso::building")' <<<"$s" >/dev/null ||
      { echo "budget: #$IID is being built: its budget continues; a new one starts only when the tech lead sends it back" >&2; exit 1; }
    [ -f "$LEDGER" ] || { echo "budget: nothing spent yet in $RUN"; exit 0; }
    n=1; while [ -f "$RUN/budget-$n.jsonl" ]; do n=$((n + 1)); done
    mv "$LEDGER" "$RUN/budget-$n.jsonl" && echo "budget: the rework of #$IID starts a new budget; the spent one is kept in $RUN/budget-$n.jsonl" ;;
  reset)
    if [ -n "$ROLE" ]; then
      [ -f "$LEDGER" ] || { echo "budget: nothing to reset in $RUN"; exit 0; }
      jq -c --arg r "$ROLE" 'select(.role != $r)' "$LEDGER" > "$LEDGER.tmp" && mv "$LEDGER.tmp" "$LEDGER" && echo "budget: $ROLE reset for $RUN"
    else
      rm -f "$LEDGER" && echo "budget: reset for $RUN"
    fi ;;
  *) echo "usage: budget.sh claim|show|rework|reset --run DIR ..." >&2; exit 1 ;;
esac
