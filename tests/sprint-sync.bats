#!/usr/bin/env bats
load helper

# Sprint S20: feature #6 with stories #8 (closed, stale label), #11 (runnable) and
# #14 (runnable, overlaps #11); feature #7 with #9 (blocked by #13) and bug #15
# (waits on open #11); #10 human-owned; #16 in review; epic #12.
setup() {
  setup_repo
  export FAKE_GL="$BATS_TEST_TMPDIR/gl"; mkdir -p "$FAKE_GL/issues" "$FAKE_GL/parent"; : > "$FAKE_GL/calls.log"
  export PATH="$ROOT/tests/fake:$PATH"
  cfg_set '.sprint.parallel = 3'
  items='[]'
  add 6  issue "Invoice history" opened '["type::feature","compasso::building"]' '**Goal:** g'
  add 7  issue "Invoice PDF" opened '["type::feature"]' '**Goal:** g'
  add 12 issue "S20: goal" opened '["type::epic"]' '**Goal:** g'
  add 8  task "Invoice list API" closed '["owner::agent","compasso::in-review"]' '**Tests:** unit' 6
  add 11 task "Year filter" opened '["owner::either"]' $'**Tests:** unit\\\n**Touches:** `src/billing/filter/**`' 6
  add 14 task "Filter by status" opened '["owner::agent"]' $'**Tests:** unit\\\n**Touches:** `src/billing/**`' 6
  add 9  task "PDF endpoint" opened '["owner::agent","blocked"]' '**Blocked by:** #13' 7
  add 13 task "PDF credentials" opened '["type::blocker","priority::urgent"]' '## Steps' "" '[{"username":"ana"}]'
  add 15 task "Empty page 2" opened '["type::bug","owner::agent"]' '**Depends on:** #11' 7
  add 10 task "Invoice list UI" opened '["owner::human"]' '**Tests:** unit' 6 '[{"username":"rui"}]'
  add 16 task "Export CSV" opened '["owner::agent","compasso::in-review"]' '**Tests:** unit' 6
  echo "$items" > "$FAKE_GL/issue-query.json"
}
add() { # iid type title state labels description [parent] [assignees]
  items="$(jq -c --argjson iid "$1" --arg t "$2" --arg title "$3" --arg s "$4" --argjson l "$5" --arg d "$6" --argjson a "${8:-[]}" \
    'map(select(.iid != $iid)) + [{iid: $iid, id: (1000 + $iid), issue_type: $t, title: $title, state: $s, labels: $l, description: $d, assignees: $a}]' <<<"$items")"
  [ -z "${7:-}" ] || echo "$((1000 + $7))" > "$FAKE_GL/parent/$((1000 + $1))"
}
sync() { "$ROOT/bin/tracker/gitlab.sh" sprint-sync --repo "$REPO" --milestone S20; }
field() { sync | jq -c "$1"; }

@test "runnable stories and bugs are the open ones with nothing open ahead of them" {
  [ "$(field '[.runnable[].iid]')" = "[11,14]" ]
}

@test "the next batch never pairs stories whose paths overlap" {
  [ "$(field '[.next_batch[].iid]')" = "[11]" ]
}

@test "the next batch is capped by sprint.parallel" {
  add 17 task "Health v2" opened '["owner::agent"]' $'**Tests:** unit\\\n**Touches:** `src/health/**`' 6
  add 18 task "Metrics" opened '["owner::agent"]' $'**Tests:** unit\\\n**Touches:** `src/metrics/**`' 6
  echo "$items" > "$FAKE_GL/issue-query.json"
  cfg_set '.sprint.parallel = 2'
  [ "$(field '[.next_batch[].iid]')" = "[11,17]" ]
}

@test "blocked stories name the blocker and who owns it" {
  [ "$(field '.blocked')" = '[{"iid":9,"title":"PDF endpoint","by":[{"iid":13,"title":"PDF credentials","assignees":["ana"]}]}]' ]
}

@test "stories waiting on open dependencies, human-owned and in-review ones are listed apart" {
  [ "$(field '[.waiting[] | [.iid, .on]]')" = '[[15,[11]]]' ]
  [ "$(field '[.human[] | [.iid, .assignees]]')" = '[[10,["rui"]]]' ]
  [ "$(field '[.in_review[].iid]')" = '[16]' ]
}

@test "a bug is built like a story" {
  [ "$(field '[.waiting[] | select(.iid == 15)] | length')" = 1 ]
  cfg_set '.sprint.parallel = 8'
  items="$(jq -c 'map(if .iid == 11 then .state = "closed" else . end)' <<<"$items")"; echo "$items" > "$FAKE_GL/issue-query.json"
  [ "$(field '[.runnable[] | select(.iid == 15) | .kind]')" = '["bug"]' ]
}

@test "a dependency outside the sprint is looked up" {
  add 11 task "Year filter" opened '["owner::either"]' '**Depends on:** #3' 6
  echo "$items" > "$FAKE_GL/issue-query.json"
  echo '{"iid":3,"state":"opened","title":"old"}' > "$FAKE_GL/issues/3.json"
  [ "$(field '[.waiting[] | select(.iid == 11) | .on]')" = '[[3]]' ]
}

@test "closed stories lose their stale in-progress label" {
  [ "$(field '.cleaned')" = "[8]" ]
  grep -q "PUT projects/acme%2Fapp/issues/8 remove_labels=compasso::building,compasso::in-review" "$FAKE_GL/calls.log"
}

@test "a feature whose stories are all closed is ready to verify" {
  [ "$(field '[.features[] | [.iid, .ready_to_verify, .open]]')" = '[[6,false,4],[7,false,2]]' ]
  items="$(jq -c 'map(if .iid == 9 or .iid == 15 then .state = "closed" else . end)' <<<"$items")"
  echo "$items" > "$FAKE_GL/issue-query.json"
  [ "$(field '[.features[] | select(.iid == 7) | .ready_to_verify]')" = '[true]' ]
}

@test "without a milestone or a plan it refuses" {
  run "$ROOT/bin/tracker/gitlab.sh" sprint-sync --repo "$REPO"
  [ "$status" -eq 1 ]
  [[ "$output" == *"needs --milestone"* ]] || false
}

@test "a closed dependency no longer holds a story back, inside or outside the sprint" {
  add 11 task "Year filter" opened '["owner::either"]' $'**Depends on:** #3, #8' 6
  echo "$items" > "$FAKE_GL/issue-query.json"
  echo '{"iid":3,"state":"closed","title":"old"}' > "$FAKE_GL/issues/3.json"
  [ "$(field '[.runnable[] | select(.iid == 11)] | length')" = 1 ]
}

@test "with --parent only that feature's stories and the feature itself count" {
  run "$ROOT/bin/tracker/gitlab.sh" sprint-sync --repo "$REPO" --milestone S20 --parent 7
  [ "$status" -eq 0 ]
  [ "$(jq -c '[.runnable[].iid]' <<<"$output")" = "[]" ]
  [ "$(jq -c '[.blocked[].iid, .waiting[].iid]' <<<"$output")" = "[9,15]" ]
  [ "$(jq -c '[.features[].iid]' <<<"$output")" = "[7]" ]
}

@test "a verifying feature whose stories and bugs are all closed is ready to finish" {
  [ "$(field '[.features[] | select(.iid == 6) | .ready_to_finish]')" = '[false]' ]
  add 6 issue "Invoice history" opened '["type::feature","compasso::verifying"]' '**Goal:** g'
  items="$(jq -c 'map(if .iid == 10 or .iid == 11 or .iid == 14 or .iid == 16 then .state = "closed" else . end)' <<<"$items")"
  echo "$items" > "$FAKE_GL/issue-query.json"
  [ "$(field '[.features[] | select(.iid == 6) | [.ready_to_verify, .ready_to_finish]]')" = '[[false,true]]' ]
}

@test "a story waiting on one story whose merge request is open can stack on it" {
  # #16 (in review) is the only open dependency of #17; #18 waits on #16 and #11
  add 17 task "Stacked story" opened '["owner::agent"]' $'**Depends on:** #16\\\n**Touches:** `src/other/**`' 6
  add 18 task "Two dependencies" opened '["owner::agent"]' $'**Depends on:** #16, #11\\\n**Touches:** `src/third/**`' 6
  echo "$items" > "$FAKE_GL/issue-query.json"
  [ "$(field '[.runnable[] | select(.iid == 17) | .stack_on]')" = '[16]' ]
  [ "$(field '[.waiting[] | select(.iid == 18) | .iid]')" = '[18]' ]
  [ "$(field '[.runnable[] | select(.iid == 11) | has("stack_on")]')" = '[false]' ]
}

@test "a story whose only dependency is not in review yet still waits" {
  add 17 task "Stacked story" opened '["owner::agent"]' '**Depends on:** #14' 6
  echo "$items" > "$FAKE_GL/issue-query.json"
  [ "$(field '[.waiting[] | select(.iid == 17) | .on]')" = '[[14]]' ]
}
