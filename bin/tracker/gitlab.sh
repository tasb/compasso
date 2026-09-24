#!/usr/bin/env bash
# GitLab tracker adapter. Reads .compasso/project.yaml; talks to GitLab through glab.
#
#   gitlab.sh check         --repo R   the tracker gate: auth, project, role, tier -> JSON on stdout
#   gitlab.sh ensure-labels --repo R   create Compasso's labels that are missing (idempotent)
#   gitlab.sh push-plan     --repo R   create or update .compasso/plan.yaml in GitLab; ids are written back
#   gitlab.sh story         --repo R --iid N                      a story, its resolved coverage and open dependencies -> JSON
#   gitlab.sh set-state     --repo R --iid N --state S            S: building | in-review; drops the other compasso:: states
#   gitlab.sh open-mr       --repo R --iid N --branch B --body-file F   create or update the story's MR -> JSON {iid, web_url}
#   gitlab.sh followup      --repo R --parent N --title T --body-file F [--labels a,b]  a task under N (a minor finding, a bug) -> iid
#   gitlab.sh merge         --repo R --mr N                       merge when the pipeline succeeds (approvals.merge: agent only)
#   gitlab.sh mr-info       --repo R --mr N                       branches, author and the issues it closes -> JSON
#   gitlab.sh comment       --repo R --mr N|--iid N --body-file F  post F as a comment on a merge request or an issue
#   gitlab.sh sprint-sync   --repo R [--milestone S20]            what can be built now, what waits and on whom -> JSON
#
# Exit: 0 ok | 1 config/usage | 2 not logged in | 3 project not found or no access
#       4 role below Developer | 5 tier cannot be detected (set tracker.tier)
set -u

BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CMD="${1:-}"; shift || true
REPO="." IID="" STATE="" BRANCH="" BODY="" TITLE="" PARENT="" MR="" LABELS_ARG="owner::either" MILESTONE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --iid) IID="$2"; shift 2 ;;
    --state) STATE="$2"; shift 2 ;;
    --branch) BRANCH="$2"; shift 2 ;;
    --body-file) BODY="$2"; shift 2 ;;
    --title) TITLE="$2"; shift 2 ;;
    --parent) PARENT="$2"; shift 2 ;;
    --mr) MR="$2"; shift 2 ;;
    --labels) LABELS_ARG="$2"; shift 2 ;;
    --milestone) MILESTONE="$2"; shift 2 ;;
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
compasso::building|#1f75cb|Stories being built
compasso::in-review|#3498db|Story merge request open; waiting for approval
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
type::blocker|#6c3483|Something outside the plan a story waits for
priority::urgent|#e74c3c|Needs action now
blocked|#d9534f|Waiting on a blocker task'

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

sprint() { echo "S$(pget .epic.sprint.number)"; }   # sprint number 20 -> "S20"

milestone() { # -> milestone id
  local id name start end
  id="$(pget '.epic.gitlab.milestone // ""')"
  name="$(sprint)"; start="$(pget .epic.sprint.start)"; end="$(pget .epic.sprint.end)"
  if [ -z "$id" ]; then
    id="$(api "projects/$PID/milestones?title=$name" | jq -r '.[0].id // empty')"
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

member_id() { # username -> user id of a member of the project
  local uid
  uid="$(api "users?username=$1" | jq -r '.[0].id // empty')"
  [ -n "$uid" ] || { echo "gitlab: no GitLab user '$1'" >&2; return 1; }
  api "projects/$PID/members/all/$uid" >/dev/null 2>&1 || { echo "gitlab: $1 is not a member of $PROJECT" >&2; return 1; }
  echo "$uid"
}

upsert_issue() { # iid-or-empty title description milestone type assignee-id-or-empty labels... -> "iid id"
  local iid="$1" title="$2" desc="$3" ms="$4" type="$5" who="$6"; shift 6
  local out assign=""
  [ -n "$who" ] && assign="assignee_ids=$who"
  if [ -z "$iid" ]; then
    out="$(api -X POST "projects/$PID/issues" -f title="$title" -f description="$desc" \
      ${ms:+-f "milestone_id=$ms"} -f issue_type="$type" -f labels="$(IFS=,; echo "$*")" ${assign:+-f "$assign"})"
  else
    out="$(api -X PUT "projects/$PID/issues/$iid" -f title="$title" -f description="$desc" \
      ${ms:+-f "milestone_id=$ms"} -f add_labels="$(IFS=,; echo "$*")" ${assign:+-f "$assign"})"
  fi
  printf '%s' "$out" | jq -r 'if .iid then "\(.iid) \(.id)" else empty end'
}

push_plan() {
  local info tier ms n i f b s key iid id fid title desc labels ctx res owner feats uid needed
  local iids='{}' stale was parent
  "$BIN/plan-check.sh" --repo "$REPO" >/dev/null || {
    echo "gitlab: the plan does not pass plan-check - run: bin/plan-check.sh --repo $REPO" >&2; return 1; }
  info="$(check)" || return $?
  ensure_labels >/dev/null || return $?   # labels added in a newer Compasso exist before they are applied
  # Premium features (native epics, iterations, blocks links) are not available
  # yet: every tier is pushed the Free way until they can be tested on Premium.
  # tier="$(printf '%s' "$info" | jq -r .tier)"
  tier=free
  ms="$(milestone)" || return 1

  # features
  n="$(pget '.features | length')"; i=0
  while [ "$i" -lt "$n" ]; do
    f="$(yq -o=json ".features[$i]" "$PLAN")"
    key="$(jq -r .key <<<"$f")"; title="$(jq -r .title <<<"$f")"
    desc="$(render feature "$f" '{}')"
    res="$(upsert_issue "$(jq -r '.gitlab // ""' <<<"$f")" "$title" "$desc" "$ms" issue "" type::feature)"
    [ -n "$res" ] || { echo "gitlab: could not write feature $key" >&2; return 1; }
    iid="${res% *}"; id="${res#* }"
    pset '(.features[] | select(.key == strenv(K)) | .gitlab) = (strenv(V) | tonumber)' "$key" "$iid"
    iids="$(jq -c --arg k "$key" --argjson v "$iid" --argjson id "$id" '.[$k] = $v | .["id:" + $k] = $id' <<<"$iids")"
    echo "gitlab: feature $key -> #$iid"
    i=$((i + 1))
  done

  # blockers, before the stories that link to them; "Needed for" is filled in after the stories
  n="$(pget '.blockers // [] | length')"; i=0
  while [ "$i" -lt "$n" ]; do
    b="$(yq -o=json ".blockers[$i]" "$PLAN")"
    key="$(jq -r .key <<<"$b")"
    uid="$(member_id "$(jq -r .assignee <<<"$b")")" || return 1
    iid="$(jq -r '.gitlab // ""' <<<"$b")"
    if [ -z "$iid" ]; then
      res="$(upsert_issue "" "$(jq -r .title <<<"$b")" "$(render blocker "$b" '{"needed": []}')" "$ms" task "$uid" type::blocker priority::urgent)"
      [ -n "$res" ] || { echo "gitlab: could not write blocker $key" >&2; return 1; }
      iid="${res% *}"
      pset '(.blockers[] | select(.key == strenv(K)) | .gitlab) = (strenv(V) | tonumber)' "$key" "$iid"
    fi
    iids="$(jq -c --arg k "$key" --argjson v "$iid" '.[$k] = $v' <<<"$iids")"
    i=$((i + 1))
  done

  # stories, in dependency order so every dependency already has an iid
  for key in $("$BIN/plan-check.sh" --repo "$REPO" --json | jq -r '.waves[][]'); do
    s="$(K="$key" yq -o=json '.features[] as $f | $f.stories[] | select(.key == strenv(K)) | . + {"feature": $f.key}' "$PLAN")"
    title="$(jq -r .title <<<"$s")"; owner="$(jq -r .owner <<<"$s")"
    ctx="$(jq -nc --arg tier "$tier" --argjson iids "$iids" '{tier: $tier, iids: $iids}')"
    desc="$(render story "$s" "$ctx")"
    labels="owner::$owner"
    [ "$(jq '.blocked_by // [] | length' <<<"$s")" -gt 0 ] && labels="$labels,blocked"
    iid="$(jq -r '.gitlab // ""' <<<"$s")"
    res="$(upsert_issue "$iid" "$title" "$desc" "$ms" task "" $labels)"
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

    # Premium only, not available yet (see the tier note above): dependencies as blocks links.
    # if [ "$tier" = premium ]; then
    #   linked="$(api "projects/$PID/issues/$iid/links" | jq -r '.[] | select(.link_type == "is_blocked_by") | .iid')"
    #   for d in $(jq -r '.depends_on // [] | .[]' <<<"$s"); do
    #     case "$d" in \#*) d="${d#\#}" ;; *) d="$(jq -r --arg k "$d" '.[$k]' <<<"$iids")" ;; esac
    #     printf '%s\n' "$linked" | grep -qxF "$d" && continue
    #     api -X POST "projects/$PID/issues/$d/links" -f target_project_id="$(printf '%s' "$info" | jq -r .project_id)" \
    #       -f target_issue_iid="$iid" -f link_type=blocks >/dev/null ||
    #       { echo "gitlab: could not link #$d as blocking story $key" >&2; return 1; }
    #   done
    # fi
    echo "gitlab: story $key -> #$iid"
  done

  # blockers again: final description with the stories they hold up, and the assignee
  n="$(pget '.blockers // [] | length')"; i=0
  while [ "$i" -lt "$n" ]; do
    b="$(yq -o=json ".blockers[$i]" "$PLAN")"
    key="$(jq -r .key <<<"$b")"
    needed="$(yq -o=json . "$PLAN" | jq -c --arg k "$key" '[.features[].stories[] | select((.blocked_by // []) | index($k)) | {iid: .gitlab, title}]')"
    uid="$(member_id "$(jq -r .assignee <<<"$b")")" || return 1
    res="$(upsert_issue "$(jq -r .gitlab <<<"$b")" "$(jq -r .title <<<"$b")" \
      "$(render blocker "$b" "$(jq -nc --argjson needed "$needed" '{needed: $needed}')")" "$ms" task "$uid" type::blocker priority::urgent)"
    [ -n "$res" ] || { echo "gitlab: could not write blocker $key" >&2; return 1; }
    echo "gitlab: blocker $key -> #${res% *} (assigned to $(jq -r .assignee <<<"$b"))"
    i=$((i + 1))
  done

  # epic, last, because it lists the features with their iids and hours
  feats="$(yq -o=json . "$PLAN" | jq -c '[.features[] | {iid: .gitlab, title, hours: ([.stories[].estimate_h] | add)}]')"
  ctx="$(jq -nc --argjson features "$feats" --argjson cap "$(cfg .sprint.capacity_hours)" '{features: $features, capacity: $cap}')"
  desc="$(render epic "$(yq -o=json .epic "$PLAN")" "$ctx")"
  res="$(upsert_issue "$(pget '.epic.gitlab.issue // ""')" "$(sprint): $(pget .epic.goal)" "$desc" "$ms" issue "" type::epic)"
  [ -n "$res" ] || { echo "gitlab: could not write the epic" >&2; return 1; }
  pset '.epic.gitlab.issue = (strenv(V) | tonumber)' "" "${res% *}"
  echo "gitlab: epic $(pget .epic.key) -> #${res% *} (milestone $(sprint))"
}


# ---------- story flow ----------
need() { for v in "$@"; do eval "[ -n \"\$$v\" ]" || { echo "gitlab: $CMD needs --$(echo "$v" | tr 'A-Z_' 'a-z-')" >&2; exit 1; }; done; }

parent_iid() { # work item id -> parent iid, or empty
  api graphql -f query="query { workItem(id: \"gid://gitlab/WorkItem/$1\") { widgets { ... on WorkItemWidgetHierarchy { parent { iid } } } } }" |
    jq -r '[.data.workItem.widgets[]? | .parent?.iid // empty][0] // empty'
}

story() {
  local issue parsed feature="" fcov="null" epic="" ecov="null" ms open='[]' d dj kind
  need IID
  check >/dev/null || return $?
  issue="$(api "projects/$PID/issues/$IID")"
  [ -n "$(jq -r '.iid // empty' <<<"$issue" 2>/dev/null)" ] || { echo "gitlab: no work item #$IID in $PROJECT" >&2; return 1; }
  parsed="$(jq -r '.description // ""' <<<"$issue" | jq -Rs -f "$BIN/parse.jq")"

  feature="$(parent_iid "$(jq -r .id <<<"$issue")")"
  [ -n "$feature" ] && fcov="$(api "projects/$PID/issues/$feature" | jq -r '.description // ""' | jq -Rs -f "$BIN/parse.jq" | jq .coverage)"
  ms="$(jq -r '.milestone.title // empty' <<<"$issue")"
  if [ -n "$ms" ]; then
    dj="$(api "projects/$PID/issues?milestone=$ms&labels=type::epic&state=all" | jq '.[0] // empty')"
    if [ -n "$dj" ]; then
      epic="$(jq -r .iid <<<"$dj")"
      ecov="$(jq -r '.description // ""' <<<"$dj" | jq -Rs -f "$BIN/parse.jq" | jq .coverage)"
    fi
  fi

  for d in $(jq -r '.depends_on[]' <<<"$parsed") $(jq -r '.blocked_by[] | "b\(.)"' <<<"$parsed"); do
    dj="$(api "projects/$PID/issues/${d#b}")" || { echo "gitlab: #${d#b} referenced by #$IID does not exist" >&2; return 1; }
    [ "$(jq -r .state <<<"$dj")" = opened ] || continue
    kind=depends_on; [ "${d#b}" = "$d" ] || kind=blocked_by
    open="$(jq -c --argjson i "${d#b}" --arg t "$(jq -r .title <<<"$dj")" --arg k "$kind" '. + [{iid: $i, title: $t, kind: $k}]' <<<"$open")"
  done

  jq -n --argjson issue "$issue" --argjson s "$parsed" --arg feature "$feature" --argjson fcov "$fcov" \
        --arg epic "$epic" --argjson ecov "$ecov" --argjson open "$open" --argjson dflt "$(cfg .coverage.min_changed)" '{
    iid: $issue.iid, id: $issue.id, title: $issue.title, state: $issue.state, type: $issue.issue_type,
    kind: (if ($issue.labels | index("type::bug")) then "bug" else "story" end),
    labels: $issue.labels, milestone: ($issue.milestone.title // null),
    feature: (if $feature == "" then null else ($feature | tonumber) end),
    epic: (if $epic == "" then null else ($epic | tonumber) end),
    # a bug is built like a story: its Expected is what the tests must pin, unit tests at least
    story: (if ($issue.labels | index("type::bug")) then $s
             | .acceptance = (if (.acceptance | length) > 0 then .acceptance else .expected end)
             | .tests = (if (.tests | length) > 0 then .tests else ["unit"] end)
           else $s end),
    coverage_min: ([$s.coverage, $fcov, $ecov, $dflt] | map(select(. != null)) | first),
    open_dependencies: $open
  }'
}

set_state() {
  local all="compasso::new compasso::building compasso::in-review compasso::verifying compasso::done"
  need IID STATE
  case " $all " in *" compasso::$STATE "*) : ;; *) echo "gitlab: unknown state '$STATE'" >&2; return 1 ;; esac
  api -X PUT "projects/$PID/issues/$IID" -f add_labels="compasso::$STATE" \
    -f remove_labels="$(printf '%s\n' $all | grep -vx "compasso::$STATE" | paste -sd, -)" >/dev/null ||
    { echo "gitlab: could not set #$IID to $STATE" >&2; return 1; }
  echo "gitlab: #$IID is $STATE"
}

open_mr() {
  local title target mr out
  need IID BRANCH BODY
  [ -f "$BODY" ] || { echo "gitlab: no body file $BODY" >&2; return 1; }
  title="$(api "projects/$PID/issues/$IID" | jq -r '.title // empty')"
  [ -n "$title" ] || { echo "gitlab: no work item #$IID" >&2; return 1; }
  target="$(api "projects/$PID" | jq -r .default_branch)"
  mr="$(api "projects/$PID/merge_requests?source_branch=$BRANCH&state=opened" | jq -r '.[0].iid // empty')"
  if [ -n "$mr" ]; then
    out="$(api -X PUT "projects/$PID/merge_requests/$mr" -f description="$(cat "$BODY")")"
  else
    out="$(api -X POST "projects/$PID/merge_requests" -f source_branch="$BRANCH" -f target_branch="$target" \
      -f title="$title" -f description="$(cat "$BODY")" -f remove_source_branch=true)"
  fi
  printf '%s' "$out" | jq -e -c '{iid, web_url}' 2>/dev/null || { echo "gitlab: could not open the merge request for $BRANCH" >&2; return 1; }
}

followup() {
  local res pj
  need PARENT TITLE BODY
  pj="$(api "projects/$PID/issues/$PARENT")"
  [ -n "$(jq -r '.iid // empty' <<<"$pj" 2>/dev/null)" ] || { echo "gitlab: no work item #$PARENT" >&2; return 1; }
  res="$(upsert_issue "" "$TITLE" "$(cat "$BODY")" "$(jq -r '.milestone.id // ""' <<<"$pj")" task "" $(printf '%s' "$LABELS_ARG" | tr ',' ' '))"
  [ -n "$res" ] || { echo "gitlab: could not create the follow-up" >&2; return 1; }
  api graphql -f query="mutation { workItemUpdate(input: { id: \"gid://gitlab/WorkItem/${res#* }\", hierarchyWidget: { parentId: \"gid://gitlab/WorkItem/$(jq -r .id <<<"$pj")\" } }) { errors } }" |
    jq -e '(.data.workItemUpdate.errors // ["no response"]) | length == 0' >/dev/null ||
    { echo "gitlab: created #${res% *} but could not attach it to #$PARENT" >&2; return 1; }
  echo "${res% *}"
}

merge() {
  need MR
  [ "$(cfg .approvals.merge)" = agent ] || { echo "gitlab: approvals.merge is human - a person merges this merge request" >&2; return 1; }
  [ -n "$BODY" ] && [ -f "$BODY" ] || { echo "gitlab: merge needs --body-file with the review findings" >&2; return 1; }
  "$BIN/review-gate.sh" --findings "$BODY" --for merge || return 1
  api -X PUT "projects/$PID/merge_requests/$MR/merge" -f merge_when_pipeline_succeeds=true >/dev/null ||
    { echo "gitlab: could not merge !$MR" >&2; return 1; }
  echo "gitlab: !$MR merges when its pipeline succeeds"
}


mr_info() {
  local mr closes
  need MR
  mr="$(api "projects/$PID/merge_requests/$MR")"
  [ -n "$(jq -r '.iid // empty' <<<"$mr" 2>/dev/null)" ] || { echo "gitlab: no merge request !$MR in $PROJECT" >&2; return 1; }
  closes="$(api "projects/$PID/merge_requests/$MR/closes_issues" | jq -c '[.[].iid]')" || closes='[]'
  jq -c --argjson closes "$closes" '{iid, title, state, source_branch, target_branch, web_url, author: .author.username, draft, closes: $closes}' <<<"$mr"
}

comment() { # on a merge request (--mr) or an issue (--iid)
  local target where
  need BODY
  [ -f "$BODY" ] || { echo "gitlab: no body file $BODY" >&2; return 1; }
  if [ -n "$MR" ]; then target="merge_requests/$MR"; where="!$MR"
  elif [ -n "$IID" ]; then target="issues/$IID"; where="#$IID"
  else echo "gitlab: comment needs --mr or --iid" >&2; return 1; fi
  api -X POST "projects/$PID/$target/notes" -f body="$(cat "$BODY")" | jq -e -r '.id' >/dev/null ||
    { echo "gitlab: could not comment on $where" >&2; return 1; }
  echo "gitlab: commented on $where"
}


sprint_sync() {
  local ms items tasks enriched ext='[]' i id d cleaned='[]' parallel
  check >/dev/null || return $?
  ms="$MILESTONE"
  [ -n "$ms" ] || ms="S$(yq -r '.epic.sprint.number // ""' "$REPO/.compasso/plan.yaml" 2>/dev/null)"
  [ "$ms" != "S" ] || { echo "gitlab: sprint-sync needs --milestone or a .compasso/plan.yaml" >&2; return 1; }
  items="$(api --paginate "projects/$PID/issues?milestone=$ms&state=all&per_page=100" | jq -s 'add // []')"
  [ "$(jq length <<<"$items")" -gt 0 ] || { echo "gitlab: no work items in milestone $ms" >&2; return 1; }

  # every task gets its parent and its parsed description
  enriched='[]'
  for i in $(jq -r '.[].iid' <<<"$items"); do
    d="$(jq --argjson i "$i" '.[] | select(.iid == $i)' <<<"$items")"
    id="$(jq -r .id <<<"$d")"
    d="$(jq --argjson p "$(jq -r '.description // ""' <<<"$d" | jq -Rs -f "$BIN/parse.jq")" \
            --arg parent "$( [ "$(jq -r .issue_type <<<"$d")" = task ] && parent_iid "$id" )" \
      '. + {parsed: $p, parent: (if $parent == "" then null else ($parent | tonumber) end)}' <<<"$d")"
    enriched="$(jq -c --argjson d "$d" '. + [$d]' <<<"$enriched")"
  done

  # dependencies outside the milestone: look up their state
  for i in $(jq -r '[.[].iid] as $in | [.[].parsed | (.depends_on + .blocked_by)[]] | unique | map(select(. as $x | $in | index($x) | not)) | .[]' <<<"$enriched"); do
    d="$(api "projects/$PID/issues/$i")" || { echo "gitlab: #$i is referenced in $ms but does not exist" >&2; return 1; }
    ext="$(jq -c --argjson d "$d" '. + [{iid: $d.iid, state: $d.state, title: $d.title}]' <<<"$ext")"
  done

  # closed stories and bugs keep no in-progress state label
  for i in $(jq -r '.[] | select(.state == "closed" and .issue_type == "task")
      | select(.labels | index("compasso::building") or index("compasso::in-review")) | .iid' <<<"$enriched"); do
    api -X PUT "projects/$PID/issues/$i" -f remove_labels="compasso::building,compasso::in-review" >/dev/null ||
      { echo "gitlab: could not clear the state of #$i" >&2; return 1; }
    cleaned="$(jq -c --argjson i "$i" '. + [$i]' <<<"$cleaned")"
  done

  parallel="$(cfg '.sprint.parallel // 2')"
  jq -n --arg ms "$ms" --argjson items "$enriched" --argjson ext "$ext" --argjson cleaned "$cleaned" \
        --argjson parallel "$parallel" -f "$BIN/sprint.jq"
}


case "$CMD" in
  check) check ;;
  ensure-labels) ensure_labels ;;
  push-plan) push_plan ;;
  story) story ;;
  set-state) set_state ;;
  open-mr) open_mr ;;
  followup) followup ;;
  merge) merge ;;
  mr-info) mr_info ;;
  comment) comment ;;
  sprint-sync) sprint_sync ;;
  *) echo "usage: gitlab.sh check|ensure-labels|push-plan|story|set-state|open-mr|followup|merge|mr-info|comment|sprint-sync --repo R ..." >&2; exit 1 ;;
esac
