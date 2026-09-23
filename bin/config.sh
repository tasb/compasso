#!/usr/bin/env bash
# Compasso project configuration: .compasso/project.yaml
#
#   config.sh init     --repo R [--project ns/name]   copy the template (refuses to overwrite)
#   config.sh validate --repo R                       print every problem, exit 1 if any
#   config.sh get      --repo R <yq-path>             print one value
#
# Exit: 0 ok | 1 invalid or failure | 3 no config file
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROLES="planner tester builder reviewer security approver shipper"
FLOOR_ROLES="security approver"   # may never run on a fast-tier model or low effort

CMD="${1:-}"; shift || true
REPO="." PROJECT="" ARG=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --project) PROJECT="$2"; shift 2 ;;
    -*) echo "config: unknown option '$1'" >&2; exit 1 ;;
    *) ARG="$1"; shift ;;
  esac
done
CFG="$REPO/.compasso/project.yaml"

need_cfg() { [ -f "$CFG" ] || { echo "config: no $CFG - run /compasso:setup" >&2; exit 3; }; }
val() { yq -r "$1 // \"\"" "$CFG"; }
is_int() { case "$1" in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac; }

fast_tier() { # harness model -> 0 when the model is a fast/cheap tier
  case "$1:$2" in
    claude:haiku|claude:*haiku*) return 0 ;;
    codex:*luna*|codex:*mini*|codex:*nano*) return 0 ;;
  esac
  return 1
}

validate() {
  local errs="" h r m e v weeks hpd cap smax star
  err() { errs="$errs  - $1"$'\n'; }

  yq -e '.' "$CFG" >/dev/null 2>&1 || { echo "config: $CFG is not valid YAML" >&2; return 1; }

  [ "$(val .version)" = "1" ] || err "version must be 1"
  [ "$(val .tracker.provider)" = "gitlab" ] || err "tracker.provider must be gitlab"
  [ -n "$(val .tracker.host)" ] || err "tracker.host is required"
  case "$(val .tracker.project)" in
    */*) : ;;
    *) err "tracker.project must be namespace/project" ;;
  esac
  case "$(val .tracker.tier)" in
    auto|free|premium) : ;;
    *) err "tracker.tier must be auto, free or premium" ;;
  esac

  weeks="$(val .sprint.weeks)"; hpd="$(val .sprint.hours_per_day)"; cap="$(val .sprint.capacity_hours)"
  is_int "$weeks" && [ "$weeks" -ge 1 ] && [ "$weeks" -le 8 ] || err "sprint.weeks must be an integer from 1 to 8"
  is_int "$hpd" && [ "$hpd" -ge 1 ] && [ "$hpd" -le 24 ] || err "sprint.hours_per_day must be an integer from 1 to 24"
  is_int "$cap" && [ "$cap" -ge 1 ] || err "sprint.capacity_hours must be a positive integer"

  smax="$(val .limits.story_max_hours)"; star="$(val .limits.story_target_hours)"
  if is_int "$smax" && [ "$smax" -ge 1 ]; then
    is_int "$hpd" && [ "$smax" -gt "$hpd" ] && err "limits.story_max_hours ($smax) exceeds one working day ($hpd)"
  else
    err "limits.story_max_hours must be a positive integer"
  fi
  if is_int "$star" && [ "$star" -ge 1 ]; then
    is_int "$smax" && [ "$star" -gt "$smax" ] && err "limits.story_target_hours ($star) exceeds story_max_hours ($smax)"
  else
    err "limits.story_target_hours must be a positive integer"
  fi

  [ "$(yq -r '.test_paths | length' "$CFG" 2>/dev/null)" -ge 1 ] 2>/dev/null || err "test_paths must list at least one pattern"

  v="$(val .coverage.min_changed)"
  is_int "$v" && [ "$v" -le 100 ] || err "coverage.min_changed must be an integer from 0 to 100"
  [ -z "$(val .coverage.command)" ] || [ -n "$(val .coverage.report)" ] || err "coverage.report is required when coverage.command is set"

  case "$(val .approvals.plan)" in human|auto) : ;; *) err "approvals.plan must be human or auto" ;; esac
  case "$(val .approvals.merge)" in human|agent) : ;; *) err "approvals.merge must be human or agent" ;; esac

  [ "$(yq -r '.harnesses | length' "$CFG")" -ge 1 ] 2>/dev/null || err "harnesses must list claude and/or codex"
  for h in $(yq -r '.harnesses[]?' "$CFG"); do
    case "$h" in claude|codex) : ;; *) err "harnesses: unknown '$h'"; continue ;; esac
    for r in $ROLES; do
      m="$(val ".models.$h.$r.model")"; e="$(val ".models.$h.$r.effort")"
      [ -n "$m" ] || { err "models.$h.$r.model is required"; continue; }
      case " $FLOOR_ROLES " in *" $r "*)
        fast_tier "$h" "$m" && err "models.$h.$r: '$m' is a fast-tier model; $r needs a strong model"
        case "$e" in low|minimal) err "models.$h.$r: effort '$e' is below the floor for $r" ;; esac
      esac
    done
  done

  # Security review is not configurable; refuse any attempt to add a switch for it.
  for v in '.security' '.review.security' '.approvals.security'; do
    [ "$(yq -r "$v // \"\"" "$CFG")" = "" ] || err "${v#.}: security review is mandatory and has no settings"
  done

  if [ -n "$errs" ]; then
    printf 'config: %s is invalid:\n%s' "$CFG" "$errs" >&2
    return 1
  fi
  echo "config: $CFG is valid"
}

case "$CMD" in
  init)
    [ -f "$CFG" ] && { echo "config: $CFG already exists - edit it or delete it first" >&2; exit 1; }
    mkdir -p "$REPO/.compasso"
    cp "$ROOT/templates/project.yaml" "$CFG"
    [ -n "$PROJECT" ] && P="$PROJECT" yq -i '.tracker.project = strenv(P)' "$CFG"
    echo "config: wrote $CFG"
    ;;
  validate) need_cfg; validate ;;
  get) need_cfg; [ -n "$ARG" ] || { echo "config: get needs a path" >&2; exit 1; }; val "$ARG" ;;
  *) echo "usage: config.sh init|validate|get --repo R" >&2; exit 1 ;;
esac
