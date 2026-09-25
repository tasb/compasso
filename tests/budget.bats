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
