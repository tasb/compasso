#!/usr/bin/env bash
# The persona of the agent working in this checkout: what the whole agent may do.
# Not a role: roles/ are the subagents a flow dispatches; a persona is the session that runs the flows.
#
#   default     Compasso as it always was: one agent does everything. No persona file means default.
#   tech-lead   manages scope and assigns the work; never builds
#   developer   builds what carries its name; always an agent, with a name
#
# The persona is one agent's and .compasso/project.yaml is everyone's, so it lives outside the
# repository, as Verify approvals do: ${COMPASSO_HOME:-$HOME/.compasso}/persona/<sha256 of the
# repository's physical path> (its worktrees share it), holding "persona=<p>" and "name=<n>".
# A team project is one with team.enabled: true. In it, the default persona only reads.
#
#   persona.sh show --repo R [--json]                         the persona, name and checkout id
#   persona.sh set  --repo R --persona P [--name N]           after a person chose (setup)
#   persona.sh join --repo R                                  the JSON a developer hands to the tech lead
#   persona.sh gate --repo R --skill S | --tracker C [--read-only]   may this persona run it?
#   persona.sh account --repo R --set LOGIN --email E   the tracker account this agent uses (one per agent, never a person's)
#   persona.sh env  --repo R                                  "export ..." of the account's token, for the adapters to eval
#
# The account: every tracker call exports its token for that call only (GitLab GITLAB_TOKEN, from
# <home>/accounts/<host>/<login>, mode 600, written by a person; GitHub GH_TOKEN, from gh, which holds the
# account), and git gets the same token from a credential helper set in the repository's own configuration
# (bin/git-credential-compasso, copied to <home>/bin). The agent's commits carry its name (a developer's
# name, "tech-lead", or the login) and email. A checkout with no account uses the machine's login, as before.
#
# Exit: 0 ok or allowed | 1 failure | 2 usage | 6 the persona may not do this
set -u
case "${1:-}" in -h|--help) sed -n '2,/^set -u/s/^# \{0,1\}//p' "$0"; exit 0 ;; esac   # the header above is the help

BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CMD="${1:-}"; shift || true
REPO="." PERSONA="" NAME="" SKILL="" TRACKER="" READ_ONLY=0 JSON=0 ACCOUNT="" EMAIL=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --persona) PERSONA="$2"; shift 2 ;;
    --name) NAME="$2"; shift 2 ;;
    --skill) SKILL="$2"; shift 2 ;;
    --tracker) TRACKER="$2"; shift 2 ;;
    --read-only) READ_ONLY=1; shift ;;
    --json) JSON=1; shift ;;
    --set) ACCOUNT="$2"; shift 2 ;;
    --email) EMAIL="$2"; shift 2 ;;
    *) echo "persona: unknown argument '$1'" >&2; exit 2 ;;
  esac
done
CFG_REPO="$REPO"   # a worktree has the configuration too
REPO="$(cd "$REPO" 2>/dev/null && pwd -P)" || { echo "persona: no repository" >&2; exit 2; }
common="$(git -C "$REPO" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
case "$common" in */.git) REPO="$(cd "${common%/.git}" && pwd -P)" ;; esac
HOME_DIR="${COMPASSO_HOME:-$HOME/.compasso}"
mkdir -p "$HOME_DIR/persona" || exit 1
HOME_DIR="$(cd "$HOME_DIR" && pwd -P)"
case "$HOME_DIR/" in "$REPO/"*) echo "persona: a persona cannot live inside the repository it works in ($HOME_DIR)" >&2; exit 1 ;; esac
sha() { printf '%s' "$1" | shasum -a 256 | cut -d' ' -f1; }
FILE="$HOME_DIR/persona/$(sha "$REPO")"
CHECKOUT="$(sha "$(hostname):$REPO" | cut -c1-12)"   # two machines can hold the same path

valid_name() { # lowercase letters, digits and hyphens, starting with a letter, at most 20; not a reserved word
  [[ "$1" =~ ^[a-z][a-z0-9-]{0,19}$ ]] || return 1
  case "$1" in default|lead|none) return 1 ;; esac
}
field() { sed -n "s/^$1=//p" "$FILE" 2>/dev/null | head -1; }
persona() { local p; p="$(field persona)"; echo "${p:-default}"; }
name() { field name; }
keep() { # rewrite the file with these key=value lines replaced (the others kept)
  local tmp="$FILE.tmp" k
  { grep -v -E "^($(printf '%s\n' "$@" | sed 's/=.*//' | paste -sd'|' -))=" "$FILE" 2>/dev/null; printf '%s\n' "$@"; } > "$tmp" && mv "$tmp" "$FILE"
}
team() { [ "$("$BIN/config.sh" get --repo "$CFG_REPO" .team.enabled 2>/dev/null)" = true ]; }
refuse() { echo "persona: $1" >&2; exit 6; }

case "$CMD" in
  show)
    t=false; team && t=true
    if [ "$JSON" -eq 1 ]; then
      jq -n --arg p "$(persona)" --arg n "$(name)" --arg c "$CHECKOUT" --argjson t "$t" --arg a "$(field account)" --arg e "$(field email)" \
        '{persona: $p, name: (if $n == "" then null else $n end), checkout: $c, team: $t,
          account: (if $a == "" then null else $a end), email: (if $e == "" then null else $e end)}'
    else
      echo "$(persona)$( [ -n "$(name)" ] && echo " $(name)")"
    fi ;;
  set)
    case "$PERSONA" in
      default|tech-lead) [ -z "$NAME" ] || { echo "persona: only a developer has a name" >&2; exit 2; } ;;
      developer) valid_name "$NAME" || { echo "persona: a developer needs --name: lowercase letters, digits and hyphens, starting with a letter, at most 20 (not default, lead or none)" >&2; exit 2; } ;;
      *) echo "persona: --persona must be default, tech-lead or developer" >&2; exit 2 ;;
    esac
    { echo "persona=$PERSONA"; [ -z "$NAME" ] || echo "name=$NAME"; grep -E '^(account|email|host|provider)=' "$FILE" 2>/dev/null || true; } > "$FILE.tmp" &&
      mv "$FILE.tmp" "$FILE" || exit 1   # the account stays: it is the agent's, whatever its persona
    echo "persona: this checkout is $PERSONA$( [ -n "$NAME" ] && echo " $NAME")" ;;
  join)
    [ "$(persona)" = developer ] || { echo "persona: only a developer joins a team - run setup and choose developer" >&2; exit 1; }
    jq -n --arg n "$(name)" --arg p "$("$BIN/config.sh" get --repo "$CFG_REPO" .tracker.project)" --arg c "$CHECKOUT" --arg a "$(field account)" \
      '{compasso: "join", name: $n, project: $p, harness: "claude", checkout: $c} + (if $a == "" then {} else {account: $a} end)' ;;
  account)
    [ -n "$ACCOUNT" ] || { jq -n --arg a "$(field account)" --arg e "$(field email)" '{account: (if $a == "" then null else $a end), email: (if $e == "" then null else $e end)}'; exit 0; }
    [[ "$ACCOUNT" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,99}$ ]] || { echo "persona: '$ACCOUNT' is not a tracker login" >&2; exit 2; }
    [[ "$EMAIL" =~ ^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$ ]] || { echo "persona: --email is the agent's commit email (name@domain)" >&2; exit 2; }
    provider="$("$BIN/config.sh" get --repo "$CFG_REPO" .tracker.provider)"; host="$("$BIN/config.sh" get --repo "$CFG_REPO" .tracker.host)"
    [ "$provider" != github ] || [ -n "$host" ] || host=github.com
    case "$provider" in
      gitlab)
        tf="$HOME_DIR/accounts/$host/$ACCOUNT"
        [ -s "$tf" ] || { echo "persona: no token for $ACCOUNT - the person writes the service account's token to $tf, in their own terminal, never in a chat:" >&2
          echo "  mkdir -p '$HOME_DIR/accounts/$host' && (umask 077; read -rs T && printf '%s' \"\$T\" > '$tf')" >&2; exit 1; }
        [ "$(ls -l "$tf" | cut -c5-10)" = "------" ] || { echo "persona: $tf can be read by others - chmod 600 '$tf'" >&2; exit 1; } ;;
      github)
        gh auth token --hostname "$host" --user "$ACCOUNT" >/dev/null 2>&1 ||
          { echo "persona: gh holds no account $ACCOUNT - log it in first: gh auth login --hostname $host (as $ACCOUNT)" >&2; exit 1; } ;;
      *) echo "persona: no tracker in .compasso/project.yaml - run setup" >&2; exit 1 ;;
    esac
    [ -f "$FILE" ] || echo "persona=default" > "$FILE"
    keep "account=$ACCOUNT" "email=$EMAIL" "host=$host" "provider=$provider" || exit 1
    # git: the token from the helper, for the tracker's host only; the inherited helpers are reset first
    mkdir -p "$HOME_DIR/bin" && cp "$BIN/git-credential-compasso" "$HOME_DIR/bin/" && chmod 755 "$HOME_DIR/bin/git-credential-compasso" || exit 1
    k="credential.https://$host.helper"
    git -C "$REPO" config --local --unset-all "$k" 2>/dev/null
    git -C "$REPO" config --local --add "$k" "" && git -C "$REPO" config --local --add "$k" "!'$HOME_DIR/bin/git-credential-compasso'" || exit 1
    case "$(persona)" in developer) who="$(name)" ;; tech-lead) who=tech-lead ;; *) who="$ACCOUNT" ;; esac
    git -C "$REPO" config --local user.name "$who" && git -C "$REPO" config --local user.email "$EMAIL" || exit 1
    echo "persona: this checkout uses $ACCOUNT on $host; its commits are $who <$EMAIL>"
    # the tech lead owns the configuration: its own login joins the agents, whose approvals never count as a person's
    if [ "$(persona)" = tech-lead ]; then
      A="$ACCOUNT" yq -i '.team.agents = ((.team.agents // []) + [strenv(A)] | unique)' "$CFG_REPO/.compasso/project.yaml" || exit 1
      echo "persona: $ACCOUNT is in team.agents - commit .compasso/project.yaml"
    fi ;;
  env)
    [ -n "$(field account)" ] || exit 0
    t="$("$BIN/git-credential-compasso" token --repo "$REPO")" && [ -n "$t" ] || exit 1
    case "$(field provider)" in
      gitlab) printf 'export GITLAB_TOKEN=%q\n' "$t" ;;
      github) printf 'export GH_TOKEN=%q GH_ENTERPRISE_TOKEN=%q\n' "$t" "$t" ;;
    esac ;;
  gate)
    p="$(persona)"
    [ -n "$SKILL$TRACKER" ] || { echo "persona: gate needs --skill or --tracker" >&2; exit 2; }
    case "$TRACKER" in label|label-create|comment-delete|comment-edit)
      refuse "$TRACKER is used through bin/team.sh and bin/mr-report.sh, which check who may assign, claim, message and report" ;; esac
    if ! team; then
      [ "$p" = default ] || refuse "this checkout is $p, but the project has no team (team.enabled is false in .compasso/project.yaml). The tech lead's setup turns it on; pull its change, or run setup and choose default."
      [ "$SKILL" != work ] || refuse "the poll is for team projects (team.enabled: true)"
      exit 0
    fi
    if [ -n "$SKILL" ]; then
      case "$p:$SKILL" in
        *:setup|*:start|*:status) ;;
        tech-lead:story) refuse "the tech lead never builds: assign the story to a developer (bin/team.sh assign)" ;;
        tech-lead:*) ;;
        developer:story|developer:sprint|developer:review|developer:work) ;;
        developer:*) refuse "a developer builds what is assigned to it; /compasso:$SKILL is the tech lead's" ;;
        default:report|default:present) ;;
        default:*) refuse "this is a team project and this checkout has no persona, so it only reads. Run /compasso:setup and choose tech lead or developer." ;;
      esac
      exit 0
    fi
    case "$TRACKER" in
      check|story|mr-info|mr-of|mr-events|mr-checks|main-pipeline|followups|sprint-items|sprint-done|merge-commit|digest|labels|comments) exit 0 ;;
      merge) refuse "in a team project the tech lead (in mvp also the story's developer) merges, through bin/team.sh merge, which checks the reports, the risk, main and a person's approval" ;;
      mr-update) refuse "in a team project the tech lead brings a merge request up to date, through bin/team.sh update" ;;
      disarm) refuse "in a team project the tech lead turns off auto-merge when main is red, through bin/team.sh main" ;;
      sprint-sync) [ "$READ_ONLY" -eq 1 ] && exit 0 ;;
    esac
    case "$p:$TRACKER" in
      default:*) refuse "this is a team project and this checkout has no persona, so it only reads. Run /compasso:setup and choose tech lead or developer." ;;
      tech-lead:*) ;;
      developer:push-plan|developer:push-backlog|developer:ensure-labels|developer:protect|developer:set-milestone|developer:close) refuse "$TRACKER is the tech lead's: a developer does not change the scope or the project's settings" ;;
      developer:*) ;;
    esac
    exit 0 ;;
  *) echo "usage: persona.sh show|set|join|gate|account|env --repo R ..." >&2; exit 2 ;;
esac
