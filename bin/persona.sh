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
#
# Exit: 0 ok or allowed | 1 failure | 2 usage | 6 the persona may not do this
set -u

BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CMD="${1:-}"; shift || true
REPO="." PERSONA="" NAME="" SKILL="" TRACKER="" READ_ONLY=0 JSON=0
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --persona) PERSONA="$2"; shift 2 ;;
    --name) NAME="$2"; shift 2 ;;
    --skill) SKILL="$2"; shift 2 ;;
    --tracker) TRACKER="$2"; shift 2 ;;
    --read-only) READ_ONLY=1; shift ;;
    --json) JSON=1; shift ;;
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
persona() { local p; p="$(sed -n 's/^persona=//p' "$FILE" 2>/dev/null | head -1)"; echo "${p:-default}"; }
name() { sed -n 's/^name=//p' "$FILE" 2>/dev/null | head -1; }
team() { [ "$("$BIN/config.sh" get --repo "$CFG_REPO" .team.enabled 2>/dev/null)" = true ]; }
refuse() { echo "persona: $1" >&2; exit 6; }

case "$CMD" in
  show)
    t=false; team && t=true
    if [ "$JSON" -eq 1 ]; then
      jq -n --arg p "$(persona)" --arg n "$(name)" --arg c "$CHECKOUT" --argjson t "$t" \
        '{persona: $p, name: (if $n == "" then null else $n end), checkout: $c, team: $t}'
    else
      echo "$(persona)$( [ -n "$(name)" ] && echo " $(name)")"
    fi ;;
  set)
    case "$PERSONA" in
      default|tech-lead) [ -z "$NAME" ] || { echo "persona: only a developer has a name" >&2; exit 2; } ;;
      developer) valid_name "$NAME" || { echo "persona: a developer needs --name: lowercase letters, digits and hyphens, starting with a letter, at most 20 (not default, lead or none)" >&2; exit 2; } ;;
      *) echo "persona: --persona must be default, tech-lead or developer" >&2; exit 2 ;;
    esac
    { echo "persona=$PERSONA"; [ -z "$NAME" ] || echo "name=$NAME"; } > "$FILE" || exit 1
    echo "persona: this checkout is $PERSONA$( [ -n "$NAME" ] && echo " $NAME")" ;;
  join)
    [ "$(persona)" = developer ] || { echo "persona: only a developer joins a team - run setup and choose developer" >&2; exit 1; }
    jq -n --arg n "$(name)" --arg p "$("$BIN/config.sh" get --repo "$CFG_REPO" .tracker.project)" --arg c "$CHECKOUT" \
      '{compasso: "join", name: $n, project: $p, harness: "claude", checkout: $c}' ;;
  gate)
    p="$(persona)"
    [ -n "$SKILL$TRACKER" ] || { echo "persona: gate needs --skill or --tracker" >&2; exit 2; }
    case "$TRACKER" in label|label-create|comment-delete)
      refuse "$TRACKER is used through bin/team.sh, which checks who may assign, claim and message" ;; esac
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
      check|story|mr-info|sprint-items|sprint-done|merge-commit|open-mr-branch|digest|labels|comments) exit 0 ;;
      sprint-sync) [ "$READ_ONLY" -eq 1 ] && exit 0 ;;
    esac
    case "$p:$TRACKER" in
      default:*) refuse "this is a team project and this checkout has no persona, so it only reads. Run /compasso:setup and choose tech lead or developer." ;;
      tech-lead:*) ;;
      developer:push-plan|developer:push-backlog|developer:ensure-labels|developer:protect) refuse "$TRACKER is the tech lead's: a developer does not change the scope or the project's settings" ;;
      developer:*) ;;
    esac
    exit 0 ;;
  *) echo "usage: persona.sh show|set|join|gate --repo R ..." >&2; exit 2 ;;
esac
