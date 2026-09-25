#!/usr/bin/env bash
# GitHub tracker adapter. Reads .compasso/project.yaml; talks to GitHub through gh.
# Same commands, options and output shapes as gitlab.sh, so every skill and script
# works with either. GitHub issues are returned in the GitLab adapter's shape:
# number -> iid, open -> opened, type::epic/type::feature -> "issue", other work -> "task",
# the Project's estimate -> time_stats.time_estimate (seconds).
#
# Mapping (decided 2026-09-25):
#   sprint      a milestone S<n> and an iteration S<n> in the GitHub Project, kept in step
#   estimate    the Project's number field (tracker.github.fields.estimate)
#   state       compasso:: labels and the Project's Status field (tracker.github.status)
#   structure   type:: labels; features are sub-issues of the epic, stories and blockers of their feature
#   dependency  GitHub's native "blocked by" (depends_on and blocked_by both)
#   approval    merging is the approval; merge requests are pull requests
#
#   github.sh check | ensure-labels | push-plan | story | set-state | open-mr | followup | merge
#             | mr-info | comment | sprint-sync | merge-commit | digest | open-mr-branch
#             | sprint-items | sprint-done | protect --repo R [options as in gitlab.sh]
#
# Exit: 0 ok | 1 config/usage/tracker failure | 2 not logged in | 3 repository not found or no access
#       4 cannot push to the repository
set -u

BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CMD="${1:-}"; shift || true
REPO="." IID="" STATE="" BRANCH="" BODY="" TITLE="" PARENT="" MR="" LABELS_ARG="owner::either" MILESTONE="" RISK="" TARGET="" SINCE="" READ_ONLY=0
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
    --risk) RISK="$2"; shift 2 ;;
    --target) TARGET="$2"; shift 2 ;;
    --since) SINCE="$2"; shift 2 ;;
    --read-only) READ_ONLY=1; shift ;;
    *) echo "github: unknown argument '$1'" >&2; exit 1 ;;
  esac
done

"$BIN/config.sh" validate --repo "$REPO" >/dev/null || exit 1
cfg() { "$BIN/config.sh" get --repo "$REPO" "$1"; }
HOST="$(cfg .tracker.host)"; [ -n "$HOST" ] || HOST=github.com
R="$(cfg .tracker.project)"; OWNER="${R%%/*}"
PROJ="$(cfg .tracker.github.project)"; PROJ="${PROJ:-0}"
LABELS="$(cat "$BIN/tracker/labels.txt")"
STATES="new building in-review verifying done"

api() { gh api --hostname "$HOST" "$@"; }
gql() { gh api graphql --hostname "$HOST" "$@"; }
need() { for v in "$@"; do eval "[ -n \"\$$v\" ]" || { echo "github: $CMD needs --$(echo "$v" | tr 'A-Z_' 'a-z-')" >&2; exit 1; }; done; }
status_option() { cfg ".tracker.github.status.\"$1\""; }

# ---------- normalising: a GitHub issue in the GitLab adapter's shape ----------
NORM='def norm($est): {
  iid: .number, id: .id, node_id, title, description: (.body // ""),
  state: (if .state == "open" then "opened" else "closed" end),
  issue_type: (if ([.labels[].name] | index("type::epic") or index("type::feature")) then "issue" else "task" end),
  labels: [.labels[].name], created_at, closed_at,
  milestone: (if .milestone then {id: .milestone.number, title: .milestone.title} else null end),
  assignees: [.assignees[]? | {username: .login}],
  time_stats: {time_estimate: ((($est[.number | tostring]) // 0) * 3600 | round)}};'

# ---------- the GitHub Project: fields, options, items ----------
project() { # the Project with its fields, as JSON; {} when none is configured
  [ "$PROJ" != 0 ] || { echo '{}'; return; }
  gql -f query="query { repositoryOwner(login: \"$OWNER\") { ... on ProjectV2Owner { projectV2(number: $PROJ) { id
    fields(first: 50) { nodes {
      ... on ProjectV2FieldCommon { id name dataType }
      ... on ProjectV2SingleSelectField { options { id name } }
      ... on ProjectV2IterationField { configuration { duration startDay
        iterations { id title startDate duration } completedIterations { id title startDate duration } } } } } } } } }" \
    --jq '.data.repositoryOwner.projectV2' 2>/dev/null
}
estimates() { # {"<issue number>": hours} for this repository's issues in the Project
  [ "$PROJ" != 0 ] || { echo '{}'; return; }
  local f; f="$(cfg .tracker.github.fields.estimate)"
  gql --paginate -f query="query(\$endCursor: String) { repositoryOwner(login: \"$OWNER\") { ... on ProjectV2Owner { projectV2(number: $PROJ) {
    items(first: 100, after: \$endCursor) { pageInfo { hasNextPage endCursor } nodes {
      content { ... on Issue { number repository { nameWithOwner } } }
      fieldValueByName(name: \"$f\") { ... on ProjectV2ItemFieldNumberValue { number } } } } } } } }" \
    --jq ".data.repositoryOwner.projectV2.items.nodes[] | select(.content.repository.nameWithOwner == \"$R\") | {key: (.content.number | tostring), value: .fieldValueByName.number}" 2>/dev/null |
    jq -s 'map(select(.value != null)) | from_entries'
}
item_for() { # issue node id -> the Project item id (added when missing)
  gql -f query="mutation { addProjectV2ItemById(input: {projectId: \"$1\", contentId: \"$2\"}) { item { id } } }" --jq '.data.addProjectV2ItemById.item.id'
}
set_field() { # project-id item-id field-id kind value : kind number|option|iteration
  local v
  case "$4" in number) v="{number: $5}" ;; option) v="{singleSelectOptionId: \"$5\"}" ;; iteration) v="{iterationId: \"$5\"}" ;; esac
  gql -f query="mutation { updateProjectV2ItemFieldValue(input: {projectId: \"$1\", itemId: \"$2\", fieldId: \"$3\", value: $v}) { projectV2Item { id } } }" >/dev/null
}
field_id() { jq -r --arg n "$2" '.fields.nodes[] | select(.name == $n) | .id' <<<"$1"; }
option_id() { jq -r --arg n "$2" --arg o "$3" '.fields.nodes[] | select(.name == $n) | .options[]? | select(.name == $o) | .id' <<<"$1"; }
iteration_id() { jq -r --arg n "$2" --arg t "$3" '.fields.nodes[] | select(.name == $n) | .configuration | (.iterations + .completedIterations)[]? | select(.title == $t) | .id' <<<"$1"; }

# ---------- check ----------
check() {
  local user repo push proj code
  user="$(api user --jq .login 2>/dev/null)" || user=""   # on an HTTP error gh prints the error body
  [ -n "$user" ] || { echo "github: not logged in to $HOST - run: gh auth login --hostname $HOST --web" >&2; return 2; }
  repo="$(api "repos/$R" 2>/dev/null)"
  [ -n "$(jq -r '.id // empty' <<<"$repo" 2>/dev/null)" ] || { echo "github: repository $R not found on $HOST, or $user has no access to it" >&2; return 3; }
  push="$(jq -r '.permissions.push // false' <<<"$repo")"
  [ "$push" = true ] || { echo "github: $user cannot push to $R; Compasso needs write access" >&2; return 4; }
  if [ "$PROJ" != 0 ]; then
    proj="$(project)"
    [ -n "$(jq -r '.id // empty' <<<"${proj:-null}" 2>/dev/null)" ] ||
      { echo "github: Project $PROJ of $OWNER is not reachable - check tracker.github.project and that gh has the project scope (gh auth refresh -s project)" >&2; return 3; }
  fi
  # GitHub's own code scanning is free on public repositories, and needs Advanced Security on private ones
  code=false
  { [ "$(jq -r .visibility <<<"$repo")" = public ] || [ "$(jq -r '.security_and_analysis.advanced_security.status // ""' <<<"$repo")" = enabled ]; } && code=true
  jq -n --arg host "$HOST" --arg user "$user" --arg project "$R" --argjson id "$(jq .id <<<"$repo")" \
        --arg vis "$(jq -r .visibility <<<"$repo")" --argjson proj "$PROJ" --argjson code "$code" \
        --arg secret "$(jq -r '.security_and_analysis.secret_scanning.status // "disabled"' <<<"$repo")" '{
    host: $host, user: $user, project: $project, project_id: $id, access_level: 30, tier: "github", visibility: $vis,
    capabilities: {sub_issues: true, blocking_links: true, github_project: ($proj != 0),
                   code_scanning: $code, secret_scanning: ($secret == "enabled"), child_tasks: true, time_estimates: ($proj != 0)}}'
}

ensure_labels() {
  local have name color desc created=0 existing=0
  check >/dev/null || return $?
  have="$(api --paginate "repos/$R/labels?per_page=100" --jq '.[].name')"
  while IFS='|' read -r name color desc; do
    if printf '%s\n' "$have" | grep -qxF "$name"; then existing=$((existing + 1))
    else
      api -X POST "repos/$R/labels" -f name="$name" -f color="${color#\#}" -f description="$desc" >/dev/null ||
        { echo "github: could not create label $name" >&2; return 1; }
      created=$((created + 1))
    fi
  done <<EOF
$LABELS
EOF
  echo "github: labels on $R - $created created, $existing already present"
}

# ---------- issues ----------
issue() { api "repos/$R/issues/$1" 2>/dev/null; }
issue_norm() { # number -> normalised issue (with its estimate)
  local i; i="$(issue "$1")" || return 1
  [ -n "$(jq -r '.number // empty' <<<"$i" 2>/dev/null)" ] || return 1
  jq -c --argjson est "$(estimates)" "$NORM norm(\$est)" <<<"$i"
}
# on an HTTP error gh prints the error body to stdout, so a failed call's output is dropped
parent_number() { local p; p="$(api "repos/$R/issues/$1/parent" --jq '.number' 2>/dev/null)" && echo "$p"; return 0; }
blocked_by() { local b; b="$(api "repos/$R/issues/$1/dependencies/blocked_by" --jq '[.[].number]' 2>/dev/null)" && echo "$b" || echo '[]'; }
attach() { # child-number parent-number: make the child a sub-issue of the parent unless it already is
  local p cid
  p="$(parent_number "$1")"
  [ "$p" = "$2" ] && return 0
  cid="$(issue "$1" | jq -r .id)"
  if [ -n "$p" ]; then
    api -X POST "repos/$R/issues/$2/sub_issues" -F sub_issue_id="$cid" -F replace_parent=true >/dev/null
  else
    api -X POST "repos/$R/issues/$2/sub_issues" -F sub_issue_id="$cid" >/dev/null
  fi
}
block() { # blocked-number blocking-number: record "blocked by" unless it already is
  local have bid
  have="$(blocked_by "$1")"
  jq -e --argjson b "$2" 'index($b)' <<<"$have" >/dev/null && return 0
  bid="$(issue "$2" | jq -r .id)"
  api -X POST "repos/$R/issues/$1/dependencies/blocked_by" -F issue_id="$bid" >/dev/null
}
labels_set() { # number label...: add these labels
  local n="$1" args="" l; shift
  for l in "$@"; do args="$args -f labels[]=$l"; done
  # shellcheck disable=SC2086
  api -X POST "repos/$R/issues/$n/labels" $args >/dev/null
}
label_remove() { api -X DELETE "repos/$R/issues/$1/labels/$(jq -rn --arg l "$2" '$l | @uri')" >/dev/null 2>&1 || true; }

milestone_number() { # title [due-date] -> number, created when missing
  local n
  n="$(api "repos/$R/milestones?state=all&per_page=100" --jq ".[] | select(.title == \"$1\") | .number" | head -1)"
  if [ -z "$n" ]; then
    if [ -n "${2:-}" ]; then n="$(api -X POST "repos/$R/milestones" -f title="$1" -f due_on="${2}T23:59:59Z" --jq .number)"
    else n="$(api -X POST "repos/$R/milestones" -f title="$1" --jq .number)"; fi
  fi
  echo "$n"
}

upsert_issue() { # number-or-empty title body-file milestone-number-or-empty label... -> number
  local n="$1" title="$2" body="$3" ms="$4"; shift 4
  local args="" l
  if [ -z "$n" ]; then
    for l in "$@"; do args="$args -f labels[]=$l"; done
    # shellcheck disable=SC2086
    api -X POST "repos/$R/issues" -f title="$title" -F body=@"$body" ${ms:+-F milestone=$ms} $args --jq '.number // empty'
  else
    api -X PATCH "repos/$R/issues/$n" -f title="$title" -F body=@"$body" ${ms:+-F milestone=$ms} >/dev/null || return 1
    [ $# -eq 0 ] || labels_set "$n" "$@" || return 1
    echo "$n"
  fi
}

# ---------- push-plan ----------
PLAN="$REPO/.compasso/plan.yaml"
pget() { yq -r "$1" "$PLAN"; }
pset() { K="$2" V="$3" yq -i "$1" "$PLAN"; }
render() { jq -rn --arg kind "$1" --argjson item "$2" --argjson ctx "$3" '{kind: $kind, item: $item, ctx: $ctx}' | jq -r -f "$BIN/render.jq"; }
sprint() { echo "S$(pget .epic.sprint.number)"; }

ensure_iteration() { # project-json field-name title start days -> iteration id (added to the field when missing)
  local id
  id="$(iteration_id "$1" "$2" "$3")"
  [ -n "$id" ] && { echo "$id"; return; }
  # GitHub replaces the whole iteration configuration: send the existing iterations back with the new one
  jq -c --arg n "$2" --arg t "$3" --arg s "$4" --argjson d "$5" '(.fields.nodes[] | select(.name == $n)) as $f | {
    query: "mutation($f: ID!, $c: ProjectV2IterationFieldConfigurationInput!) { updateProjectV2Field(input: {fieldId: $f, iterationConfiguration: $c}) { projectV2Field { ... on ProjectV2IterationField { id } } } }",
    variables: {f: $f.id, c: {startDate: $s, duration: $d,
      iterations: (($f.configuration | (.completedIterations + .iterations)) | map({title, startDate, duration}) + [{title: $t, startDate: $s, duration: $d}])}}}' <<<"$1" |
    gql --input - >/dev/null || return 1
  iteration_id "$(project)" "$2" "$3"
}

to_project() { # number [estimate-hours] [status-state]: add to the Project, set iteration, estimate, status
  [ "$PROJ" != 0 ] || return 0
  local node item
  node="$(issue "$1" | jq -r .node_id)"
  item="$(item_for "$(jq -r .id <<<"$PJ")" "$node")" || return 1
  [ -n "$ITER" ] && set_field "$(jq -r .id <<<"$PJ")" "$item" "$(field_id "$PJ" "$F_ITER")" iteration "$ITER"
  [ -n "${2:-}" ] && set_field "$(jq -r .id <<<"$PJ")" "$item" "$(field_id "$PJ" "$F_EST")" number "$2"
  [ -n "${3:-}" ] && set_field "$(jq -r .id <<<"$PJ")" "$item" "$(field_id "$PJ" "$F_STATUS")" option "$(option_id "$PJ" "$F_STATUS" "$(status_option "$3")")"
  return 0
}

push_plan() {
  local ms n i f s b key num was title body ctx labels owner feats epic nums='{}' d stale
  "$BIN/plan-check.sh" --repo "$REPO" >/dev/null || { echo "github: the plan does not pass plan-check - run: bin/plan-check.sh --repo $REPO" >&2; return 1; }
  check >/dev/null || return $?
  ensure_labels >/dev/null || return $?
  ms="$(milestone_number "$(sprint)" "$(pget .epic.sprint.end)")" || return 1
  pset '.epic.gitlab.milestone = (strenv(V) | tonumber)' "" "$ms"
  PJ="$(project)"; ITER="" F_ITER="$(cfg .tracker.github.fields.iteration)" F_EST="$(cfg .tracker.github.fields.estimate)" F_STATUS="$(cfg .tracker.github.fields.status)"
  if [ "$PROJ" != 0 ]; then
    ITER="$(ensure_iteration "$PJ" "$F_ITER" "$(sprint)" "$(pget .epic.sprint.start)" "$(( $(cfg .sprint.weeks) * 7 ))")" ||
      { echo "github: could not find or add the iteration $(sprint)" >&2; return 1; }
    PJ="$(project)"
  fi
  body="$(mktemp)"; trap 'rm -f "$body"' RETURN

  # the epic first, so features can become its sub-issues; its full body is written last
  epic="$(pget '.epic.gitlab.issue // ""')"
  if [ -z "$epic" ]; then
    echo "**Goal:** $(pget .epic.goal)" > "$body"
    epic="$(upsert_issue "" "$(sprint): $(pget .epic.goal)" "$body" "$ms" type::epic)"
    [ -n "$epic" ] || { echo "github: could not write the epic" >&2; return 1; }
    pset '.epic.gitlab.issue = (strenv(V) | tonumber)' "" "$epic"
    to_project "$epic" "" new || return 1
  else
    to_project "$epic" || return 1
  fi

  n="$(pget '.features | length')"; i=0
  while [ "$i" -lt "$n" ]; do
    f="$(yq -o=json ".features[$i]" "$PLAN")"; key="$(jq -r .key <<<"$f")"
    render feature "$f" '{}' > "$body"
    num="$(upsert_issue "$(jq -r '.gitlab // ""' <<<"$f")" "$(jq -r .title <<<"$f")" "$body" "$ms" type::feature)" || return 1
    [ -n "$num" ] || { echo "github: could not write feature $key" >&2; return 1; }
    pset '(.features[] | select(.key == strenv(K)) | .gitlab) = (strenv(V) | tonumber)' "$key" "$num"
    nums="$(jq -c --arg k "$key" --argjson v "$num" '.[$k] = $v' <<<"$nums")"
    attach "$num" "$epic" || { echo "github: could not make feature $key a sub-issue of the epic" >&2; return 1; }
    to_project "$num" || return 1
    echo "github: feature $key -> #$num"
    i=$((i + 1))
  done

  n="$(pget '.blockers // [] | length')"; i=0
  while [ "$i" -lt "$n" ]; do
    b="$(yq -o=json ".blockers[$i]" "$PLAN")"; key="$(jq -r .key <<<"$b")"
    num="$(jq -r '.gitlab // ""' <<<"$b")"
    if [ -z "$num" ]; then
      render blocker "$b" '{"needed": []}' > "$body"
      num="$(upsert_issue "" "$(jq -r .title <<<"$b")" "$body" "$ms" type::blocker priority::urgent)" || return 1
      pset '(.blockers[] | select(.key == strenv(K)) | .gitlab) = (strenv(V) | tonumber)' "$key" "$num"
    fi
    api -X POST "repos/$R/issues/$num/assignees" -f "assignees[]=$(jq -r .assignee <<<"$b")" --jq '[.assignees[].login]' |
      jq -e --arg a "$(jq -r .assignee <<<"$b")" 'index($a)' >/dev/null ||
      { echo "github: $(jq -r .assignee <<<"$b") cannot be assigned blocker $key - is it a collaborator of $R?" >&2; return 1; }
    nums="$(jq -c --arg k "$key" --argjson v "$num" '.[$k] = $v' <<<"$nums")"
    i=$((i + 1))
  done

  for key in $("$BIN/plan-check.sh" --repo "$REPO" --json | jq -r '.waves[][]'); do
    s="$(K="$key" yq -o=json '.features[] as $f | $f.stories[] | select(.key == strenv(K)) | . + {"feature": $f.key}' "$PLAN")"
    owner="$(jq -r .owner <<<"$s")"
    ctx="$(jq -nc --argjson iids "$nums" '{tier: "github", iids: $iids}')"
    render story "$s" "$ctx" > "$body"
    labels="owner::$owner"; [ "$(jq '.blocked_by // [] | length' <<<"$s")" -gt 0 ] && labels="$labels blocked"
    was="$(jq -r '.gitlab // ""' <<<"$s")"
    # shellcheck disable=SC2086
    num="$(upsert_issue "$was" "$(jq -r .title <<<"$s")" "$body" "$ms" $labels)" || return 1
    [ -n "$num" ] || { echo "github: could not write story $key" >&2; return 1; }
    pset '(.features[].stories[] | select(.key == strenv(K)) | .gitlab) = (strenv(V) | tonumber)' "$key" "$num"
    nums="$(jq -c --arg k "$key" --argjson v "$num" '.[$k] = $v' <<<"$nums")"
    attach "$num" "$(jq -r --arg k "$(jq -r .feature <<<"$s")" '.[$k]' <<<"$nums")" ||
      { echo "github: could not attach story $key to its feature" >&2; return 1; }
    if [ -n "$was" ]; then
      for stale in owner::agent owner::human owner::either blocked; do
        case " $labels " in *" $stale "*) ;; *) label_remove "$num" "$stale" ;; esac
      done
    fi
    for d in $(jq -r '(.depends_on // []) + (.blocked_by // []) | .[]' <<<"$s"); do
      case "$d" in \#*) d="${d#\#}" ;; *) d="$(jq -r --arg k "$d" '.[$k]' <<<"$nums")" ;; esac
      block "$num" "$d" || { echo "github: could not record #$d as blocking story $key" >&2; return 1; }
    done
    to_project "$num" "$(jq .estimate_h <<<"$s")" "$( [ -z "$was" ] && echo new )" || return 1
    echo "github: story $key -> #$num"
  done

  # blockers again: final body with the stories they hold up
  n="$(pget '.blockers // [] | length')"; i=0
  while [ "$i" -lt "$n" ]; do
    b="$(yq -o=json ".blockers[$i]" "$PLAN")"; key="$(jq -r .key <<<"$b")"; num="$(jq -r .gitlab <<<"$b")"
    ctx="$(yq -o=json . "$PLAN" | jq -c --arg k "$key" '{needed: [.features[].stories[] | select((.blocked_by // []) | index($k)) | {iid: .gitlab, title}]}')"
    render blocker "$b" "$ctx" > "$body"
    upsert_issue "$num" "$(jq -r .title <<<"$b")" "$body" "$ms" >/dev/null || return 1
    to_project "$num" || return 1
    echo "github: blocker $key -> #$num (assigned to $(jq -r .assignee <<<"$b"))"
    i=$((i + 1))
  done

  feats="$(yq -o=json . "$PLAN" | jq -c '[.features[] | {iid: .gitlab, title, hours: ([.stories[].estimate_h] | add)}]')"
  ctx="$(jq -nc --argjson features "$feats" --argjson cap "$(cfg .sprint.capacity_hours)" '{features: $features, capacity: $cap}')"
  render epic "$(yq -o=json .epic "$PLAN")" "$ctx" > "$body"
  upsert_issue "$epic" "$(sprint): $(pget .epic.goal)" "$body" "$ms" >/dev/null || return 1
  echo "github: epic $(pget .epic.key) -> #$epic (milestone $(sprint)$( [ -n "$ITER" ] && echo ", iteration $(sprint)"))"
}

# ---------- push-backlog: backlog features as issues outside any sprint ----------
push_backlog() {
  local BL="$REPO/.compasso/backlog.yaml" n i f key num labels body
  "$BIN/backlog-check.sh" --repo "$REPO" >/dev/null || { echo "github: the backlog does not pass backlog-check - run bin/backlog-check.sh --repo $REPO" >&2; return 1; }
  check >/dev/null || return $?
  ensure_labels >/dev/null || return $?
  body="$(mktemp)"; trap 'rm -f "$body"' RETURN
  n="$(yq '.features | length' "$BL")"; i=0
  while [ "$i" -lt "$n" ]; do
    f="$(yq -o=json ".features[$i]" "$BL")"; key="$(jq -r .key <<<"$f")"
    labels="type::feature"; [ "$(jq -r .mvp <<<"$f")" = true ] && labels="$labels mvp"
    render feature "$f" '{}' > "$body"
    # no milestone: a feature joins a sprint when /compasso:plan pushes it
    # shellcheck disable=SC2086
    num="$(upsert_issue "$(jq -r '.gitlab // ""' <<<"$f")" "$(jq -r .title <<<"$f")" "$body" "" $labels)"
    [ -n "$num" ] || { echo "github: could not write backlog feature $key" >&2; return 1; }
    K="$key" V="$num" yq -i '(.features[] | select(.key == strenv(K)) | .gitlab) = (strenv(V) | tonumber)' "$BL"
    [ "$(jq -r .mvp <<<"$f")" = true ] || label_remove "$num" mvp
    echo "github: backlog $key -> #$num$( [ "$(jq -r .mvp <<<"$f")" = true ] && echo " (MVP)")"
    i=$((i + 1))
  done
}

# ---------- story ----------
story() {
  local n parsed feature="" fcov=null epic="" ecov=null deps blocked open='[]' d dj kind ms
  need IID
  check >/dev/null || return $?
  n="$(issue_norm "$IID")" || { echo "github: no work item #$IID in $R" >&2; return 1; }
  parsed="$(jq -r .description <<<"$n" | jq -Rs -f "$BIN/parse.jq")"
  # dependencies are GitHub's native "blocked by": blockers (type::blocker) and other work
  deps='[]'; blocked='[]'
  for d in $(blocked_by "$IID" | jq -r '.[]'); do
    dj="$(issue "$d")" || { echo "github: #$d referenced by #$IID does not exist" >&2; return 1; }
    if jq -e '[.labels[].name] | index("type::blocker")' <<<"$dj" >/dev/null; then blocked="$(jq -c ". + [$d]" <<<"$blocked")"
    else deps="$(jq -c ". + [$d]" <<<"$deps")"; fi
    [ "$(jq -r .state <<<"$dj")" = open ] || continue
    kind=depends_on; jq -e '[.labels[].name] | index("type::blocker")' <<<"$dj" >/dev/null && kind=blocked_by
    open="$(jq -c --argjson i "$d" --arg t "$(jq -r .title <<<"$dj")" --arg k "$kind" '. + [{iid: $i, title: $t, kind: $k}]' <<<"$open")"
  done
  parsed="$(jq -c --argjson d "$deps" --argjson b "$blocked" '.depends_on = $d | .blocked_by = $b' <<<"$parsed")"
  feature="$(parent_number "$IID")"
  [ -n "$feature" ] && fcov="$(issue "$feature" | jq -r '.body // ""' | jq -Rs -f "$BIN/parse.jq" | jq .coverage)"
  ms="$(jq -r '.milestone.id // empty' <<<"$n")"
  if [ -n "$ms" ]; then
    dj="$(api "repos/$R/issues?milestone=$ms&labels=type::epic&state=all" --jq '.[0] // empty')"
    if [ -n "$dj" ]; then epic="$(jq -r .number <<<"$dj")"; ecov="$(jq -r '.body // ""' <<<"$dj" | jq -Rs -f "$BIN/parse.jq" | jq .coverage)"; fi
  fi
  jq -n --argjson issue "$n" --argjson s "$parsed" --arg feature "$feature" --argjson fcov "$fcov" \
        --arg epic "$epic" --argjson ecov "$ecov" --argjson open "$open" --argjson dflt "$(cfg .coverage.min_changed)" '{
    iid: $issue.iid, id: $issue.id, title: $issue.title, state: $issue.state, type: $issue.issue_type,
    kind: (if ($issue.labels | index("type::bug")) then "bug" else "story" end),
    estimate_h: (($issue.time_stats.time_estimate // 0) / 3600),
    labels: $issue.labels, milestone: ($issue.milestone.title // null),
    feature: (if $feature == "" then null else ($feature | tonumber) end),
    epic: (if $epic == "" then null else ($epic | tonumber) end),
    story: (if ($issue.labels | index("type::bug")) then $s
             | .acceptance = (if (.acceptance | length) > 0 then .acceptance else .expected end)
             | .tests = (if (.tests | length) > 0 then .tests else ["unit"] end) else $s end),
    coverage_min: ([$s.coverage, $fcov, $ecov, $dflt] | map(select(. != null)) | first),
    open_dependencies: $open}'
}

set_state() {
  local s pj item
  need IID STATE
  case " $STATES " in *" $STATE "*) ;; *) echo "github: unknown state '$STATE'" >&2; return 1 ;; esac
  labels_set "$IID" "compasso::$STATE" || { echo "github: could not set #$IID to $STATE" >&2; return 1; }
  for s in $STATES; do [ "$s" = "$STATE" ] || label_remove "$IID" "compasso::$s"; done
  if [ "$PROJ" != 0 ] && [ -n "$(status_option "$STATE")" ]; then
    pj="$(project)"; item="$(item_for "$(jq -r .id <<<"$pj")" "$(issue "$IID" | jq -r .node_id)")"
    set_field "$(jq -r .id <<<"$pj")" "$item" "$(field_id "$pj" "$(cfg .tracker.github.fields.status)")" option \
      "$(option_id "$pj" "$(cfg .tracker.github.fields.status)" "$(status_option "$STATE")")" ||
      { echo "github: could not set the Project status of #$IID" >&2; return 1; }
  fi
  echo "github: #$IID is $STATE"
}

# ---------- pull requests ----------
open_mr() {
  local title target pr out
  need BRANCH BODY
  [ -f "$BODY" ] || { echo "github: no body file $BODY" >&2; return 1; }
  [ -n "$IID$TITLE" ] || { echo "github: open-mr needs --iid (the story's title) or --title" >&2; return 1; }
  title="$TITLE"
  [ -n "$title" ] || title="$(issue "$IID" | jq -r '.title // empty')"
  [ -n "$title" ] || { echo "github: no work item #$IID" >&2; return 1; }
  target="${TARGET:-$(api "repos/$R" --jq .default_branch)}"
  pr="$(api "repos/$R/pulls?head=$OWNER:$BRANCH&state=open" --jq '.[0].number // empty')"
  if [ -n "$pr" ]; then out="$(api -X PATCH "repos/$R/pulls/$pr" -F body=@"$BODY" -f base="$target")"
  else out="$(api -X POST "repos/$R/pulls" -f head="$BRANCH" -f base="$target" -f title="$title" -F body=@"$BODY")"; fi
  jq -e -c '{iid: .number, web_url: .html_url}' <<<"$out" 2>/dev/null || { echo "github: could not open the pull request for $BRANCH" >&2; return 1; }
}

followup() {
  local pj ms num
  need PARENT TITLE BODY
  pj="$(issue "$PARENT")"; [ -n "$(jq -r '.number // empty' <<<"$pj" 2>/dev/null)" ] || { echo "github: no work item #$PARENT" >&2; return 1; }
  ms=""; [ "$MILESTONE" = none ] || ms="$(jq -r '.milestone.number // ""' <<<"$pj")"
  # shellcheck disable=SC2046
  num="$(upsert_issue "" "$TITLE" "$BODY" "$ms" $(printf '%s' "$LABELS_ARG" | tr ',' ' '))" || true
  [ -n "$num" ] || { echo "github: could not create the follow-up" >&2; return 1; }
  attach "$num" "$PARENT" || { echo "github: created #$num but could not attach it to #$PARENT" >&2; return 1; }
  echo "$num"
}

merge() {
  local mode
  need MR
  mode="$(cfg .approvals.merge)"
  case "$mode" in agent|risk) ;; *) echo "github: approvals.merge is human - a person merges this pull request" >&2; return 1 ;; esac
  [ -n "$BODY" ] && [ -f "$BODY" ] || { echo "github: merge needs --body-file with the review findings" >&2; return 1; }
  "$BIN/review-gate.sh" --findings "$BODY" --for merge || return 1
  if [ "$mode" = risk ]; then
    [ -n "$RISK" ] && [ -f "$RISK" ] || { echo "github: approvals.merge is risk - merge needs --risk with risk.sh's decision" >&2; return 1; }
    [ "$(jq -r .level "$RISK")" = low ] || { echo "github: the change is high risk - a person merges it" >&2; return 1; }
  fi
  labels_set "$MR" compasso::auto-merged || { echo "github: could not label #$MR" >&2; return 1; }
  gh pr merge "$MR" --repo "$HOST/$R" --auto --merge >/dev/null ||
    { echo "github: could not merge #$MR (is auto-merge allowed on $R?)" >&2; return 1; }
  echo "github: #$MR merges when its checks pass"
}

mr_info() {
  need MR
  gql -f query="query { repository(owner: \"$OWNER\", name: \"${R#*/}\") { pullRequest(number: $MR) {
      number title state url isDraft headRefName baseRefName author { login }
      closingIssuesReferences(first: 20) { nodes { number } } } } }" \
    --jq '.data.repository.pullRequest // empty' 2>/dev/null |
    jq -e -c '{iid: .number, title, state: ({"OPEN": "opened", "MERGED": "merged", "CLOSED": "closed"}[.state]),
               source_branch: .headRefName, target_branch: .baseRefName, web_url: .url, author: .author.login,
               draft: .isDraft, closes: [.closingIssuesReferences.nodes[].number]}' ||
    { echo "github: no pull request #$MR in $R" >&2; return 1; }
}

comment() { # on a pull request (--mr) or an issue (--iid): on GitHub both take issue comments
  local n="${MR:-$IID}"
  need BODY
  [ -n "$n" ] || { echo "github: comment needs --mr or --iid" >&2; return 1; }
  [ -f "$BODY" ] || { echo "github: no body file $BODY" >&2; return 1; }
  api -X POST "repos/$R/issues/$n/comments" -F body=@"$BODY" --jq .id >/dev/null || { echo "github: could not comment on #$n" >&2; return 1; }
  echo "github: commented on #$n"
}

# ---------- sprint ----------
milestone_of() { api "repos/$R/milestones?state=all&per_page=100" --jq ".[] | select(.title == \"$1\") | .number" | head -1; }
sprint_issues() { # title -> normalised issues of that milestone (all states), [] when it does not exist
  local m; m="$(milestone_of "$1")"
  [ -n "$m" ] || { echo '[]'; return; }
  api --paginate "repos/$R/issues?milestone=$m&state=all&per_page=100" | jq -s 'add // [] | map(select(.pull_request | not))' |
    jq -c --argjson est "$(estimates)" "$NORM map(norm(\$est))"
}

sprint_sync() {
  local ms items enriched='[]' ext='[]' i d n cleaned='[]' parallel deps blocked p
  check >/dev/null || return $?
  ms="$MILESTONE"; [ -n "$ms" ] || ms="S$(yq -r '.epic.sprint.number // ""' "$REPO/.compasso/plan.yaml" 2>/dev/null)"
  [ "$ms" != "S" ] || { echo "github: sprint-sync needs --milestone or a .compasso/plan.yaml" >&2; return 1; }
  items="$(sprint_issues "$ms")"
  [ "$(jq length <<<"$items")" -gt 0 ] || { echo "github: no work items in milestone $ms" >&2; return 1; }
  for i in $(jq -r '.[].iid' <<<"$items"); do
    d="$(jq -c --argjson i "$i" '.[] | select(.iid == $i)' <<<"$items")"
    deps='[]'; blocked='[]'; p=""
    if [ "$(jq -r .issue_type <<<"$d")" = task ]; then
      p="$(parent_number "$i")"
      for n in $(blocked_by "$i" | jq -r '.[]'); do
        if jq -e --argjson n "$n" '.[] | select(.iid == $n) | .labels | index("type::blocker")' <<<"$items" >/dev/null ||
           issue "$n" | jq -e '[.labels[].name] | index("type::blocker")' >/dev/null; then blocked="$(jq -c ". + [$n]" <<<"$blocked")"
        else deps="$(jq -c ". + [$n]" <<<"$deps")"; fi
      done
    fi
    d="$(jq -c --argjson p "$(jq -r .description <<<"$d" | jq -Rs -f "$BIN/parse.jq" | jq -c --argjson d "$deps" --argjson b "$blocked" '.depends_on = $d | .blocked_by = $b')" \
      --arg parent "$p" '. + {parsed: $p, parent: (if $parent == "" then null else ($parent | tonumber) end)}' <<<"$d")"
    enriched="$(jq -c --argjson d "$d" '. + [$d]' <<<"$enriched")"
  done
  for i in $(jq -r '[.[].iid] as $in | [.[].parsed | (.depends_on + .blocked_by)[]] | unique | map(select(. as $x | $in | index($x) | not)) | .[]' <<<"$enriched"); do
    d="$(issue "$i")" || { echo "github: #$i is referenced in $ms but does not exist" >&2; return 1; }
    ext="$(jq -c --argjson d "$d" '. + [{iid: $d.number, state: (if $d.state == "open" then "opened" else "closed" end), title: $d.title,
      labels: [$d.labels[].name], assignees: [$d.assignees[]? | {username: .login}]}]' <<<"$ext")"
  done
  for i in $(jq -r '.[] | select(.state == "closed" and .issue_type == "task")
      | select(.labels | index("compasso::building") or index("compasso::in-review")) | .iid' <<<"$enriched"); do
    [ "$READ_ONLY" -eq 1 ] && continue   # status: report, never change the tracker
    label_remove "$i" compasso::building; label_remove "$i" compasso::in-review
    cleaned="$(jq -c --argjson i "$i" '. + [$i]' <<<"$cleaned")"
  done
  parallel="$(cfg '.sprint.parallel // 2')"
  jq -n --arg ms "$ms" --argjson items "$enriched" --argjson ext "$ext" --argjson cleaned "$cleaned" \
        --argjson parallel "$parallel" --arg feature "$PARENT" -f "$BIN/sprint.jq"
}

sprint_items() { # the sprint's work items with their label history, for the report
  local items with='[]' i ev
  need MILESTONE
  items="$(sprint_issues "$MILESTONE")"
  for i in $(jq -r '.[] | select(.issue_type == "task") | .iid' <<<"$items"); do
    ev="$(api --paginate "repos/$R/issues/$i/events?per_page=100" | jq -s -c 'add // [] | map(select(.event == "labeled" or .event == "unlabeled")
      | {action: (if .event == "labeled" then "add" else "remove" end), label: {name: .label.name}, created_at})')" || ev='[]'
    with="$(jq -c --argjson i "$i" --argjson ev "$ev" '. + [{iid: $i, label_events: $ev}]' <<<"$with")"
  done
  jq -c --argjson with "$with" 'map(. as $it | . + {label_events: ([$with[] | select(.iid == $it.iid) | .label_events][0] // [])})' <<<"$items"
}

sprint_done() { # hours done in a sprint, or null when the sprint does not exist
  need MILESTONE
  sprint_issues "$MILESTONE" | jq 'map(select(.state == "closed" and .issue_type == "task" and ((.labels | index("type::blocker")) | not)))
    | if length == 0 then null else (map(.time_stats.time_estimate // 0) | add / 3600 * 10 | round / 10) end'
}

closing_prs() { # number -> pull requests that close it: [{number, state, merged, headRefName, mergeCommit}]
  gql -f query="query { repository(owner: \"$OWNER\", name: \"${R#*/}\") { issue(number: $1) {
      closedByPullRequestsReferences(first: 10, includeClosedPrs: true) { nodes { number state merged headRefName mergeCommit { oid } } } } } }" \
    --jq '.data.repository.issue.closedByPullRequestsReferences.nodes // []'
}

merge_commit() {
  need IID
  closing_prs "$IID" | jq -e -r '[.[] | select(.merged)][0].mergeCommit.oid // empty' ||
    { echo "github: #$IID was not closed by a merged pull request" >&2; return 1; }
}

open_mr_branch() {
  need IID
  closing_prs "$IID" | jq -e -r '[.[] | select(.state == "OPEN")][0].headRefName // empty' ||
    { echo "github: #$IID has no open pull request to stack on" >&2; return 1; }
}

digest() {
  need SINCE
  api -X GET search/issues -f q="repo:$R is:pr is:merged label:compasso::auto-merged merged:>=$SINCE" -f per_page=100 --jq '.items' |
    jq -r --arg since "$SINCE" '
      "**Merged without a person** · since \($since)", "",
      (if length == 0 then "- Nothing" else (sort_by(.pull_request.merged_at)[] | "- #\(.number) \(.title) · merged \(.pull_request.merged_at[0:16] | sub("T"; " "))") end),
      "", "Each one passed review, the mandatory security review and CI, and was low risk. To undo one, revert its pull request."'
}

# ---------- protect: the repository settings Compasso relies on ----------
protect() {
  local checks info rules id wf codeql=false
  check >/dev/null || return $?
  info="$(check)"
  wf="$REPO/.github/workflows/compasso.yml"
  [ -f "$wf" ] || { echo "github: no $wf yet - run bin/ci.sh first, so the required checks exist" >&2; return 1; }
  # auto-merge (approvals.merge agent or risk) and deleting merged branches (so stacked pull requests retarget)
  api -X PATCH "repos/$R" -F allow_auto_merge=true -F delete_branch_on_merge=true >/dev/null || { echo "github: could not update $R's settings" >&2; return 1; }
  if [ "$(jq -r .capabilities.code_scanning <<<"$info")" = true ]; then
    if api -X PATCH "repos/$R/code-scanning/default-setup" -f state=configured >/dev/null 2>&1; then codeql=true
    else echo "github: CodeQL default setup could not be turned on yet (it needs code in a language CodeQL supports); run protect again later" >&2; fi
  fi
  # the workflow's gate jobs are the required checks; coverage is a warning and never required
  checks="$(yq -o=json '.jobs | keys' "$wf" | jq -c 'map(select(. == "compasso-verify" or . == "compasso-e2e" or . == "compasso-scan-gate") | {context: .})')"
  rules="$(jq -n --argjson checks "$checks" --argjson code "$codeql" '{
    name: "compasso", target: "branch", enforcement: "active",
    conditions: {ref_name: {include: ["~DEFAULT_BRANCH"], exclude: []}},
    rules: ([{type: "deletion"}, {type: "non_fast_forward"},
            {type: "pull_request", parameters: {required_approving_review_count: 0, dismiss_stale_reviews_on_push: false,
              require_code_owner_review: false, require_last_push_approval: false, required_review_thread_resolution: false}},
            {type: "required_status_checks", parameters: {strict_required_status_checks_policy: false, required_status_checks: $checks}}]
           + (if $code then [{type: "code_scanning", parameters: {code_scanning_tools: [{tool: "CodeQL", security_alerts_threshold: "high_or_higher", alerts_threshold: "errors"}]}}] else [] end))}')"
  id="$(api "repos/$R/rulesets" --jq '.[] | select(.name == "compasso") | .id' 2>/dev/null | head -1)"
  if [ -n "$id" ]; then api -X PUT "repos/$R/rulesets/$id" --input <(printf '%s' "$rules") >/dev/null
  else api -X POST "repos/$R/rulesets" --input <(printf '%s' "$rules") >/dev/null; fi ||
    { echo "github: could not write the compasso ruleset on $R" >&2; return 1; }
  echo "github: $R protected - pull requests only; required: $(jq -r 'map(.context) | join(", ")' <<<"$checks")$( [ "$codeql" = true ] && echo "; CodeQL high or higher blocks"); auto-merge on"
}

case "$CMD" in
  check) check ;;
  ensure-labels) ensure_labels ;;
  push-plan) push_plan ;;
  push-backlog) push_backlog ;;
  story) story ;;
  set-state) set_state ;;
  open-mr) open_mr ;;
  followup) followup ;;
  merge) merge ;;
  mr-info) mr_info ;;
  comment) comment ;;
  sprint-sync) sprint_sync ;;
  merge-commit) merge_commit ;;
  digest) digest ;;
  open-mr-branch) open_mr_branch ;;
  sprint-items) sprint_items ;;
  sprint-done) sprint_done ;;
  protect) protect ;;
  *) echo "usage: github.sh check|ensure-labels|push-plan|push-backlog|story|set-state|open-mr|followup|merge|mr-info|comment|sprint-sync|merge-commit|digest|open-mr-branch|sprint-items|sprint-done|protect --repo R ..." >&2; exit 1 ;;
esac
