#!/usr/bin/env bats
load helper

setup() { setup_repo; RUN="$BATS_TEST_TMPDIR/run"; cfg_set '.limits.agent_runs.reviewer = 2 | .limits.agent_runs.total = 4'; }
b() { "$ROOT/bin/budget.sh" "$@" --repo "$REPO" --run "$RUN"; }

@test "claims count per role; the one past the role's limit is refused" {
  run b claim --role reviewer
  [ "$status" -eq 0 ]
  [ "$output" = "budget: reviewer run 1 of 2 (all roles: 1 of 4)" ]
  b claim --role reviewer >/dev/null
  run b claim --role reviewer
  [ "$status" -eq 3 ]
  [[ "$output" == *"STOP - reviewer has run 2 times in this flow run (limit 2)"* ]] || false
  [ "$(wc -l < "$RUN/budget.jsonl" | tr -d ' ')" = 2 ]
}

@test "the total for every role together is a limit of its own" {
  b claim --role tester >/dev/null; b claim --role builder >/dev/null; b claim --role builder >/dev/null; b claim --role security >/dev/null
  run b claim --role builder
  [ "$status" -eq 3 ]
  [[ "$output" == *"4 agent runs in this flow run (limit 4)"* ]] || false
}

@test "a restarted flow continues the same budget; only reset starts again" {
  b claim --role reviewer >/dev/null; b claim --role reviewer >/dev/null
  run b claim --role reviewer
  [ "$status" -eq 3 ]
  "$ROOT/bin/budget.sh" reset --run "$RUN" >/dev/null
  run b claim --role reviewer
  [ "$status" -eq 0 ]
}

@test "on Claude Code a claim by hand is refused and spends nothing: the hook claims when the agent is dispatched" {
  CLAUDECODE=1 run b claim --role tester
  [ "$status" -eq 1 ]
  [[ "$output" == *"the hook claims the budget when compasso:tester is dispatched"* ]] || false
  [ ! -s "$RUN/budget.jsonl" ]
  CLAUDECODE=1 run b claim --role tester --hook
  [ "$status" -eq 0 ]
  run b claim --role tester
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$RUN/budget.jsonl" | tr -d ' ')" = 2 ]
}

@test "reset --role gives one role its runs back and keeps the others'" {
  b claim --role reviewer >/dev/null; b claim --role reviewer >/dev/null; b claim --role tester >/dev/null
  "$ROOT/bin/budget.sh" reset --run "$RUN" --role reviewer >/dev/null
  [ "$(jq -sc 'map(.role)' "$RUN/budget.jsonl")" = '["tester"]' ]
  run b claim --role reviewer
  [ "$status" -eq 0 ]
}

@test "show lists runs used and left; an unknown role is refused" {
  b claim --role security >/dev/null
  run b show
  [[ "$output" == *"security: 1 of 4"* ]] || false
  [[ "$output" == *"all roles: 1 of 4"* ]] || false
  run b claim --role planner
  [ "$status" -eq 1 ]
  run b claim --role total
  [ "$status" -eq 1 ]
}

@test "a config without the limits is invalid and says how to fix it" {
  cfg_set 'del(.limits.agent_runs)'
  run b claim --role tester
  [ "$status" -eq 1 ]
  run "$ROOT/bin/config.sh" validate --repo "$REPO"
  [[ "$output" == *"limits.agent_runs.tester must be a positive integer (run: config.sh upgrade)"* ]] || false
}

@test "the defaults cover the story flow's worst case: tester 9, builder 10, reviewer 6, 30 in all; 40 in mvp" {
  [ "$(yq -o=json -I0 '.limits.agent_runs | [.tester, .builder, .reviewer, .total, .mvp_total]' "$ROOT/templates/project.yaml")" = '[9,10,6,30,40]' ]
}

@test "in mvp only the total applies, limits.agent_runs.mvp_total" {
  cfg_set '.stage = "mvp" | .limits.agent_runs.mvp_total = 5'
  for i in 1 2 3 4; do b claim --role reviewer >/dev/null; done
  run b claim --role reviewer
  [ "$status" -eq 0 ]
  [ "$output" = "budget: reviewer run 5 (all roles: 5 of 5)" ]
  run b claim --role tester
  [ "$status" -eq 3 ]
  [[ "$output" == *"5 agent runs in this flow run (limit 5)"* ]] || false
  run b claim --role mvp_total
  [ "$status" -eq 1 ]
  run b show
  [[ "$output" == *"reviewer: 5"* ]] || false
  [[ "$output" == *"all roles: 5 of 5"* ]] || false
  cfg_set '.limits.agent_runs.mvp_total = 0'
  run "$ROOT/bin/config.sh" validate --repo "$REPO"
  [[ "$output" == *"limits.agent_runs.mvp_total must be a positive integer"* ]] || false
}

@test "a project from before mvp_total and trust.mvp_approval validates, with 40 and false" {
  cfg_set 'del(.limits.agent_runs.mvp_total) | del(.trust) | .stage = "mvp"'
  run "$ROOT/bin/config.sh" validate --repo "$REPO"
  [ "$status" -eq 0 ]
  mkdir -p "$RUN"; for i in $(seq 1 39); do echo '{"role":"tester"}'; done > "$RUN/budget.jsonl"
  run b claim --role tester
  [ "$output" = "budget: tester run 40 (all roles: 40 of 40)" ]
  jq -n '{story: {verify: ["make check"]}}' > "$BATS_TEST_TMPDIR/story.json"
  run "$ROOT/bin/trust.sh" check --repo "$REPO" --story "$BATS_TEST_TMPDIR/story.json"
  [ "$status" -eq 0 ]
}

# rework: story #14's pull request #31 came back from the tech lead (GitHub fake)
rework_world() { # labels-json [no-mr]
  cfg_set '.tracker.provider = "github" | .tracker.host = "github.com"'
  export FAKE_GH="$BATS_TEST_TMPDIR/gh"; mkdir -p "$FAKE_GH"/{issues,parent,blocked,comments,closing}; : > "$FAKE_GH/calls.log"
  export PATH="$ROOT/tests/fake:$PATH"
  echo '[{"number":1,"title":"S20"}]' > "$FAKE_GH/milestones.json"
  jq -n --argjson l "$1" '{number: 14, id: 1014, node_id: "I_14", title: "Status filter", state: "open", body: "**Tests:** unit",
    labels: ($l | map({name: .})), milestone: {number: 1, title: "S20"}, assignees: [], created_at: "2026-10-05T09:00:00Z", closed_at: null}' > "$FAKE_GH/issues/14.json"
  [ -n "${2:-}" ] && echo '[]' > "$FAKE_GH/closing/14.json" ||
    echo '[{"number":31,"state":"OPEN","merged":false,"headRefName":"story/14-status","baseRefName":"main","url":"u","mergeCommit":null}]' > "$FAKE_GH/closing/14.json"
}

@test "rework: a story sent back on its open merge request starts a new budget; the spent one is kept" {
  rework_world '["dev::rui","compasso::backlog"]'
  b claim --role reviewer >/dev/null; b claim --role reviewer >/dev/null
  run b rework --iid 14
  [ "$status" -eq 0 ]
  [ "$(jq -sc 'map(.role)' "$RUN/budget-1.jsonl")" = '["reviewer","reviewer"]' ]
  run b claim --role reviewer
  [ "$output" = "budget: reviewer run 1 of 2 (all roles: 1 of 4)" ]
  run b show
  [[ "$output" == *"all roles: 1 of 4"* ]] || false
  # the next rework keeps both earlier budgets
  b rework --iid 14 >/dev/null
  [ -f "$RUN/budget-2.jsonl" ]
  [ -f "$RUN/budget-1.jsonl" ]
}

@test "rework is refused while the story is being built, or when it has no open merge request" {
  rework_world '["dev::rui","compasso::building"]'
  b claim --role reviewer >/dev/null
  run b rework --iid 14
  [ "$status" -eq 1 ]
  [[ "$output" == *"#14 is being built"* ]] || false
  rework_world '["dev::rui","compasso::backlog"]' no-mr
  run b rework --iid 14
  [ "$status" -eq 1 ]
  [[ "$output" == *"#14 has no open merge request"* ]] || false
  [ "$(wc -l < "$RUN/budget.jsonl" | tr -d ' ')" = 1 ]
  [ ! -f "$RUN/budget-1.jsonl" ]
}
