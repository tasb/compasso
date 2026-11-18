#!/usr/bin/env bash
# GitLab tracker adapter. Reads .compasso/project.yaml; talks to GitLab through glab.
#
#   gitlab.sh check         --repo R   the tracker gate: auth, project, role, tier -> JSON on stdout
#   gitlab.sh ensure-labels --repo R   create Compasso's labels that are missing (idempotent)
#   gitlab.sh push-plan     --repo R   create or update .compasso/plan.yaml in GitLab; ids are written back
#   gitlab.sh push-backlog  --repo R   create or update .compasso/backlog.yaml's features, outside any sprint
#   gitlab.sh story         --repo R --iid N                      a story, its resolved coverage and open dependencies -> JSON
#   gitlab.sh set-state     --repo R --iid N --state S            S: backlog | building | in-review; drops the other compasso:: states
#   gitlab.sh open-mr       --repo R --iid N --branch B --body-file F   create or update the story's MR to the default branch -> JSON {iid, web_url}
#   gitlab.sh mr-info       --repo R --mr N                       branches, author and the issues it closes -> JSON
#   gitlab.sh close         --repo R --iid N --body-file F        post F on the issue, then close it
#   gitlab.sh mr-checks     --repo R --mr N                       its last commit's pipeline and whether it conflicts with its target
#                                                                 -> {pipeline: success|failed|running|none, conflicts}
#   gitlab.sh main-pipeline --repo R                              the default branch's last finished pipeline and, when it failed, the
#                                                                 merge request that broke it -> {pipeline: success|failed|none, sha,
#                                                                 web_url, broken_by: {sha, mr, closes} | null}
#   gitlab.sh comment       --repo R --mr N|--iid N --body-file F  post F as a comment on a merge request or an issue
#   gitlab.sh sprint-sync   --repo R [--milestone S20] [--parent F] what can be built now, what waits and on whom -> JSON
#   gitlab.sh sprint-items  --repo R --milestone S20              the sprint's work items with their label history (the report)
#   gitlab.sh sprint-done   --repo R --milestone S19              hours done in a sprint, or null
#   gitlab.sh human-ask     --repo R --key K [--iid N] --title T --body-file F   open, or update, the needs::human issue for (K, N),
#                                                                 assigned to people.ask; N gets needs::human (bin/human.sh) -> {iid, web_url, created}
#   gitlab.sh assign        --repo R --iid N --name D             give N to developer D: dev::D and the backlog state, no other
#                                                                 developer's label (the tech lead, bin/run.sh's assign job)
#   gitlab.sh human-done    --repo R --iid N                      the question about N was answered: N loses needs::human
#   gitlab.sh snapshot      --repo R                              open work items, open merge requests and main's pipeline, in four
#                                                                 reads (bin/run.sh, before it starts a model) -> JSON (bin/snapshot.jq)
#   gitlab.sh mr-merge      --repo R --mr N                       merge when the pipeline succeeds, never after it failed (the tech lead, bin/lead.sh)
#   gitlab.sh mr-label      --repo R --mr N [--add L] [--remove L]   only compasso::rework and compasso::fix-main, the labels bin/run.sh reads
#   gitlab.sh after-mvp     --repo R --title T --body-file F      add F as a comment on the one open after-MVP list, opened (titled T)
#                                                                 when there is none -> {iid, web_url}
#   gitlab.sh reopen        --repo R --iid N                      reopen a closed work item (a story whose merge was reverted)
#   gitlab.sh harden-feature --repo R --title T                  the one open hardening feature, opened (titled T) when there is none
#                                                                 -> {iid, web_url}
#   gitlab.sh add-story     --repo R --parent F --title T --from S.json   a story under feature F, in its sprint, with its developer
#                                                                 (S: the plan's story fields; bin/lead.sh story checks them) -> {iid, web_url}
#   gitlab.sh comments      --repo R --iid N|--mr N               [{id, body, author, at, member}], oldest first
#
# Exit: 0 ok | 1 config/usage | 2 not logged in | 3 project not found or no access
#       4 role below Developer | 5 tier cannot be detected (set tracker.tier)
set -u
case "${1:-}" in -h|--help) sed -n '2,/^set -u/s/^# \{0,1\}//p' "$0"; exit 0 ;; esac   # the header above is the help

BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CMD="${1:-}"; shift || true
REPO="." IID="" STATE="" BRANCH="" BODY="" TITLE="" PARENT="" MR="" MILESTONE="" READ_ONLY=0 NAME="" ADD="" REMOVE="" KEY="" FROM=""
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
    --milestone) MILESTONE="$2"; shift 2 ;;
    --read-only) READ_ONLY=1; shift ;;
    --name) NAME="$2"; shift 2 ;;
    --add) ADD="$2"; shift 2 ;;
    --remove) REMOVE="$2"; shift 2 ;;
    --key) KEY="$2"; shift 2 ;;
    --from) FROM="$2"; shift 2 ;;
    *) echo "gitlab: unknown argument '$1'" >&2; exit 1 ;;
  esac
done

"$BIN/config.sh" validate --repo "$REPO" >/dev/null || exit 1
# this agent's own tracker account, when it has one (bin/persona.sh account); else the machine's login
acct="$("$BIN/persona.sh" env --repo "$REPO")" || { echo "gitlab: cannot read this checkout's account token" >&2; exit 2; }
eval "$acct"
cfg() { "$BIN/config.sh" get --repo "$REPO" "$1"; }
HOST="$(cfg .tracker.host)"
PROJECT="$(cfg .tracker.project)"
TIER_CFG="$(cfg .tracker.tier)"
PID="$(printf '%s' "$PROJECT" | sed 's#/#%2F#g')"

api() { glab api --hostname "$HOST" "$@"; }

# Labels Compasso owns (name|colour|description), shared with the GitHub adapter. Free tier does
# not make scoped labels exclusive, so state changes remove the previous compasso:: label explicitly.
LABELS="$(cat "$BIN/tracker/labels.txt")"
NAMES="$("$BIN/locale.sh" --names)"                   # work-item names in every language, for reading
LOC="$("$BIN/locale.sh" --repo "$REPO")" || exit 1    # the project's language, for writing

# a team project assigns work by dev::<name> labels and uses no owner:: labels but owner::human,
# work for a person no agent is assigned (bin/persona.sh)
TEAM=false; [ "$(cfg .team.enabled)" = true ] && TEAM=true
# each developer's dev:: label is one of Compasso's labels too (ensure-labels creates it)
[ "$TEAM" = true ] && LABELS="$LABELS
$(yq -r '.team.developers // [] | .[] | "dev::" + . + "|#6699cc|Built by the developer " + .' "$REPO/.compasso/project.yaml")"
ME=""; [ "$TEAM" = true ] && ME="$("$BIN/persona.sh" show --repo "$REPO" --json | jq -r '.name // ""')"
DEV_COLOR="#0e8a16"

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
    '{kind: $kind, item: $item, ctx: $ctx}' | jq -r -L "$BIN" --argjson L "$LOC" -f "$BIN/render.jq"
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
  local iids='{}' stale was parent devs dev
  "$BIN/plan-check.sh" --repo "$REPO" >/dev/null || {
    echo "gitlab: the plan does not pass plan-check - run: bin/plan-check.sh --repo $REPO" >&2; return 1; }
  info="$(check)" || return $?
  ensure_labels >/dev/null || return $?   # labels added in a newer Compasso exist before they are applied
  # Premium features (native epics, iterations, blocks links) are not available
  # yet: every tier is pushed the Free way until they can be tested on Premium.
  # tier="$(printf '%s' "$info" | jq -r .tier)"
  tier=free
  devs="$(team_devs)" || return 1
  for dev in $(yq -o=json . "$PLAN" | jq -r '[.features[] | .dev, ((.stories // [])[].dev)] | map(select(. != null)) | unique | .[]'); do
    [ "$TEAM" = true ] || break
    printf '%s\n' "$devs" | grep -qxF "dev::$dev" ||
      { echo "gitlab: $dev is not in team.developers in .compasso/project.yaml - add the name there first" >&2; return 1; }
  done
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
    # its stories are planned: the runner builds and delivers it; a state it already moved past is kept
    case "$(api "projects/$PID/issues/$iid" | jq -r '[.labels[] | select(startswith("compasso::"))][0] // ""')" in
      ""|compasso::new) IID="$iid" STATE=building set_state >/dev/null || return 1 ;;
    esac
    pset '(.features[] | select(.key == strenv(K)) | .gitlab) = (strenv(V) | tonumber)' "$key" "$iid"
    iids="$(jq -c --arg k "$key" --argjson v "$iid" --argjson id "$id" '.[$k] = $v | .["id:" + $k] = $id' <<<"$iids")"
    if [ "$TEAM" = true ]; then   # a feature's developer covers its stories and its verification
      dev="$(jq -r '.dev // ""' <<<"$f")"
      stale="$(printf '%s\n' "$devs" | grep -vx "dev::$dev" | paste -sd, -)"
      api -X PUT "projects/$PID/issues/$iid" ${dev:+-f "add_labels=dev::$dev"} ${stale:+-f "remove_labels=$stale"} >/dev/null ||
        { echo "gitlab: could not set the developer of feature $key" >&2; return 1; }
    fi
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
    if [ "$TEAM" = true ]; then dev="$(jq -r '.dev // ""' <<<"$s")"; labels="${dev:+dev::$dev}"; fi
    [ "$(jq '.blocked_by // [] | length' <<<"$s")" -gt 0 ] && labels="${labels:+$labels,}blocked"
    iid="$(jq -r '.gitlab // ""' <<<"$s")"
    res="$(upsert_issue "$iid" "$title" "$desc" "$ms" task "" "$labels")"
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
      # the same goes for a developer change in a team project
      stale="$(printf 'owner::agent\nowner::human\nowner::either\nblocked\n%s\n' "$devs" | grep -v '^$' | grep -vxF "$(printf '%s' "$labels" | tr ',' '\n')")"
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


# ---------- push-backlog: backlog features as issues outside any sprint ----------
push_backlog() {
  local BL="$REPO/.compasso/backlog.yaml" n i f key num res labels
  "$BIN/backlog-check.sh" --repo "$REPO" >/dev/null || { echo "gitlab: the backlog does not pass backlog-check - run bin/backlog-check.sh --repo $REPO" >&2; return 1; }
  check >/dev/null || return $?
  ensure_labels >/dev/null || return $?
  n="$(yq '.features | length' "$BL")"; i=0
  while [ "$i" -lt "$n" ]; do
    f="$(yq -o=json ".features[$i]" "$BL")"; key="$(jq -r .key <<<"$f")"
    labels="type::feature"; [ "$(jq -r .mvp <<<"$f")" = true ] && labels="$labels mvp"
    num="$(jq -r '.gitlab // ""' <<<"$f")"
    [ -n "$num" ] || labels="$labels compasso::new"   # new: the tech lead splits it into stories when its turn comes
    # no milestone: a feature joins a sprint when /compasso:plan pushes it
    # shellcheck disable=SC2086
    res="$(upsert_issue "$num" "$(jq -r .title <<<"$f")" "$(render feature "$f" '{}')" "" issue "" $labels)"
    [ -n "$res" ] || { echo "gitlab: could not write backlog feature $key" >&2; return 1; }
    num="${res% *}"
    K="$key" V="$num" yq -i '(.features[] | select(.key == strenv(K)) | .gitlab) = (strenv(V) | tonumber)' "$BL"
    [ "$(jq -r .mvp <<<"$f")" = true ] || api -X PUT "projects/$PID/issues/$num" -f remove_labels=mvp >/dev/null
    echo "gitlab: backlog $key -> #$num$( [ "$(jq -r .mvp <<<"$f")" = true ] && echo " (MVP)")"
    i=$((i + 1))
  done
}

# ---------- stories and merge requests ----------
need() { for v in "$@"; do eval "[ -n \"\$$v\" ]" || { echo "gitlab: $CMD needs --$(echo "$v" | tr 'A-Z_' 'a-z-')" >&2; exit 1; }; done; }

parent_iid() { # work item id -> parent iid, or empty
  api graphql -f query="query { workItem(id: \"gid://gitlab/WorkItem/$1\") { widgets { ... on WorkItemWidgetHierarchy { parent { iid } } } } }" |
    jq -r '[.data.workItem.widgets[]? | .parent?.iid // empty][0] // empty'
}

story() {
  local issue parsed feature="" fcov="null" fdev="" epic="" ecov="null" ms open='[]' d dj kind
  need IID
  check >/dev/null || return $?
  issue="$(api "projects/$PID/issues/$IID")"
  [ -n "$(jq -r '.iid // empty' <<<"$issue" 2>/dev/null)" ] || { echo "gitlab: no work item #$IID in $PROJECT" >&2; return 1; }
  parsed="$(jq -r '.description // ""' <<<"$issue" | jq -Rs --argjson N "$NAMES" -f "$BIN/parse.jq")"

  feature="$(parent_iid "$(jq -r .id <<<"$issue")")"
  if [ -n "$feature" ]; then
    dj="$(api "projects/$PID/issues/$feature")"
    fcov="$(jq -r '.description // ""' <<<"$dj" | jq -Rs --argjson N "$NAMES" -f "$BIN/parse.jq" | jq .coverage)"
    fdev="$(jq -r '[.labels[]? | select(startswith("dev::")) | sub("dev::"; "")][0] // ""' <<<"$dj")"
  fi
  ms="$(jq -r '.milestone.title // empty' <<<"$issue")"
  if [ -n "$ms" ]; then
    dj="$(api "projects/$PID/issues?milestone=$ms&labels=type::epic&state=all" | jq '.[0] // empty')"
    if [ -n "$dj" ]; then
      epic="$(jq -r .iid <<<"$dj")"
      ecov="$(jq -r '.description // ""' <<<"$dj" | jq -Rs --argjson N "$NAMES" -f "$BIN/parse.jq" | jq .coverage)"
    fi
  fi

  for d in $(jq -r '.depends_on[]' <<<"$parsed") $(jq -r '.blocked_by[] | "b\(.)"' <<<"$parsed"); do
    dj="$(api "projects/$PID/issues/${d#b}")" || { echo "gitlab: #${d#b} referenced by #$IID does not exist" >&2; return 1; }
    [ "$(jq -r .state <<<"$dj")" = opened ] || continue
    kind=depends_on; [ "${d#b}" = "$d" ] || kind=blocked_by
    open="$(jq -c --argjson i "${d#b}" --arg t "$(jq -r .title <<<"$dj")" --arg k "$kind" '. + [{iid: $i, title: $t, kind: $k}]' <<<"$open")"
  done

  jq -n --slurpfile issue <(printf '%s' "$issue") --slurpfile s <(printf '%s' "$parsed") --arg feature "$feature" --argjson fcov "$fcov" \
        --arg epic "$epic" --argjson ecov "$ecov" --argjson open "$open" --argjson dflt "$(cfg .coverage.min_changed)" --arg fdev "$fdev" '$issue[0] as $issue | $s[0] as $s | {
    iid: $issue.iid, id: $issue.id, title: $issue.title, state: $issue.state, type: $issue.issue_type,
    dev: ([$issue.labels[] | select(startswith("dev::")) | sub("dev::"; "")][0] // (if $fdev == "" then null else $fdev end)),
    kind: (if ($issue.labels | index("type::bug")) then "bug" else "story" end),
    estimate_h: (($issue.time_stats.time_estimate // 0) / 3600),
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
  local all="compasso::new compasso::backlog compasso::building compasso::in-review compasso::verifying compasso::done"
  need IID STATE
  case " $all " in *" compasso::$STATE "*) : ;; *) echo "gitlab: unknown state '$STATE'" >&2; return 1 ;; esac
  api -X PUT "projects/$PID/issues/$IID" -f add_labels="compasso::$STATE" \
    -f remove_labels="$(printf '%s\n' $all | grep -vx "compasso::$STATE" | paste -sd, -)" >/dev/null ||
    { echo "gitlab: could not set #$IID to $STATE" >&2; return 1; }
  echo "gitlab: #$IID is $STATE"
}

open_mr() {
  local title target mr out
  need BRANCH BODY
  [ -f "$BODY" ] || { echo "gitlab: no body file $BODY" >&2; return 1; }
  [ -n "$IID$TITLE" ] || { echo "gitlab: open-mr needs --iid (the story's title) or --title" >&2; return 1; }
  title="$TITLE"
  if [ -z "$title" ]; then
    title="$(api "projects/$PID/issues/$IID" | jq -r '.title // empty')"
    [ -n "$title" ] || { echo "gitlab: no work item #$IID" >&2; return 1; }
  fi
  target="$(api "projects/$PID" | jq -r .default_branch)"   # trunk-based: a story never stacks on another's branch
  mr="$(api "projects/$PID/merge_requests?source_branch=$BRANCH&state=opened" | jq -r '.[0].iid // empty')"
  if [ -n "$mr" ]; then
    out="$(api -X PUT "projects/$PID/merge_requests/$mr" -f description="$(cat "$BODY")")"
  else
    out="$(api -X POST "projects/$PID/merge_requests" -f source_branch="$BRANCH" -f target_branch="$target" \
      -f title="$title" -f description="$(cat "$BODY")" -f remove_source_branch=true)"
  fi
  printf '%s' "$out" | jq -e -c '{iid, web_url}' 2>/dev/null || { echo "gitlab: could not open the merge request for $BRANCH" >&2; return 1; }
}




mr_info() {
  local mr closes
  need MR
  mr="$(api "projects/$PID/merge_requests/$MR")"
  [ -n "$(jq -r '.iid // empty' <<<"$mr" 2>/dev/null)" ] || { echo "gitlab: no merge request !$MR in $PROJECT" >&2; return 1; }
  closes="$(api "projects/$PID/merge_requests/$MR/closes_issues" | jq -c '[.[].iid]')" || closes='[]'
  jq -c --argjson closes "$closes" '{iid, title, state, source_branch, target_branch, web_url, author: .author.username, draft, closes: $closes}' <<<"$mr"
}


close() {
  need IID
  comment >/dev/null || return 1
  api -X PUT "projects/$PID/issues/$IID" -f state_event=close >/dev/null || { echo "gitlab: could not close #$IID" >&2; return 1; }
  echo "gitlab: #$IID closed"
}


mr_checks() {
  local m
  need MR
  m="$(api "projects/$PID/merge_requests/$MR")"
  [ -n "$(jq -r '.iid // empty' <<<"$m" 2>/dev/null)" ] || { echo "gitlab: no merge request !$MR in $PROJECT" >&2; return 1; }
  jq -c '{pipeline: (.head_pipeline.status // "none"
            | if . == "success" then "success" elif . == "failed" or . == "canceled" then "failed"
              elif . == "none" or . == "skipped" then "none" else "running" end),
          conflicts: (.has_conflicts == true)}' <<<"$m"
}

main_pipeline() { # a canceled or skipped pipeline says nothing about main; the oldest of the newest failures broke it
  local b p sha mr="" closes='[]'
  b="$(api "projects/$PID" | jq -r .default_branch)" || return 1
  p="$(api "projects/$PID/pipelines?ref=$b&scope=finished&per_page=50" | jq -c '[.[] | select(.status == "success" or .status == "failed")]
    | if length == 0 then {pipeline: "none", sha: null, web_url: null, broken: null}
      else {pipeline: .[0].status, sha: .[0].sha, web_url: .[0].web_url,
            broken: (if .[0].status == "failed" then ((map(.status == "failed") | index(false)) as $i | .[($i // length) - 1].sha) else null end)} end')" ||
    { echo "gitlab: cannot read the pipelines of $b" >&2; return 1; }
  sha="$(jq -r '.broken // empty' <<<"$p")"
  if [ -n "$sha" ]; then
    mr="$(api "projects/$PID/repository/commits/$sha/merge_requests" | jq -r '[.[] | select(.state == "merged")][0].iid // empty')"
    [ -z "$mr" ] || closes="$(MR="$mr" mr_info | jq -c .closes)" || closes='[]'
  fi
  jq -c --arg mr "$mr" --argjson closes "$closes" '{pipeline, sha, web_url,
    broken_by: (if .broken then {sha: .broken, mr: (if $mr == "" then null else ($mr | tonumber) end), closes: $closes} else null end)}' <<<"$p"
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
    d="$(jq --slurpfile p <(jq -r '.description // ""' <<<"$d" | jq -Rs --argjson N "$NAMES" -f "$BIN/parse.jq") \
            --arg parent "$( [ "$(jq -r .issue_type <<<"$d")" = task ] && parent_iid "$id" )" \
      '$p[0] as $p | . + {parsed: $p, parent: (if $parent == "" then null else ($parent | tonumber) end)}' <<<"$d")"
    enriched="$(jq -c --slurpfile d <(printf '%s' "$d") '. + $d' <<<"$enriched")"   # a file, not an argument: items can be large
  done

  # dependencies outside the milestone: look up their state
  for i in $(jq -r '[.[].iid] as $in | [.[].parsed | (.depends_on + .blocked_by)[]] | unique | map(select(. as $x | $in | index($x) | not)) | .[]' <<<"$enriched"); do
    d="$(api "projects/$PID/issues/$i")" || { echo "gitlab: #$i is referenced in $ms but does not exist" >&2; return 1; }
    ext="$(jq -c --slurpfile d <(printf '%s' "$d") '$d[0] as $d | . + [{iid: $d.iid, state: $d.state, title: $d.title}]' <<<"$ext")"
  done

  # closed stories and bugs keep no in-progress state label
  for i in $(jq -r '.[] | select(.state == "closed" and .issue_type == "task")
      | select(.labels | index("compasso::building") or index("compasso::in-review")) | .iid' <<<"$enriched"); do
    [ "$READ_ONLY" -eq 1 ] && continue   # status: report, never change the tracker
    api -X PUT "projects/$PID/issues/$i" -f remove_labels="compasso::building,compasso::in-review" >/dev/null ||
      { echo "gitlab: could not clear the state of #$i" >&2; return 1; }
    cleaned="$(jq -c --argjson i "$i" '. + [$i]' <<<"$cleaned")"
  done

  parallel="$(cfg '.sprint.parallel // 2')"
  devs='[]'; [ "$TEAM" != true ] || devs="$(labels_cmd | jq -c 'map(select(startswith("dev::")) | sub("dev::"; ""))')" || return 1
  jq -n --argjson devs "$devs" --arg ms "$ms" --slurpfile items <(printf '%s' "$enriched") --slurpfile ext <(printf '%s' "$ext") --argjson cleaned "$cleaned" \
        --argjson parallel "$parallel" --arg feature "$PARENT" --argjson team "$TEAM" --arg me "$ME" -f "$BIN/sprint.jq"
}


snapshot() { # four reads; bin/snapshot.jq shapes them the same way for both trackers
  local proj issues mrs pipes parsed
  proj="$(api "projects/$PID")" || { echo "gitlab: cannot read $PROJECT" >&2; return 1; }
  issues="$(api --paginate "projects/$PID/issues?state=opened&per_page=100")" && issues="$(jq -s 'add // []' <<<"$issues")" ||
    { echo "gitlab: cannot read the open work items" >&2; return 1; }
  mrs="$(api --paginate "projects/$PID/merge_requests?state=opened&per_page=100")" && mrs="$(jq -s 'add // []' <<<"$mrs")" ||
    { echo "gitlab: cannot read the open merge requests" >&2; return 1; }
  pipes="$(api "projects/$PID/pipelines?per_page=100")" || { echo "gitlab: cannot read the pipelines" >&2; return 1; }
  parsed="$(jq '.[] | .description // ""' <<<"$issues" | jq -c --argjson N "$NAMES" -f "$BIN/parse.jq" | jq -s .)" || return 1
  jq -n -L "$BIN" --arg main "$(jq -r '.default_branch // "main"' <<<"$proj")" \
    --slurpfile issues <(printf '%s' "$issues") --slurpfile parsed <(printf '%s' "$parsed") \
    --slurpfile mrs <(printf '%s' "$mrs") --slurpfile pipes <(printf '%s' "$pipes") '
    include "snapshot";
    ($pipes[0] | map({ref, sha, status})) as $p
    | snapshot(
        [$issues[0], $parsed[0]] | transpose | map(.[0] as $i | {iid: $i.iid, title: $i.title, web_url: $i.web_url,
          labels: $i.labels, description: ($i.description // ""), deps: (.[1].depends_on + .[1].blocked_by), feature: .[1].feature,
          sprint: ($i.milestone | if . then {title, due: .due_date} else null end), type: $i.issue_type});
        $mrs[0] | map(. as $m | {iid, title, web_url, draft, labels, branch: .source_branch, description: (.description // ""),
          author: .author.username, pipeline: ([$p[] | select(.sha == $m.sha)][0].status // "none")});
        [$p[] | select(.ref == $main and (.status == "success" or .status == "failed"))][0] | {pipeline: (.status // "none"), sha})'
}


assign_cmd() {
  local others
  need IID NAME
  others="$(api "projects/$PID/issues/$IID" | jq -r --arg me "dev::$NAME" '[.labels[] | select(startswith("dev::") and . != $me)] | join(",")')" ||
    { echo "gitlab: no work item #$IID" >&2; return 1; }
  api -X PUT "projects/$PID/issues/$IID" -f add_labels="dev::$NAME,compasso::backlog" \
    -f remove_labels="${others:+$others,}compasso::building,compasso::in-review" >/dev/null || { echo "gitlab: could not assign #$IID" >&2; return 1; }
}

human_done() { # the question was answered: the story is free again (bin/run.sh)
  need IID
  api -X PUT "projects/$PID/issues/$IID" -f remove_labels=needs::human >/dev/null || { echo "gitlab: could not unblock #$IID" >&2; return 1; }
}

human_ask() { # one open issue per (key, story): asking again updates it
  local open marker hit ids="" u id out
  need KEY TITLE BODY
  marker="<!-- compasso:ask story=$IID key=$KEY -->"
  open="$(api --paginate "projects/$PID/issues?state=opened&labels=needs::human&per_page=100")" && open="$(jq -s 'add // []' <<<"$open")" ||
    { echo "gitlab: cannot read the open needs::human issues" >&2; return 1; }
  hit="$(jq -c --arg m "$marker" '[.[] | select((.description // "") | startswith($m))][0] // empty' <<<"$open")"
  if [ -n "$hit" ]; then
    out="$(api -X PUT "projects/$PID/issues/$(jq -r .iid <<<"$hit")" -f title="$TITLE" -f description="$(cat "$BODY")")" ||
      { echo "gitlab: could not update the question" >&2; return 1; }
    jq -c '{iid, web_url, created: false}' <<<"$out"
  else
    for u in $(cfg '.people.ask // [] | .[]'); do
      id="$(api "users?username=$u" | jq -r '.[0].id // empty')"
      [ -n "$id" ] && ids="$ids -f assignee_ids[]=$id" || echo "gitlab: no user $u on $HOST to ask; the question stays unassigned" >&2
    done
    # shellcheck disable=SC2086
    out="$(api -X POST "projects/$PID/issues" -f title="$TITLE" -f description="$(cat "$BODY")" -f issue_type=issue -f labels=needs::human $ids)" &&
      [ -n "$(jq -r '.iid // empty' <<<"$out")" ] || { echo "gitlab: could not open the question" >&2; return 1; }
    jq -c '{iid, web_url, created: true}' <<<"$out"
  fi
  [ -z "$IID" ] || api -X PUT "projects/$PID/issues/$IID" -f add_labels=needs::human >/dev/null ||
    { echo "gitlab: asked, but could not hold back #$IID: add needs::human to it by hand" >&2; return 1; }
}






sprint_items() { # a sprint's work items with their label history, for the report
  local items with='[]' i ev
  need MILESTONE
  items="$(api --paginate "projects/$PID/issues?milestone=$MILESTONE&state=all&per_page=100" | jq -s 'add // []')" ||
    { echo "gitlab: cannot read the work items of $MILESTONE" >&2; return 1; }
  for i in $(jq -r '.[] | select(.issue_type == "task") | .iid' <<<"$items"); do
    ev="$(api --paginate "projects/$PID/issues/$i/resource_label_events?per_page=100" | jq -s 'add // []')" || ev='[]'
    with="$(jq -c --argjson i "$i" --argjson ev "$ev" '. + [{iid: $i, label_events: $ev}]' <<<"$with")"
  done
  jq -c --slurpfile with <(printf '%s' "$with") '$with[0] as $with | map(. as $it | . + {label_events: ([$with[] | select(.iid == $it.iid) | .label_events][0] // [])})' <<<"$items"
}

sprint_done() { # hours of work done in a sprint, or null when the sprint does not exist
  need MILESTONE
  api --paginate "projects/$PID/issues?milestone=$MILESTONE&state=closed&per_page=100" | jq -s '
    add // [] | map(select(.issue_type == "task" and ((.labels | index("type::blocker")) | not)))
    | if length == 0 then null else (map(.time_stats.time_estimate // 0) | add / 3600 * 10 | round / 10) end'
}


team_devs() { # the team's developers (team.developers) as dev:: labels, one per line; nothing outside a team project
  [ "$TEAM" = true ] || return 0
  yq -r '.team.developers // [] | .[] | "dev::" + .' "$REPO/.compasso/project.yaml"
}
labels_cmd() { api --paginate "projects/$PID/labels?per_page=100" | jq -s -c 'add // [] | map(.name)'; }
harden_feature() { # what the harden stage drains from the after-MVP list goes under it (bin/lead.sh hardening)
  local marker="<!-- compasso:harden -->" open out
  need TITLE
  open="$(api --paginate "projects/$PID/issues?state=opened&labels=type::feature&per_page=100")" && open="$(jq -s 'add // []' <<<"$open")" ||
    { echo "gitlab: cannot read the open features" >&2; return 1; }
  out="$(jq -c --arg m "$marker" '[.[] | select((.description // "") | startswith($m))] | sort_by(.iid) | .[0] // empty' <<<"$open")"
  if [ -z "$out" ]; then
    out="$(api -X POST "projects/$PID/issues" -f title="$TITLE" -f description="$marker" -f issue_type=issue -f labels=type::feature,compasso::building)" &&
      [ -n "$(jq -r '.iid // empty' <<<"$out")" ] || { echo "gitlab: could not open the hardening feature" >&2; return 1; }
  fi
  jq -c '{iid, web_url}' <<<"$out"
}
add_story() { # in the feature's sprint and hierarchy; its developer covers its stories
  local f s labels="owner::agent" dev res
  need PARENT TITLE FROM
  f="$(api "projects/$PID/issues/$PARENT")" && [ -n "$(jq -r '.iid // empty' <<<"$f" 2>/dev/null)" ] || { echo "gitlab: no feature #$PARENT" >&2; return 1; }
  s="$(jq -c --arg f "#$PARENT" '. + {feature: $f} | del(.key)' "$FROM")" || { echo "gitlab: $FROM is not JSON" >&2; return 1; }
  if [ "$TEAM" = true ]; then
    dev="$(jq -r '[.labels[] | select(startswith("dev::"))][0] // empty' <<<"$f")"; labels="${dev:+$dev,compasso::backlog}"
  fi
  res="$(upsert_issue "" "$TITLE" "$(render story "$s" '{"iids": {}}')" "$(jq -r '.milestone.id // empty' <<<"$f")" task "" "$labels")"
  [ -n "$res" ] || { echo "gitlab: could not write the story" >&2; return 1; }
  api graphql -f query="mutation { workItemUpdate(input: { id: \"gid://gitlab/WorkItem/${res#* }\", hierarchyWidget: { parentId: \"gid://gitlab/WorkItem/$(jq -r .id <<<"$f")\" } }) { errors } }" |
    jq -e '(.data.workItemUpdate.errors // ["no response"]) | length == 0' >/dev/null || { echo "gitlab: #${res% *} written, but not attached to #$PARENT" >&2; return 1; }
  jq -cn --argjson iid "${res% *}" --arg u "https://$HOST/$PROJECT/-/issues/${res% *}" '{iid: $iid, web_url: $u}'
}
mr_merge() { # the tech lead's merge: no approvals to check; main stays green
  need MR
  [ "$(mr_checks | jq -r .pipeline)" != failed ] || { echo "gitlab: !$MR is not merged: its pipeline failed" >&2; return 1; }
  api -X PUT "projects/$PID/merge_requests/$MR/merge" -f merge_when_pipeline_succeeds=true >/dev/null ||
    { echo "gitlab: could not merge !$MR" >&2; return 1; }
  echo "gitlab: !$MR merges when its pipeline succeeds"
}
mr_label() {
  local l
  need MR
  for l in $(printf '%s,%s' "$ADD" "$REMOVE" | tr ',' ' '); do
    case "$l" in compasso::rework|compasso::fix-main) ;; *) echo "gitlab: mr-label sets only compasso::rework and compasso::fix-main, not $l" >&2; return 1 ;; esac
  done
  IID="" label_cmd
}
after_mvp() { # one list, appended to: what the MVP leaves for the harden stage
  local marker="<!-- compasso:after-mvp list -->" open iid out
  need TITLE BODY
  [ -f "$BODY" ] || { echo "gitlab: no body file $BODY" >&2; return 1; }
  open="$(api --paginate "projects/$PID/issues?state=opened&labels=compasso::after-mvp&per_page=100")" && open="$(jq -s 'add // []' <<<"$open")" ||
    { echo "gitlab: cannot read the after-MVP list" >&2; return 1; }
  out="$(jq -c --arg m "$marker" '[.[] | select((.description // "") | startswith($m))] | sort_by(.iid) | .[0] // empty' <<<"$open")"
  if [ -z "$out" ]; then
    out="$(api -X POST "projects/$PID/issues" -f title="$TITLE" -f description="$marker" -f issue_type=issue -f labels=compasso::after-mvp)" &&
      [ -n "$(jq -r '.iid // empty' <<<"$out")" ] || { echo "gitlab: could not open the after-MVP list" >&2; return 1; }
  fi
  iid="$(jq -r .iid <<<"$out")"
  IID="$iid" MR="" comment >/dev/null || return 1
  jq -c '{iid, web_url}' <<<"$out"
}
reopen() {
  need IID
  api -X PUT "projects/$PID/issues/$IID" -f state_event=reopen >/dev/null || { echo "gitlab: could not reopen #$IID" >&2; return 1; }
  echo "gitlab: #$IID reopened"
}
label_cmd() { # --add and --remove take comma-separated labels; on an issue (--iid) or a merge request (--mr)
  local on where
  if [ -n "$MR" ]; then on="merge_requests/$MR"; where="!$MR"; else need IID; on="issues/$IID"; where="#$IID"; fi
  api -X PUT "projects/$PID/$on" ${ADD:+-f "add_labels=$ADD"} ${REMOVE:+-f "remove_labels=$REMOVE"} >/dev/null ||
    { echo "gitlab: could not label $where" >&2; return 1; }
  echo "gitlab: $where labels updated"
}
notes_of() { # the issue's (--iid) or the merge request's (--mr) notes path
  if [ -n "$MR" ]; then echo "merge_requests/$MR"; elif [ -n "$IID" ]; then echo "issues/$IID"
  else echo "gitlab: $CMD needs --iid or --mr" >&2; return 1; fi
}
comments() { # oldest first; member: the tracker says a project member wrote it
  local notes members='{}' a on
  on="$(notes_of)" || return 1
  notes="$(api --paginate "projects/$PID/$on/notes?sort=asc&per_page=100" | jq -s -c 'add // [] | map(select(.system | not))')" ||
    { echo "gitlab: cannot read the comments of ${MR:+!$MR}${IID:+#$IID}" >&2; return 1; }
  for a in $(jq -r '[.[].author.id] | unique | .[]' <<<"$notes"); do
    if api "projects/$PID/members/all/$a" >/dev/null 2>&1; then members="$(jq -c --arg a "$a" '.[$a] = true' <<<"$members")"; fi
  done
  jq -c --argjson m "$members" 'map({id, body: (.body // ""), author: .author.username, at: .created_at,
    member: ($m[.author.id | tostring] // false)}) | sort_by(.id)' <<<"$notes"
}

case "$CMD" in
  comments) comments ;;
  check) check ;;
  ensure-labels) ensure_labels ;;
  push-plan) push_plan ;;
  push-backlog) push_backlog ;;
  story) story ;;
  set-state) set_state ;;
  open-mr) open_mr ;;
  mr-info) mr_info ;;
  mr-checks) mr_checks ;;
  close) close ;;
  main-pipeline) main_pipeline ;;
  comment) comment ;;
  sprint-sync) sprint_sync ;;
  sprint-items) sprint_items ;;
  sprint-done) sprint_done ;;
  snapshot) snapshot ;;
  mr-merge) mr_merge ;;
  mr-label) mr_label ;;
  after-mvp) after_mvp ;;
  reopen) reopen ;;
  add-story) add_story ;;
  harden-feature) harden_feature ;;
  human-ask) human_ask ;;
  human-done) human_done ;;
  assign) assign_cmd ;;
  *) echo "usage: gitlab.sh <command> --repo R ... (gitlab.sh --help lists them)" >&2; exit 1 ;;
esac
