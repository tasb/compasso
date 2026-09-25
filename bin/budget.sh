#!/usr/bin/env bash
# Strict orchestration: a budget of agent runs for one flow run (a story, a plan, a review...).
#
#   budget.sh claim --repo R --run DIR --role ROLE   before every dispatch of an agent, and before
#                                                    continuing one: records the run, or refuses it
#   budget.sh show  --repo R --run DIR               runs used and left, per role
#   budget.sh reset --run DIR                        start the budget again: a person's decision only
#
# The limits are limits.agent_runs in .compasso/project.yaml: per role, and a total for every role
# together. Claims are kept in DIR/budget.jsonl, so a flow that is restarted continues the same budget
# instead of starting afresh. With each agent's own turn limit (maxTurns), the work of a flow run is
# bounded: no agent loops without end, and none can start another.
# Exit: 0 claimed | 3 refused (the flow stops and hands back) | 1 usage or config
set -u

BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CMD="${1:-}"; shift || true
REPO="." RUN="" ROLE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --run) RUN="$2"; shift 2 ;;
    --role) ROLE="$2"; shift 2 ;;
    *) echo "budget: unknown argument '$1'" >&2; exit 1 ;;
  esac
done
[ -n "$RUN" ] || { echo "budget: --run is required" >&2; exit 1; }
LEDGER="$RUN/budget.jsonl"
limits() { "$BIN/config.sh" validate --repo "$REPO" >/dev/null || exit 1; yq -o=json '.limits.agent_runs' "$REPO/.compasso/project.yaml"; }
used() { [ -f "$LEDGER" ] && jq -s --arg r "${1:-}" 'if $r == "" then length else map(select(.role == $r)) | length end' "$LEDGER" || echo 0; }

case "$CMD" in
  claim)
    [ -n "$ROLE" ] || { echo "budget: claim needs --role" >&2; exit 1; }
    lim="$(limits)"
    cap="$(jq -r --arg r "$ROLE" '.[$r] // empty' <<<"$lim")"
    [ -n "$cap" ] && [ "$ROLE" != total ] || { echo "budget: unknown role '$ROLE'" >&2; exit 1; }
    total="$(jq -r .total <<<"$lim")"; n="$(used "$ROLE")"; t="$(used)"
    if [ "$n" -ge "$cap" ]; then
      echo "budget: STOP - $ROLE has run $n times in this flow run (limit $cap). Hand back to a person; only a person resets the budget (bin/budget.sh reset --run $RUN)." >&2; exit 3
    fi
    if [ "$t" -ge "$total" ]; then
      echo "budget: STOP - $t agent runs in this flow run (limit $total). Hand back to a person; only a person resets the budget (bin/budget.sh reset --run $RUN)." >&2; exit 3
    fi
    mkdir -p "$RUN" && jq -cn --arg r "$ROLE" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{role: $r, at: $at}' >> "$LEDGER" || exit 1
    echo "budget: $ROLE run $((n + 1)) of $cap (all roles: $((t + 1)) of $total)" ;;
  show)
    lim="$(limits)"
    jq -r --argjson u "$( [ -f "$LEDGER" ] && jq -s 'group_by(.role) | map({key: .[0].role, value: length}) | from_entries' "$LEDGER" || echo '{}')" '
      to_entries[] | select(.key != "total") | "\(.key): \($u[.key] // 0) of \(.value)"' <<<"$lim"
    echo "all roles: $(used) of $(jq -r .total <<<"$lim")" ;;
  reset)
    rm -f "$LEDGER" && echo "budget: reset for $RUN" ;;
  *) echo "usage: budget.sh claim|show|reset --run DIR ..." >&2; exit 1 ;;
esac
