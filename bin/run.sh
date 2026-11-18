#!/usr/bin/env bash
# What cron starts on each agent's machine: one job per run, in a fresh session.
#
#   run.sh lead [--repo R] [--harness claude|codex]
#   run.sh dev --name N [--repo R] [--harness claude|codex]
#
# It first brings the checkout to the default branch as origin has it (fetch, then a fast-forward), so a change
# merged there - the stage, run.* - reaches this run; a checkout with uncommitted changes stays where it is.
# It reads the tracker (tracker.sh snapshot) and picks the role's next job (bin/next.jq). With no job
# it records an idle run and exits: no model starts. An answered question is unblocked here, without a
# model; so are a red main (bin/lead.sh red-main reverts what broke it) and an assignment (to the developer with the
# fewest ready stories). Any other job runs as one headless session - /compasso:lead or /compasso:build with the job -
# for at most run.job_minutes, without permission prompts; Compasso's hooks still guard every tool call.
# In production only allowed tools run: the repo's commands, git, the tracker CLI, Compasso's scripts, its agents and
# run.allow (Claude: dontAsk; Codex: the workspace-write sandbox, with the network).
# After the session it reads the tracker again: the same job still waiting means no progress. A failed,
# timed-out or stalled job counts against its key; run.failures in a row asks a person (bin/human.sh)
# and the job is skipped while that question is open; once the person closes it, the job starts over.
# Files in .compasso/runs/runner/: events.jsonl (one line per run: the job, its stories, the result, the seconds and,
# when the harness reports them, the session's tokens, cost and model - its subagents included), failures.json, logs/, <role>-<name>.lock,
# audited (in harden, the lead's audit of the whole code is done: delete it to audit again)
#
# Exit: 0 idle, busy or the job moved on | 1 usage, a tracker failure or a failed job
set -u
case "${1:-}" in -h|--help) sed -n '2,/^set -u/s/^# \{0,1\}//p' "$0"; exit 0 ;; esac   # the header above is the help

BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROLE="${1:-}"; shift || true
REPO="." NAME="" HARNESS=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --name) NAME="$2"; shift 2 ;;
    --harness) HARNESS="$2"; shift 2 ;;
    *) echo "run: unknown argument '$1'" >&2; exit 1 ;;
  esac
done
case "$ROLE" in lead|dev) ;; *) echo "usage: run.sh lead|dev [--name N] [--repo R] [--harness claude|codex]" >&2; exit 1 ;; esac
REPO="$(cd "$REPO" 2>/dev/null && pwd)" || { echo "run: no repository at --repo" >&2; exit 1; }
[ "$ROLE" = lead ] || [ -n "$NAME" ] || { echo "run: dev needs --name" >&2; exit 1; }
cfg() { "$BIN/config.sh" get --repo "$REPO" "$1"; }
[ -n "$HARNESS" ] || HARNESS="$(cfg '.harnesses[0] // "claude"')"
case "$HARNESS" in claude|codex) ;; *) echo "run: --harness is claude or codex" >&2; exit 1 ;; esac

if [ "$(cfg .team.enabled)" = true ]; then   # the checkout's persona runs, as its own tracker account
  me="$("$BIN/persona.sh" show --repo "$REPO" --json)" || exit 1
  p="$(jq -r .persona <<<"$me")"; n="$(jq -r '.name // ""' <<<"$me")"; is="$p${n:+ $n}"
  if [ "$ROLE" = lead ]; then
    [ "$p" = tech-lead ] || { echo "run: this checkout is $is; run.sh lead runs in the tech lead's checkout" >&2; exit 1; }
  else
    [ "$p" = developer ] && [ "$n" = "$NAME" ] || { echo "run: this checkout is $is; run.sh dev --name $NAME runs in $NAME's checkout" >&2; exit 1; }
  fi
  [ -n "$(jq -r '.account // empty' <<<"$me")" ] || {
    echo "run: ${n:-the tech lead} has no tracker account of its own, and an agent never acts as a person - a person sets one: bin/persona.sh account --repo $REPO --set LOGIN --email E" >&2; exit 1; }
fi

DIR="$REPO/.compasso/runs/runner"; mkdir -p "$DIR/logs"
WHO="$ROLE${NAME:+ $NAME}"
LOCK="$DIR/$ROLE${NAME:+-$NAME}.lock"
FAIL="$DIR/failures.json"; [ -s "$FAIL" ] || echo '{}' > "$FAIL"

# one run at a time per role and name; a lock whose process is gone is taken over
if ! mkdir "$LOCK" 2>/dev/null; then
  pid="$(cat "$LOCK/pid" 2>/dev/null)"
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then echo "run: $WHO - busy: another run holds the lock"; exit 0; fi
  rm -rf "$LOCK"; mkdir "$LOCK" || { echo "run: cannot take the lock $LOCK" >&2; exit 1; }
fi
echo $$ > "$LOCK/pid"
trap 'rm -rf "$LOCK"' EXIT

START=$SECONDS
event() { # job-json result [usage-json]
  local u="${3:-}"; [ -n "$u" ] || u='{}'
  jq -cn --arg role "$ROLE" --arg name "$NAME" --argjson j "$1" --arg r "$2" --argjson s $((SECONDS - START)) --argjson u "$u" \
    '{at: (now | todate), role: $role, name: (if $name == "" then null else $name end), job: $j.job, key: ($j.key // null),
      iids: ($j.iids // []), result: $r, seconds: $s} + $u' >> "$DIR/events.jsonl"
}
usage() { # log -> what the session reported it used; {} when it reported nothing (never guessed)
  jq -R 'fromjson? // empty' "$1" 2>/dev/null | jq -cs '
    (map(select(type == "object" and .type == "result")) | last) as $r
    | [.[] | select(type == "object" and .type == "turn.completed") | .usage] as $t
    | if $r then {tokens: ($r.usage // {} | (.input_tokens // 0) + (.cache_creation_input_tokens // 0) + (.cache_read_input_tokens // 0) + (.output_tokens // 0)),
                  cost_usd: $r.total_cost_usd, turns: $r.num_turns,
                  model: (($r.modelUsage // {}) | to_entries | if length == 0 then null else max_by(.value.costUSD // 0).key end)}
      elif ($t | length) > 0 then {tokens: ($t | map((.input_tokens // 0) + (.output_tokens // 0)) | add), turns: ($t | length)}
      else {} end
    | with_entries(select(.value != null))' 2>/dev/null || echo '{}'
}
sync() { # the checkout follows the default branch between jobs; never discards work
  git -C "$REPO" remote get-url origin >/dev/null 2>&1 || return 0
  git -C "$REPO" fetch -q origin 2>/dev/null || { echo "run: $WHO - cannot fetch origin; this run uses the checkout as it is" >&2; return 0; }
  local def; def="$(git -C "$REPO" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null)"; def="${def#origin/}"
  [ -n "$def" ] || def="$(git -C "$REPO" ls-remote --symref origin HEAD 2>/dev/null | sed -n 's|^ref: refs/heads/\(.*\)[[:space:]]HEAD$|\1|p')"
  [ -n "$def" ] || return 0
  if [ -n "$(git -C "$REPO" status --porcelain --untracked-files=no)" ]; then
    echo "run: $WHO - uncommitted changes in this checkout; it stays on $(git -C "$REPO" rev-parse --abbrev-ref HEAD) instead of $def" >&2; return 0
  fi
  { git -C "$REPO" checkout -q "$def" && git -C "$REPO" merge -q --ff-only "origin/$def"; } >/dev/null 2>&1 ||
    echo "run: $WHO - could not bring $def up to date with origin/$def" >&2
}
next_job() { # the role's next job now; a stuck job is skipped while its question is open, and starts over once it is closed
  local snap asked n
  snap="$("$BIN/tracker.sh" snapshot --repo "$REPO")" || { echo "run: $WHO - cannot read the tracker" >&2; return 1; }
  asked="$(jq -c '[.issues[] | select(.kind == "ask") | .ask_key]' <<<"$snap")"; n="$(cfg '.run.failures // 2')"
  jq --argjson asked "$asked" --argjson n "$n" \
    'with_entries(select(.value < $n or (("stuck-" + (.key | gsub("[^A-Za-z0-9]"; "-"))) as $k | $asked | index($k))))' "$FAIL" > "$FAIL.tmp" && mv "$FAIL.tmp" "$FAIL"
  jq -c -L "$BIN" --arg role "$ROLE" --arg name "$NAME" --argjson devs "$(yq -o=json -I0 '.team.developers // []' "$REPO/.compasso/project.yaml")" \
    --argjson queue "$(cfg '.team.queue.min // 2')" --arg stage "$(cfg .stage)" --argjson audited "$([ -f "$DIR/audited" ] && echo true || echo false)" \
    --argjson skip "$(jq -c --argjson n "$n" '[to_entries[] | select(.value >= $n) | .key]' "$FAIL")" \
    'include "next"; next' <<<"$snap"
}

sync
job="$(next_job)" || exit 1
kind="$(jq -r '.job // empty' <<<"$job")"
key="$(jq -r '.key // empty' <<<"$job")"
if [ -z "$kind" ]; then event "$job" idle; echo "run: $WHO - nothing to do"; exit 0; fi

if [ "$kind" = unblock ]; then
  for i in $(jq -r '.iids[]' <<<"$job"); do
    "$BIN/tracker.sh" human-done --repo "$REPO" --iid "$i" >/dev/null || { event "$job" failed; echo "run: $WHO - could not unblock #$i" >&2; exit 1; }
  done
  event "$job" done; echo "run: $WHO - unblocked $(jq -r '.iids | map("#\(.)") | join(", ")' <<<"$job")"; exit 0
fi

skill=build; [ "$ROLE" = lead ] && skill=lead
case "$kind" in red-main|assign) skill="" ;; esac   # mechanical: the shell does them, no model
log="$DIR/logs/$(date -u +%Y%m%dT%H%M%SZ)-$ROLE${NAME:+-$NAME}-$(printf '%s' "$key" | tr -c 'A-Za-z0-9' '-').log"
secs="${COMPASSO_JOB_SECONDS:-$(( $(cfg '.run.job_minutes // 60') * 60 ))}"
if [ -z "$skill" ]; then
  case "$kind" in
    red-main) set -- "$BIN/lead.sh" red-main --repo "$REPO" $(jq -r '.mrs[0] // empty | "--failed-fix \(.)"' <<<"$job") ;;
    assign) set -- "$BIN/tracker.sh" assign --repo "$REPO" --iid "$(jq -r '.iids[0]' <<<"$job")" --name "$(jq -r '.devs[0]' <<<"$job")" ;;
  esac
elif [ "$(cfg .stage)" = production ]; then   # no prompts, but only what is allowed runs
  allow="$(yq -o=json '[.commands // {} | .[] | select(. != "" and . != null) | "Bash(\(.)*)"] + (.run.allow // [])' "$REPO/.compasso/project.yaml" |
    jq -r --arg cli "$( [ "$(cfg .tracker.provider)" = github ] && echo gh || echo glab )" \
      '["Read", "Edit", "Write", "Glob", "Grep", "Agent", "Bash(git *)", "Bash(\($cli) *)", "Bash(bash */compasso/*)"] + . | unique | join(",")')"
  case "$HARNESS" in
    claude) set -- claude -p "/compasso:$skill $job" --output-format json --permission-mode dontAsk --allowedTools "$allow" ;;
    codex) set -- codex exec --json --sandbox workspace-write -c sandbox_workspace_write.network_access=true "\$compasso-$skill $job" ;;
  esac
else
  case "$HARNESS" in
    claude) set -- claude -p "/compasso:$skill $job" --output-format json --permission-mode bypassPermissions ;;
    codex) set -- codex exec --json --dangerously-bypass-approvals-and-sandbox "\$compasso-$skill $job" ;;
  esac
fi
( cd "$REPO" && perl "$BIN/with-timeout.pl" "$secs" "$@" ) > "$log" 2>&1
rc=$?
ls -1t "$DIR/logs" | tail -n +51 | while read -r f; do rm -f "$DIR/logs/$f"; done   # the last 50 runs

result=done
if [ "$rc" -eq 142 ]; then result=timeout
elif [ "$rc" -ne 0 ]; then result=failed
elif [ "$kind" = audit ]; then   # done once per harden stage, on this machine: the tracker shows no state for it
  git -C "$REPO" rev-parse HEAD 2>/dev/null > "$DIR/audited" || : > "$DIR/audited"
elif [ -n "$skill" ]; then   # a session can end well and leave the work where it was; a shell job's exit says it all
  after="$(next_job)" || after='{}'
  [ "$(jq -r '.key // empty' <<<"$after")" = "$key" ] && result=no-progress
fi
used='{}'; [ -z "$skill" ] || used="$(usage "$log")"
event "$job" "$result" "$used"

if [ "$result" = done ]; then
  jq --arg k "$key" 'del(.[$k])' "$FAIL" > "$FAIL.tmp" && mv "$FAIL.tmp" "$FAIL"
  echo "run: $WHO - $key done in $((SECONDS - START))s"; exit 0
fi
jq --arg k "$key" '.[$k] = ((.[$k] // 0) + 1)' "$FAIL" > "$FAIL.tmp" && mv "$FAIL.tmp" "$FAIL"
n="$(jq -r --arg k "$key" '.[$k]' "$FAIL")"
echo "run: $WHO - $key $result (failure $n of $(cfg '.run.failures // 2'))" >&2
if [ "$n" -ge "$(cfg '.run.failures // 2')" ]; then
  story="$(jq -r 'if .job == "build" or .job == "rework" then .iids[0] else empty end' <<<"$job")"
  q="$DIR/ask.json"
  v="$(jq -cn --arg key "$key" --arg n "$n" --arg result "$result" --arg log "$log" --arg who "$WHO" --arg host "$(hostname)" '$ARGS.named')"
  jq -n -L "$BIN" --argjson L "$("$BIN/locale.sh" --repo "$REPO")" --argjson v "$v" 'include "i18n"; {
    title: tf("stuck_title"; $v), need: tf("stuck_need"; $v), why: [tf("stuck_why_count"; $v), tf("stuck_why_log"; $v)],
    steps: [t("stuck_step_read"), t("stuck_step_fix"), t("stuck_step_comment")], meanwhile: t("stuck_meanwhile")}' > "$q"
  "$BIN/human.sh" ask --repo "$REPO" --key "stuck-$(printf '%s' "$key" | tr -c 'A-Za-z0-9\n' '-')" ${story:+--story "$story"} \
    --title "$(jq -r .title "$q")" --from "$q" >/dev/null || echo "run: $WHO - could not ask a person about $key" >&2
fi
exit 1
