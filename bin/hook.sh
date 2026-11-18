#!/usr/bin/env bash
# Compasso's hooks, one entry point for every event (hooks/hooks.json on Claude Code,
# .codex/hooks.json on Codex). The event's JSON arrives on stdin.
#
#   hook.sh pre-tool        PreToolUse: role guard and command guard (they deny)
#   hook.sh post-agent      PostToolUse on Agent: binds the agent to its role and run; records its metrics
#   hook.sh subagent-start  SubagentStart: when each agent (re)started
#   hook.sh subagent-stop   SubagentStop: records a continued agent's run
#
# - Outside a repository with .compasso/project.yaml every hook exits at once, doing nothing:
#   plugin hooks fire in every repository on the machine.
# - COMPASSO_HOOKS=off is a person's emergency brake: every hook does nothing.
# - The guards fail closed: if a guard itself fails, the action is denied with the reason.
#   The other hooks fail silently and never disturb the session.
# - Both harnesses name the agent making a call (agent_type compasso:<role> on Claude Code,
#   compasso-<role> on Codex; verified live on both), so every guard applies on both.
#
# Role guard (Write, Edit, MultiEdit, NotebookEdit, apply_patch, and files a shell command writes: redirects,
#   tee, sed -i, cp, mv, rm, touch, mkdir), for Compasso's agents only:
#   paths in a story's worktree (.compasso/worktrees/<iid>/) are judged as if that worktree were the repository
#   every role: never outside the repository, never .compasso/project.yaml, .compasso/runs/.agents.json,
#     .claude/, .codex/ or .git/
#   tester: test_paths, manifests and test configs, the run folder | reviewer: docs/learnings/ |
#   security, planner, anything else: nothing
# Command guard (Bash; Read), for everyone: force-pushing the default branch, rm -r outside the repository
#   and temporary folders, reading secrets (.env, private keys, credential files), piping a download
#   into a shell.
set -u
case "${1:-}" in -h|--help) sed -n '2,/^set -u/s/^# \{0,1\}//p' "$0"; exit 0 ;; esac   # the header above is the help

BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EVENT="${1:-}"
[ "${COMPASSO_HOOKS:-on}" = off ] && exit 0
INPUT="$(cat)"

guard=0; [ "$EVENT" = pre-tool ] && guard=1
deny() { # reason
  jq -cn --arg r "Compasso: $1" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
  exit 0
}

if ! command -v jq >/dev/null 2>&1; then
  # without jq nothing can be read: guards deny inside Compasso repositories, everything else is silent
  [ "$guard" -eq 1 ] && [ -f "$PWD/.compasso/project.yaml" ] && { echo "Compasso: its guards need jq, which is not installed" >&2; exit 2; }
  exit 0
fi

cwd="$(jq -r '.cwd // empty' <<<"$INPUT" 2>/dev/null)"; [ -n "$cwd" ] || cwd="$PWD"
ROOT="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || echo "$cwd")"
[ -f "$ROOT/.compasso/project.yaml" ] || exit 0
ROOT="$(cd "$ROOT" && pwd -P)"
STATE="$ROOT/.compasso/runs/.agents.json"

# ---------- shared ----------
lock() { local n=0; mkdir -p "$ROOT/.compasso/runs"; until mkdir "$STATE.lock" 2>/dev/null; do n=$((n + 1)); [ "$n" -gt 50 ] && return 1; sleep 0.1; done; }
unlock() { rmdir "$STATE.lock" 2>/dev/null || true; }
state() { [ -f "$STATE" ] && cat "$STATE" || echo '{}'; }
state_set() { # jq filter with --arg id ... applied to the state
  local f="$1"; shift
  lock || return 1
  state | jq "$@" "$f" > "$STATE.tmp" && mv "$STATE.tmp" "$STATE"; local rc=$?
  unlock; return $rc
}
run_of() { grep -oE '\.compasso/runs/[A-Za-z0-9._-]*[A-Za-z0-9_-]' <<<"$1" | head -1; }   # never ends in a sentence's period
alias_of() { case "$1" in *opus*) echo opus ;; *sonnet*) echo sonnet ;; *haiku*) echo haiku ;; *fable*) echo fable ;; *) echo "$1" ;; esac; }

relpath() { # absolute or cwd-relative path -> path inside the repository, or "" when outside
  local p="$1" out="" part IFS=/
  case "$p" in /*) ;; *) p="$cwd/$p" ;; esac
  case "$p" in "$ROOT"/*) p="${p#"$ROOT"/}" ;; *)
    local phys; phys="$(cd "$(dirname "$p")" 2>/dev/null && pwd -P)/$(basename "$p")" || true
    case "$phys" in "$ROOT"/*) p="${phys#"$ROOT"/}" ;; *) echo ""; return ;; esac ;; esac
  for part in $p; do
    case "$part" in ''|.) ;; ..) case "$out" in */*) out="${out%/*}" ;; '') echo ""; return ;; *) out="" ;; esac ;; *) out="${out:+$out/}$part" ;; esac
  done
  echo "$out"
}
matches() { # path glob... ; * crosses "/"
  local f="$1" g; shift
  for g in "$@"; do case "$f" in $g) return 0 ;; esac; case "/$f" in $g) return 0 ;; esac; done
  return 1
}

# ---------- role guard ----------
role_guard() {
  local atype role tool paths p rel tests
  atype="$(jq -r '.agent_type // ""' <<<"$INPUT")"
  case "$atype" in compasso:*|compasso-*) role="${atype#compasso[:-]}" ;; *) return 0 ;; esac
  tool="$(jq -r '.tool_name' <<<"$INPUT")"
  case "$tool" in
    Write|Edit|MultiEdit) paths="$(jq -r '.tool_input.file_path // empty' <<<"$INPUT")" ;;
    NotebookEdit) paths="$(jq -r '.tool_input.notebook_path // empty' <<<"$INPUT")" ;;
    apply_patch) paths="$(jq -r '.tool_input | .. | strings' <<<"$INPUT" | sed -nE 's/^\*\*\* (Add File|Update File|Delete File|Move to): (.+)$/\2/p')" ;;
    Bash|shell|local_shell|exec_command) paths="$(shell_writes "$(jq -r '.tool_input.command | if type == "array" then join(" ") else (. // "") end' <<<"$INPUT")")" ;;
    *) return 0 ;;
  esac
  tests="$(yq -r '.test_paths[]' "$ROOT/.compasso/project.yaml")" || return 1
  set -f
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    rel="$(relpath "$p")"
    [ -n "$rel" ] || { verdict "the $role may only write inside the repository, not $p"; return 0; }
    # a worktree (bin/lead.sh red-main) is judged as the repository itself
    case "$rel" in .compasso/worktrees/*/*) rel="${rel#.compasso/worktrees/*/}" ;; esac
    if matches "$rel" '.compasso/project.yaml' '.compasso/runs/.agents.json' '.claude/*' '.codex/*' '.git/*'; then
      verdict "no agent may change $rel: it holds Compasso's settings or git state"; return 0
    fi
    # shellcheck disable=SC2086
    case "$role" in
      tester) matches "$rel" $tests '.compasso/runs/*' '*package.json' '*package-lock.json' '*pnpm-lock.yaml' '*yarn.lock' '*pyproject.toml' '*requirements*.txt' '*setup.cfg' '*tox.ini' '*pytest.ini' '*conftest.py' '*go.mod' '*go.sum' '*pom.xml' '*build.gradle' '*build.gradle.kts' '*settings.gradle*' '*.csproj' '*Directory.Packages.props' '*Gemfile' '*Gemfile.lock' '*.rspec' '*composer.json' '*composer.lock' '*phpunit.xml*' '*Cargo.toml' '*Cargo.lock' '*playwright.config.*' '*vitest.config.*' '*jest.config.*' '*cypress.config.*' '*.mocharc*' ||
          { verdict "the tester writes tests, test configs and manifests only; $rel is product code, which is the developer's"; return 0; } ;;
      reviewer) matches "$rel" 'docs/learnings/*' || { verdict "the reviewer only writes lessons in docs/learnings/, not $rel"; return 0; } ;;
      *) verdict "the $role only reads; it may not write $rel"; return 0 ;;
    esac
  done <<EOF
$paths
EOF
  set +f
  return 0
}
verdict() { deny "$1"; }
shell_writes() { # a shell command -> the files it writes, one per line (redirects, tee, sed -i, cp, mv, rm, touch, mkdir)
  local seg w words n i last
  set -f
  printf '%s\n' "$1" | grep -oE '>>?[[:space:]]*[^[:space:];&|<>]+' | sed -E 's/^>>?[[:space:]]*//' | grep -vE '^(&|/dev/)' || true
  printf '%s\n' "$1" | tr ';&|' '\n\n\n' | while IFS= read -r seg; do
    # shellcheck disable=SC2086
    set -- $seg
    [ $# -gt 0 ] || continue
    case "$1" in sudo|env|command) shift ;; esac
    case "${1:-}" in
      tee) shift; for w in "$@"; do case "$w" in -*) ;; *) echo "$w" ;; esac; done ;;
      rm|touch|mkdir|truncate) shift; for w in "$@"; do case "$w" in -*) ;; *) echo "$w" ;; esac; done ;;
      cp|mv|install|ln) shift; last=""; for w in "$@"; do case "$w" in -*) ;; *) last="$w" ;; esac; done; [ -n "$last" ] && echo "$last" ;;
      sed|perl) case " $* " in *" -i"*|*" --in-place"*) last=""; for w in "$@"; do last="$w"; done; echo "$last" ;; esac ;;
    esac
  done
}

# ---------- command guard ----------
command_guard() {
  local tool cmd def f
  set -f   # words of the command are checked as written, never expanded against this folder
  tool="$(jq -r '.tool_name' <<<"$INPUT")"
  case "$tool" in
    Read)
      f="$(jq -r '.tool_input.file_path // ""' <<<"$INPUT")"
      secret_file "${f##*/}" && deny "reading $f is blocked: it looks like a secret (credentials, keys, .env). A person can read it outside the agent."
      return 0 ;;
    Bash|shell|local_shell|exec_command|container.exec) ;;
    *) return 0 ;;
  esac
  cmd="$(jq -r '.tool_input.command | if type == "array" then join(" ") else (. // "") end' <<<"$INPUT")"
  [ -n "$cmd" ] || return 0
  # force-pushing the default branch
  if grep -qE '(^|[;&|[:space:]])git([[:space:]]+-[^[:space:]]+)*[[:space:]]+push([[:space:]]|$)' <<<"$cmd" &&
     grep -qE '[[:space:]](--force(-with-lease)?(=[^[:space:]]*)?|-f|-[a-zA-Z]*f[a-zA-Z]*)([[:space:]]|$)|[[:space:]]\+[^[:space:]]+' <<<"$cmd"; then
    def="$(git -C "$ROOT" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')"; [ -n "$def" ] || def=main
    if grep -qE "(^|[[:space:]:+/])$def([[:space:]]|$)|[[:space:]]HEAD([[:space:]]|$)" <<<"$cmd" ||
       [ "$(git -C "$ROOT" branch --show-current 2>/dev/null)" = "$def" ]; then
      deny "force-pushing $def is blocked: it rewrites the shared history. Push a branch and open a merge request."
    fi
  fi
  # rm -r outside the repository and temporary folders
  if grep -qE '(^|[;&|[:space:]])rm[[:space:]]+(-[a-zA-Z]*[rR][a-zA-Z]*|--recursive)' <<<"$cmd"; then
    for f in $(sed -E 's/.*(^|[;&|[:space:]])rm[[:space:]]+//' <<<"$cmd" | tr ';&|' '   '); do
      case "$f" in -*) continue ;; esac
      case "$f" in
        "~"*|'$HOME'*|'${HOME}'*|'*'|/|/\*|..|../*|*/..|*/../*) deny "rm -r of $f is blocked: it can reach outside the repository" ;;
        /tmp/*|/private/tmp/*|/var/folders/*|"$ROOT"/*) ;;
        /*) deny "rm -r of $f is blocked: it is outside the repository" ;;
      esac
    done
  fi
  # reading secrets
  if grep -qE '(^|[;&|[:space:]])(cat|less|more|head|tail|grep|egrep|rg|awk|sed|bat|strings|xxd|od|base64|source|\.|cp|scp|curl)[[:space:]]' <<<"$cmd"; then
    for f in $cmd; do f="${f//[\'\"]/}"; secret_file "${f##*/}" && deny "reading or copying $f is blocked: it looks like a secret (credentials, keys, .env). A person can do it outside the agent."; done
  fi
  # a download piped into a shell
  grep -qE '(curl|wget)[^|]*\|[[:space:]]*(sudo[[:space:]]+)?(ba|z|da|k)?sh([[:space:]]|$)' <<<"$cmd" &&
    deny "piping a download into a shell is blocked: download it, read it, then run it"
  return 0
}
secret_file() { # basename -> 0 when it looks like a secret
  case "$1" in
    .env.example|.env.sample|.env.template|.env.dist) return 1 ;;
    .env|.env.*|*.pem|*.key|*.p12|*.pfx|id_rsa|id_rsa.*|id_ed25519|id_ed25519.*|id_ecdsa|credentials.json|.npmrc|.netrc|.pypirc|*.keystore|*.jks) return 0 ;;
  esac
  return 1
}

# ---------- metrics ----------
record() { # run role model tokens ms
  "$BIN/story-metrics.sh" agent --run "$ROOT/$1" --role "$2" --model "$3" ${4:+--tokens "$4"} ${5:+--ms "$5"} >/dev/null 2>&1 || true
}

case "$EVENT" in
  pre-tool)
    err="$(mktemp)"
    out="$( { role_guard && command_guard; } 2>"$err")"; rc=$?
    msg="$(tail -3 "$err")"; rm -f "$err"
    if [ "$rc" -ne 0 ]; then deny "a guard failed, so the action is denied (${msg:-exit $rc}). Fix it, or a person sets COMPASSO_HOOKS=off."; fi
    [ -n "$msg" ] && echo "$msg" >&2
    printf '%s' "$out" ;;
  post-agent)
    {
      atype="$(jq -r '.tool_response.agentType // .tool_input.subagent_type // ""' <<<"$INPUT")"
      case "$atype" in compasso:*) ;; *) exit 0 ;; esac
      id="$(jq -r '.tool_response.agentId // empty' <<<"$INPUT")"; [ -n "$id" ] || exit 0
      run="$(run_of "$(jq -r '.tool_input.prompt // ""' <<<"$INPUT")")"; [ -n "$run" ] || exit 0
      model="$(alias_of "$(jq -r '.tool_input.model // .tool_response.resolvedModel // "unknown"' <<<"$INPUT")")"
      state_set '.[$id] = ((.[$id] // {}) + {role: $role, run: $run, model: $model})' --arg id "$id" --arg role "${atype#compasso:}" --arg run "$run" --arg model "$model"
      tokens="$(jq -r '.tool_response.totalTokens // empty' <<<"$INPUT")"
      # a background agent returns before it finishes: its run is recorded when it stops
      [ -n "$tokens" ] && record "$run" "${atype#compasso:}" "$model" "$tokens" "$(jq -r '.tool_response.totalDurationMs // empty' <<<"$INPUT")"
    } >/dev/null 2>&1
    exit 0 ;;
  subagent-start)
    {
      atype="$(jq -r '.agent_type // ""' <<<"$INPUT")"; id="$(jq -r .agent_id <<<"$INPUT")"
      case "$atype" in
        compasso:*) state_set '.[$id] = ((.[$id] // {}) + {started: ($now | tonumber), role: $role})' --arg id "$id" --arg now "$(date +%s)" --arg role "${atype#compasso:}" ;;
      esac
    } >/dev/null 2>&1
    exit 0 ;;
  subagent-stop)
    {
      id="$(jq -r '.agent_id // ""' <<<"$INPUT")"
      info="$(state | jq -c --arg id "$id" '.[$id] // empty')"
      # bound means the agent was already dispatched and recorded: this stop ends a continuation
      [ -n "$info" ] && [ "$(jq -r '.run // ""' <<<"$info")" != "" ] || exit 0
      t="$(jq -r '.agent_transcript_path // ""' <<<"$INPUT")"
      tokens=""
      if [ -f "$t" ]; then
        tokens="$(jq -s '[.[] | select(.message.usage) | .message.usage] | last // empty | (.input_tokens + (.cache_creation_input_tokens // 0) + (.cache_read_input_tokens // 0) + .output_tokens)' "$t" 2>/dev/null)"
      fi
      started="$(jq -r '.started // empty' <<<"$info")"; ms=""; [ -n "$started" ] && ms=$(( ($(date +%s) - started) * 1000 ))
      record "$(jq -r .run <<<"$info")" "$(jq -r .role <<<"$info")" "$(jq -r --arg m "$(jq -r '.model // ""' <<<"$INPUT")" '.model // (if $m == "" then "unknown" else $m end)' <<<"$info")" "$tokens" "$ms"
    } >/dev/null 2>&1
    exit 0 ;;
  *) exit 0 ;;
esac
