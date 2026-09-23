#!/usr/bin/env bash
# GitLab tracker adapter. Reads .compasso/project.yaml; talks to GitLab through glab.
#
#   gitlab.sh check         --repo R   the tracker gate: auth, project, role, tier -> JSON on stdout
#   gitlab.sh ensure-labels --repo R   create Compasso's labels that are missing (idempotent)
#   gitlab.sh push-plan     --repo R   create or update .compasso/plan.yaml in GitLab; ids are written back
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

# ---------- push-plan ----------
# Creates or updates the plan's items in GitLab and writes their ids back to
# plan.yaml after each one, so a re-run updates instead of duplicating and a
# failed run resumes where it stopped.
PLAN="$REPO/.compasso/plan.yaml"

pget() { yq -r "$1" "$PLAN"; }
pset() { K="$2" V="$3" yq -i "$1" "$PLAN"; }   # expression uses strenv(K) and strenv(V)

render() { # kind item-json ctx-json
  jq -rn --arg kind "$1" --argjson item "$2" --argjson ctx "$3" \
    '{kind: $kind, item: $item, ctx: $ctx}' | jq -r -f "$BIN/render.jq"
}

duration() { # hours (may be fractional) -> GitLab duration, e.g. 4.5 -> 4h30m
  jq -rn --argjson h "$1" '($h | floor) as $w | (($h - $w) * 60 | round) as $m
    | "\($w)h" + (if $m > 0 then "\($m)m" else "" end)'
}

milestone() { # -> milestone id
  local id name start end
  id="$(pget '.epic.gitlab.milestone // ""')"
  name="$(pget .epic.sprint.name)"; start="$(pget .epic.sprint.start)"; end="$(pget .epic.sprint.end)"
  if [ -z "$id" ]; then
    id="$(api "projects/$PID/milestones?title=$(printf '%s' "$name" | jq -sRr @uri)" | jq -r '.[0].id // empty')"
    [ -n "$id" ] || id="$(api -X POST "projects/$PID/milestones" -f title="$name" \
      -f start_date="$start" -f due_date="$end" | jq -r '.id // empty')"
    [ -n "$id" ] || { echo "gitlab: could not create milestone $name" >&2; return 1; }
    pset '.epic.gitlab.milestone = (strenv(V) | tonumber)' "" "$id"
  else
    api -X PUT "projects/$PID/milestones/$id" -f title="$name" -f start_date="$start" -f due_date="$end" >/dev/null ||
      { echo "gitlab: could not update milestone $name" >&2; return 1; }
  fi
  echo "$id"
}

upsert_issue() { # iid-or-empty title description milestone type labels... -> "iid id"
  local iid="$1" title="$2" desc="$3" ms="$4" type="$5"; shift 5
  local out
  if [ -z "$iid" ]; then
    out="$(api -X POST "projects/$PID/issues" -f title="$title" -f description="$desc" \
      -f milestone_id="$ms" -f issue_type="$type" -f labels="$(IFS=,; echo "$*")")"
  else
    out="$(api -X PUT "projects/$PID/issues/$iid" -f title="$title" -f description="$desc" \
      -f milestone_id="$ms" -f add_labels="$(IFS=,; echo "$*")")"
  fi
  printf '%s' "$out" | jq -r 'if .iid then "\(.iid) \(.id)" else empty end'
}

push_plan() {
  local info tier ms nf ns fi si f s key iid id fid title desc labels deps d ctx res owner feats=""
  local iids='{}' stale linked was parent
  "$BIN/plan-check.sh" --repo "$REPO" >/dev/null || {
    echo "gitlab: the plan does not pass plan-check - run: bin/plan-check.sh --repo $REPO" >&2; return 1; }
  info="$(check)" || return $?
  tier="$(printf '%s' "$info" | jq -r .tier)"
  ms="$(milestone)" || return 1

  # features
  nf="$(pget '.features | length')"
  fi=0
  while [ "$fi" -lt "$nf" ]; do
    f="$(yq -o=json ".features[$fi]" "$PLAN")"
    key="$(jq -r .key <<<"$f")"; title="$(jq -r .title <<<"$f")"
    desc="$(render feature "$f" '{}')"
    res="$(upsert_issue "$(jq -r '.gitlab // ""' <<<"$f")" "$title" "$desc" "$ms" issue type::feature)"
    [ -n "$res" ] || { echo "gitlab: could not write feature $key" >&2; return 1; }
    iid="${res% *}"; id="${res#* }"
    pset '(.features[] | select(.key == strenv(K)) | .gitlab) = (strenv(V) | tonumber)' "$key" "$iid"
    iids="$(jq -c --arg k "$key" --argjson v "$iid" --argjson id "$id" '.[$k] = $v | .["id:" + $k] = $id' <<<"$iids")"
    echo "gitlab: feature $key -> #$iid"
    fi=$((fi + 1))
  done

  # stories, in dependency order so every dependency already has an iid
  for key in $("$BIN/plan-check.sh" --repo "$REPO" --json | jq -r '.waves[][]'); do
    s="$(K="$key" yq -o=json '.features[] as $f | $f.stories[] | select(.key == strenv(K)) | . + {"feature": $f.key}' "$PLAN")"
    title="$(jq -r .title <<<"$s")"; owner="$(jq -r .owner <<<"$s")"
    ctx="$(jq -nc --arg tier "$tier" --argjson iids "$iids" '{tier: $tier, iids: $iids}')"
    desc="$(render story "$s" "$ctx")"
    labels="owner::$owner"
    [ -n "$(jq -r '.blocked // ""' <<<"$s")" ] && labels="$labels,blocked"
    iid="$(jq -r '.gitlab // ""' <<<"$s")"
    res="$(upsert_issue "$iid" "$title" "$desc" "$ms" task $labels)"
    [ -n "$res" ] || { echo "gitlab: could not write story $key" >&2; return 1; }
    was="$iid"; iid="${res% *}"
    pset '(.features[].stories[] | select(.key == strenv(K)) | .gitlab) = (strenv(V) | tonumber)' "$key" "$iid"
    iids="$(jq -c --arg k "$key" --argjson v "$iid" '.[$k] = $v' <<<"$iids")"
    # attach to the feature unless it already is: GitLab refuses a repeat ("already assigned"),
    # and checking every push repairs a run that failed between create and attach
    fid="$(jq -r --arg k "id:$(jq -r .feature <<<"$s")" '.[$k]' <<<"$iids")"
    parent="$(api graphql -f query="query { workItem(id: \"gid://gitlab/WorkItem/${res#* }\") { widgets { ... on WorkItemWidgetHierarchy { parent { id } } } } }" |
      jq -r '[.data.workItem.widgets[]? | .parent?.id // empty][0] // empty')"
    if [ "$parent" != "gid://gitlab/WorkItem/$fid" ]; then
      api graphql -f query="mutation { workItemUpdate(input: { id: \"gid://gitlab/WorkItem/${res#* }\", hierarchyWidget: { parentId: \"gid://gitlab/WorkItem/$fid\" } }) { errors } }" |
        jq -e '(.data.workItemUpdate.errors // ["no response"]) | length == 0' >/dev/null ||
        { echo "gitlab: could not attach story $key to its feature" >&2; return 1; }
    fi
    if [ -n "$was" ]; then
      # an owner change must drop the previous owner label; Free does not do it for scoped labels
      stale="$(printf 'owner::agent\nowner::human\nowner::either\nblocked\n' | grep -vx "owner::$owner")"
      case ",$labels," in *,blocked,*) stale="$(printf '%s\n' "$stale" | grep -vx blocked)" ;; esac
      api -X PUT "projects/$PID/issues/$iid" -f remove_labels="$(printf '%s\n' "$stale" | paste -sd, -)" >/dev/null ||
        { echo "gitlab: could not update the labels of story $key" >&2; return 1; }
    fi
    api -X POST "projects/$PID/issues/$iid/time_estimate?duration=$(duration "$(jq .estimate_h <<<"$s")")" >/dev/null ||
      { echo "gitlab: could not set the estimate of story $key" >&2; return 1; }

    if [ "$tier" = premium ]; then
      linked="$(api "projects/$PID/issues/$iid/links" | jq -r '.[] | select(.link_type == "is_blocked_by") | .iid')"
      for d in $(jq -r '.depends_on // [] | .[]' <<<"$s"); do
        case "$d" in \#*) d="${d#\#}" ;; *) d="$(jq -r --arg k "$d" '.[$k]' <<<"$iids")" ;; esac
        printf '%s\n' "$linked" | grep -qxF "$d" && continue
        api -X POST "projects/$PID/issues/$d/links" -f target_project_id="$(printf '%s' "$info" | jq -r .project_id)" \
          -f target_issue_iid="$iid" -f link_type=blocks >/dev/null ||
          { echo "gitlab: could not link #$d as blocking story $key" >&2; return 1; }
      done
    fi
    echo "gitlab: story $key -> #$iid"
  done

  # epic, last, because it lists the features with their iids and hours
  feats="$(yq -o=json . "$PLAN" | jq -c '[.features[] | {iid: .gitlab, title, hours: ([.stories[].estimate_h] | add)}]')"
  ctx="$(jq -nc --argjson features "$feats" --argjson cap "$(cfg .sprint.capacity_hours)" '{features: $features, capacity: $cap}')"
  desc="$(render epic "$(yq -o=json .epic "$PLAN")" "$ctx")"
  res="$(upsert_issue "$(pget '.epic.gitlab.issue // ""')" "$(pget .epic.sprint.name): $(pget .epic.goal)" "$desc" "$ms" issue type::epic)"
  [ -n "$res" ] || { echo "gitlab: could not write the epic" >&2; return 1; }
  pset '.epic.gitlab.issue = (strenv(V) | tonumber)' "" "${res% *}"
  echo "gitlab: epic $(pget .epic.key) -> #${res% *} (milestone $ms)"
}


case "$CMD" in
  check) check ;;
  ensure-labels) ensure_labels ;;
  push-plan) push_plan ;;
  *) echo "usage: gitlab.sh check|ensure-labels|push-plan --repo R" >&2; exit 1 ;;
esac
