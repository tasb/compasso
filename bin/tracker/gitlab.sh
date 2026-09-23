#!/usr/bin/env bash
# GitLab tracker adapter. Reads .compasso/project.yaml; talks to GitLab through glab.
#
#   gitlab.sh check         --repo R   the tracker gate: auth, project, role, tier -> JSON on stdout
#   gitlab.sh ensure-labels --repo R   create Compasso's labels that are missing (idempotent)
#
# Exit: 0 ok | 1 config/usage | 2 not logged in | 3 project not found or no access
#       4 role below Developer | 5 tier cannot be detected (set tracker.tier)
set -u

BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CMD="${1:-}"; shift || true
REPO="."
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    *) echo "gitlab: unknown argument '$1'" >&2; exit 1 ;;
  esac
done

"$BIN/config.sh" validate --repo "$REPO" >/dev/null || exit 1
cfg() { "$BIN/config.sh" get --repo "$REPO" "$1"; }
HOST="$(cfg .tracker.host)"
PROJECT="$(cfg .tracker.project)"
TIER_CFG="$(cfg .tracker.tier)"
PID="$(printf '%s' "$PROJECT" | sed 's#/#%2F#g')"

api() { glab api --hostname "$HOST" "$@"; }

# Labels Compasso owns. Free tier does not make scoped labels exclusive, so
# state changes must remove the previous compasso:: label explicitly.
LABELS='compasso::new|#6699cc|Feature waiting for the planner
compasso::clarifying|#f0ad4e|Planner asked questions; waiting for answers in comments
compasso::plan-review|#9b59b6|Breakdown posted; waiting for plan approval
compasso::building|#1f75cb|Stories being built
compasso::verifying|#e67e22|Feature integration, e2e and bug fixing
compasso::done|#2da160|Delivered; test guide attached
type::epic|#34495e|One per sprint
type::feature|#16a085|At most half a sprint
type::bug|#c0392b|Defect found by verification or review
owner::agent|#5b6abf|An agent builds this story
owner::human|#8e6c3a|A person builds this story
owner::either|#7f8c8d|Whoever starts it first
severity::blocker|#a93226|Stops the feature from shipping
severity::major|#d35400|Wrong behaviour with a workaround
severity::minor|#b7950b|Cosmetic or low impact
blocked|#d9534f|Waiting on an external dependency'

check() {
  local user proj level tier plan
  user="$(api user 2>/dev/null | jq -r '.username // empty')"
  [ -n "$user" ] || {
    echo "gitlab: not logged in to $HOST - run: glab auth login --hostname $HOST --web" >&2; return 2; }

  proj="$(api "projects/$PID" 2>/dev/null)"
  [ -n "$(printf '%s' "$proj" | jq -r '.id // empty' 2>/dev/null)" ] || {
    echo "gitlab: project $PROJECT not found on $HOST, or $user has no access to it" >&2; return 3; }

  level="$(printf '%s' "$proj" | jq '[.permissions.project_access.access_level // 0, .permissions.group_access.access_level // 0] | max')"
  [ "$level" -ge 30 ] || {
    echo "gitlab: $user has access level $level on $PROJECT; Compasso needs Developer (30) or above" >&2; return 4; }

  plan="$(api "namespaces/$(printf '%s' "$proj" | jq -r '.namespace.id')" 2>/dev/null | jq -r '.plan // empty')"
  if [ "$TIER_CFG" != "auto" ]; then
    tier="$TIER_CFG"
  else
    case "$plan" in
      free) tier=free ;;
      *premium*|*ultimate*|*gold*|*silver*|*opensource*) tier=premium ;;
      *) echo "gitlab: cannot detect the tier of $PROJECT (plan '${plan:-none}'); set tracker.tier to free or premium" >&2; return 5 ;;
    esac
  fi

  jq -n --arg host "$HOST" --arg user "$user" --arg project "$PROJECT" \
        --argjson id "$(printf '%s' "$proj" | jq '.id')" --argjson level "$level" \
        --arg plan "$plan" --arg tier "$tier" '{
    host: $host, user: $user, project: $project, project_id: $id,
    access_level: $level, plan: $plan, tier: $tier,
    capabilities: {
      epics: ($tier == "premium"), iterations: ($tier == "premium"),
      blocking_links: ($tier == "premium"), exclusive_scoped_labels: ($tier == "premium"),
      child_tasks: true, time_estimates: true
    }}'
}

ensure_labels() {
  local have name color desc created=0 existing=0
  check >/dev/null || return $?
  have="$(api --paginate "projects/$PID/labels?per_page=100" | jq -s -r 'add // [] | .[].name')"
  while IFS='|' read -r name color desc; do
    if printf '%s\n' "$have" | grep -qxF "$name"; then
      existing=$((existing + 1))
    else
      api -X POST "projects/$PID/labels" -f name="$name" -f color="$color" -f description="$desc" >/dev/null ||
        { echo "gitlab: could not create label $name" >&2; return 1; }
      created=$((created + 1))
    fi
  done <<EOF
$LABELS
EOF
  echo "gitlab: labels on $PROJECT - $created created, $existing already present"
}

case "$CMD" in
  check) check ;;
  ensure-labels) ensure_labels ;;
  *) echo "usage: gitlab.sh check|ensure-labels --repo R" >&2; exit 1 ;;
esac
