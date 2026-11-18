#!/usr/bin/env bats
load helper

# bin/next.jq: from a tracker snapshot, the one job the lead or a developer runs next, or none.
# Built from parts: story/bug/feature/ask make work items, mr makes a merge request.

story() { # iid state dev [needs_human] [blocked_by-json] [kind] [feature] [sprint due date]
  jq -nc --argjson i "$1" --arg s "$2" --arg d "$3" --argjson h "${4:-false}" --argjson b "${5:-[]}" --arg k "${6:-story}" --argjson f "${7:-null}" --arg due "${8:-}" \
    '{iid: $i, title: "t\($i)", kind: $k, state: (if $s == "" then null else $s end), dev: (if $d == "" then null else $d end),
      feature: $f, needs_human: $h, blocked_by: $b, ask_for: null, labels: [], sprint: (if $due == "" then null else {title: "S", due: $due} end)}'
}
ask() { jq -nc --argjson i "$1" --argjson f "$2" --arg k "${3:-q}" '{iid: $i, title: "q", kind: "ask", state: null, dev: null, needs_human: true, blocked_by: [], ask_for: $f, ask_key: $k, labels: ["needs::human"]}'; }
feature() { jq -nc --argjson i "$1" --arg s "$2" --arg due "${3:-}" '{iid: $i, title: "f", kind: "feature", state: $s, dev: null, needs_human: false, blocked_by: [], ask_for: null, labels: [],
  sprint: (if $due == "" then null else {title: "S", due: $due} end)}'; }
mr() { # iid story pipeline [rework] [draft] [labels-json]
  jq -nc --argjson i "$1" --argjson s "$2" --arg p "$3" --argjson r "${4:-false}" --argjson d "${5:-false}" --argjson l "${6:-[]}" \
    '{iid: $i, story: $s, pipeline: $p, rework: $r, draft: $d, labels: $l, branch: "story/\($s)"}'
}
# snap <main-pipeline> <item>... : items whose JSON has "pipeline" are merge requests
snap() {
  local main="$1"; shift
  printf '%s\n' "$@" | jq -sc --arg m "$main" '{issues: map(select(has("pipeline") | not)), mrs: map(select(has("pipeline"))), main: {pipeline: $m, sha: "s"}}'
}
next() { # role name snapshot [skip-json] -> the job; $STAGE (mvp) and $AUDITED (false) as the runner passes them
  jq -c -L "$ROOT/bin" --arg role "$1" --arg name "$2" --argjson devs '["ana","rui"]' --argjson queue 2 \
    --argjson skip "${4:-[]}" --arg stage "${STAGE:-mvp}" --argjson audited "${AUDITED:-false}" 'include "next"; next' <<<"$3"
}
later() { jq -nc --argjson i "$1" '{iid: $i, title: "After the MVP", kind: "later", state: "after-mvp", dev: null, needs_human: false, blocked_by: [], ask_for: null, labels: ["compasso::after-mvp"]}'; }

@test "developer: nothing assigned to it is no job, so no model starts" {
  [ "$(next dev ana "$(snap success "$(story 1 backlog rui)" "$(story 2 backlog "")")")" = '{"job":null}' ]
}

@test "developer: the oldest ready story assigned to it; a blocked one, or one waiting for a person, waits" {
  s="$(snap success "$(story 5 backlog ana)" "$(story 3 backlog ana false '[9]')" "$(story 4 backlog ana true)" "$(story 7 backlog ana)")"
  [ "$(next dev ana "$s")" = '{"job":"build","iids":[5],"key":"build:5"}' ]
}

@test "developer: an open story with no state yet is not started, so it is ready" {
  s="$(snap success "$(story 5 "" ana)")"
  [ "$(next dev ana "$s")" = '{"job":"build","iids":[5],"key":"build:5"}' ]
}

@test "developer: rework on its merge request comes first, then a story it was building when the last run stopped" {
  s="$(snap success "$(story 5 backlog ana)" "$(story 6 building ana)" "$(story 8 in-review ana)" "$(mr 30 8 success true)")"
  [ "$(next dev ana "$s")" = '{"job":"rework","iids":[8],"mrs":[30],"key":"rework:8"}' ]
  s="$(snap success "$(story 5 backlog ana)" "$(story 6 building ana)")"
  [ "$(next dev ana "$s")" = '{"job":"build","iids":[6],"key":"build:6"}' ]
  s="$(snap success "$(story 5 backlog ana)" "$(story 6 building ana)" "$(mr 31 6 running)")"
  [ "$(next dev ana "$s")" = '{"job":"build","iids":[5],"key":"build:5"}' ]
}

@test "developer: a merge request whose pipeline failed is rework too" {
  s="$(snap success "$(story 5 backlog ana)" "$(story 8 in-review ana)" "$(mr 30 8 failed)")"
  [ "$(next dev ana "$s")" = '{"job":"rework","iids":[8],"mrs":[30],"key":"rework:8"}' ]
}

@test "developer: its stories of the current sprint come before a later sprint's, and before those in no sprint" {
  s="$(snap success "$(story 5 backlog ana false '[]' story null)" "$(story 6 backlog ana false '[]' story null 2026-12-11)" "$(story 7 backlog ana false '[]' story null 2026-11-27)")"
  [ "$(next dev ana "$s" | jq -c .iids)" = '[7]' ]
}

@test "developer: bugs count as stories, and a job that failed too often is skipped" {
  s="$(snap success "$(story 5 backlog ana false '[]' bug)" "$(story 6 backlog ana)")"
  [ "$(next dev ana "$s")" = '{"job":"build","iids":[5],"key":"build:5"}' ]
  [ "$(next dev ana "$s" '["build:5"]')" = '{"job":"build","iids":[6],"key":"build:6"}' ]
}

@test "lead: a story whose question was answered is unblocked by the runner itself" {
  s="$(snap success "$(story 5 backlog ana true)" "$(story 6 backlog rui true)" "$(ask 20 6)")"
  [ "$(next lead "" "$s")" = '{"job":"unblock","iids":[5],"key":"unblock:5"}' ]
}

@test "lead: a red main comes first, unless its fix is already open; the fix itself is never reviewed" {
  s="$(snap failed "$(story 5 in-review ana)" "$(mr 30 5 success)")"
  [ "$(next lead "" "$s")" = '{"job":"red-main","iids":[],"mrs":[],"key":"red-main:s"}' ]
  s="$(snap failed "$(story 5 in-review ana)" "$(mr 30 5 success)" "$(mr 31 9 running false false '["compasso::fix-main"]')")"
  [ "$(next lead "" "$s")" = '{"job":"review","iids":[5],"mrs":[30],"key":"review:30"}' ]
  s="$(snap failed "$(story 5 in-review ana)" "$(mr 30 5 success)" "$(mr 31 9 success false false '["compasso::fix-main"]')")"
  [ "$(next lead "" "$s")" = '{"job":"review","iids":[5],"mrs":[30],"key":"review:30"}' ]
}

@test "lead: a fix whose pipeline failed is a red-main job again, so a person is asked; an open question about it waits" {
  s="$(snap failed "$(mr 31 9 failed false false '["compasso::fix-main"]')")"
  [ "$(next lead "" "$s")" = '{"job":"red-main","iids":[],"mrs":[31],"key":"red-main:s"}' ]
  s="$(snap failed "$(mr 31 9 failed false false '["compasso::fix-main"]')" "$(ask 40 null red-main-abc12345)")"
  [ "$(next lead "" "$s")" = '{"job":null}' ]
}

@test "lead: every green merge request that is not a draft, in rework or waiting for a person, in one review job" {
  s="$(snap success "$(story 5 in-review ana)" "$(story 6 in-review rui true)" "$(ask 20 6)" "$(story 7 in-review ana)" "$(story 8 in-review rui)" "$(story 9 in-review ana)" \
    "$(mr 30 5 success)" "$(mr 31 6 success)" "$(mr 32 7 failed)" "$(mr 33 8 success false true)" "$(mr 34 9 success true)" "$(mr 35 1 success)")"
  [ "$(next lead "" "$s")" = '{"job":"review","iids":[5,1],"mrs":[30,35],"key":"review:30,35"}' ]
}

@test "lead: assigns when a developer has fewer ready stories than the queue and an unassigned one is ready" {
  s="$(snap success "$(story 5 backlog ana)" "$(story 6 backlog ana)" "$(story 7 backlog rui)" "$(story 8 backlog rui)" "$(story 9 backlog "")")"
  [ "$(next lead "" "$s")" = '{"job":null}' ]
  s="$(snap success "$(story 5 backlog ana)" "$(story 6 backlog ana)" "$(story 7 backlog rui)" "$(story 9 backlog "")" "$(story 10 backlog "" false '[5]')")"
  [ "$(next lead "" "$s")" = '{"job":"assign","iids":[9],"devs":["rui"],"key":"assign:9"}' ]
  s="$(snap success "$(story 5 backlog ana)" "$(story 6 backlog ana)" "$(story 7 backlog rui)" "$(story 10 backlog "" false '[5]')")"
  [ "$(next lead "" "$s")" = '{"job":null}' ]
  s="$(snap success "$(story 5 backlog ana)" "$(story 9 backlog "")")"
  [ "$(next lead "" "$s" | jq -c .devs)" = '["rui","ana"]' ]
}

@test "lead: assigns the current sprint's stories first, but goes on to a later sprint's before the current one ends" {
  s="$(snap success "$(story 5 backlog ana)" "$(story 6 backlog ana)" "$(story 9 backlog "" false '[]' story null 2026-12-11)" "$(story 10 backlog "" false '[]' story null 2026-11-27)")"
  [ "$(next lead "" "$s" | jq -c .iids)" = '[10]' ]
  s="$(snap success "$(story 5 backlog ana)" "$(story 6 backlog ana)" "$(story 8 building rui false '[]' story null 2026-11-27)" "$(story 9 backlog "" false '[]' story null 2026-12-11)")"
  [ "$(next lead "" "$s" | jq -c .iids)" = '[9]' ]
}

@test "lead: work for a person (owner::human) is never assigned to an agent" {
  s="$(snap success "$(story 5 backlog ana)" "$(story 6 backlog ana)" "$(story 9 backlog "" | jq -c '.labels = ["owner::human"]')")"
  [ "$(next lead "" "$s")" = '{"job":null}' ]
}

@test "lead: plans the next feature of the earliest sprint" {
  s="$(snap success "$(feature 3 new 2026-12-11)" "$(feature 4 new 2026-11-27)" "$(story 5 backlog ana)")"
  [ "$(next lead "" "$s" | jq -c .iids)" = '[4]' ]
}

@test "lead: a feature being built with no story of it left open is delivered, once main is green" {
  s="$(snap success "$(feature 4 building)" "$(feature 3 new)" "$(story 9 backlog ana false '[]' story 7)" "$(story 10 backlog rui)" "$(story 11 backlog ana)")"
  [ "$(next lead "" "$s")" = '{"job":"deliver","iids":[4],"key":"deliver:4"}' ]
  s="$(snap success "$(feature 4 building)" "$(story 9 in-review ana false '[]' bug 4)" "$(story 10 backlog rui)" "$(story 11 backlog ana)")"
  [ "$(next lead "" "$s")" = '{"job":null}' ]
  s="$(snap failed "$(feature 4 building)" "$(mr 31 9 running false false '["compasso::fix-main"]')")"
  [ "$(next lead "" "$s")" = '{"job":null}' ]
}

@test "lead: when no story is left to assign and a developer runs short, it plans the next feature" {
  s="$(snap success "$(feature 4 new)" "$(feature 3 new)" "$(story 5 backlog ana)")"
  [ "$(next lead "" "$s")" = '{"job":"plan","iids":[3],"key":"plan:3"}' ]
  s="$(snap success "$(feature 4 building)" "$(story 5 backlog ana false '[]' story 4)")"
  [ "$(next lead "" "$s")" = '{"job":null}' ]
  s="$(snap success "$(feature 3 new)" "$(story 5 backlog ana)" "$(story 9 backlog "")")"
  [ "$(next lead "" "$s" '["assign:9"]')" = '{"job":null}' ]
}

@test "lead: an unblock beats a red main, a red main beats a review, a review beats the rest" {
  s="$(snap failed "$(story 5 in-review ana)" "$(mr 30 5 success)" "$(story 6 backlog rui true)")"
  [ "$(next lead "" "$s" | jq -r .job)" = unblock ]
  s="$(snap success "$(story 5 in-review ana)" "$(mr 30 5 success)" "$(story 9 backlog "")" "$(feature 4 building)")"
  [ "$(next lead "" "$s" | jq -r .job)" = review ]
  [ "$(next lead "" "$s" '["review:30"]' | jq -r .job)" = deliver ]
}

@test "harden: the lead audits the whole code once, after the reviews and before anything else" {
  s="$(snap success "$(story 5 in-review ana)" "$(mr 30 5 success)" "$(later 40)" "$(story 9 backlog "")")"
  STAGE=harden; [ "$(next lead "" "$s" | jq -r .job)" = review ]
  [ "$(next lead "" "$s" '["review:30"]')" = '{"job":"audit","iids":[],"key":"audit"}' ]
  AUDITED=true; [ "$(next lead "" "$s" '["review:30"]')" = '{"job":"drain","iids":[40],"key":"drain:40"}' ]
}

@test "harden: an open after-MVP list is drained into stories; in the MVP it only grows" {
  s="$(snap success "$(later 40)" "$(feature 4 building)")"
  STAGE=harden AUDITED=true; [ "$(next lead "" "$s")" = '{"job":"drain","iids":[40],"key":"drain:40"}' ]
  STAGE=mvp; [ "$(next lead "" "$s" | jq -r .job)" = deliver ]
}

@test "bugs first, the most severe first, before any sprint's stories: for the developer and for assignment" {
  bug() { story "$1" backlog "$2" false '[]' bug | jq -c --arg s "$3" '.labels = ["type::bug", "severity::\($s)"]'; }
  s="$(snap success "$(story 5 backlog ana false '[]' story null 2026-11-27)" "$(bug 6 ana minor)" "$(bug 7 ana major)")"
  [ "$(next dev ana "$s" | jq -c .iids)" = '[7]' ]
  s="$(snap success "$(story 5 backlog ana)" "$(story 6 backlog ana)" "$(story 9 backlog "" false '[]' story null 2026-11-27)" "$(bug 10 "" blocker)")"
  [ "$(next lead "" "$s" | jq -c .iids)" = '[10]' ]
}

@test "production: the list of what the reviews left is drained too, without an audit" {
  s="$(snap success "$(later 40)")"
  STAGE=production; [ "$(next lead "" "$s")" = '{"job":"drain","iids":[40],"key":"drain:40"}' ]
}
