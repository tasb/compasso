#!/usr/bin/env bats
load helper

setup() { setup_repo; }

@test "the template, given a project, is valid" {
  run "$ROOT/bin/config.sh" validate --repo "$REPO"
  [ "$status" -eq 0 ]
}

@test "defaults: two-week sprint, hour limits of one day and half a day, human approvals" {
  [ "$(yq -r .sprint.weeks "$CFG")" = 2 ]
  [ "$(yq -r .limits.story_max_hours "$CFG")" = 8 ]
  [ "$(yq -r .limits.story_target_hours "$CFG")" = 4 ]
  [ "$(yq -r .approvals.plan "$CFG")" = human ]
  [ "$(yq -r .approvals.merge "$CFG")" = human ]
}

@test "init refuses to overwrite an existing config" {
  run "$ROOT/bin/config.sh" init --repo "$REPO"
  [ "$status" -eq 1 ]
  [[ "$output" == *"already exists"* ]] || false
}

@test "validate without a config exits 3 and points at setup" {
  run "$ROOT/bin/config.sh" validate --repo "$BATS_TEST_TMPDIR/empty"
  [ "$status" -eq 3 ]
  [[ "$output" == *"/compasso:setup"* ]] || false
}

@test "a missing project is rejected" {
  cfg_set '.tracker.project = ""'
  run "$ROOT/bin/config.sh" validate --repo "$REPO"
  [ "$status" -eq 1 ]
  [[ "$output" == *"tracker.project"* ]] || false
}

@test "a story limit above one working day is rejected" {
  cfg_set '.limits.story_max_hours = 12'
  run "$ROOT/bin/config.sh" validate --repo "$REPO"
  [ "$status" -eq 1 ]
  [[ "$output" == *"exceeds one working day"* ]] || false
}

@test "a story target above the limit is rejected" {
  cfg_set '.limits.story_target_hours = 10'
  run "$ROOT/bin/config.sh" validate --repo "$REPO"
  [ "$status" -eq 1 ]
  [[ "$output" == *"story_target_hours"* ]] || false
}

@test "unknown approval modes are rejected" {
  cfg_set '.approvals.plan = "maybe" | .approvals.merge = "auto"'
  run "$ROOT/bin/config.sh" validate --repo "$REPO"
  [ "$status" -eq 1 ]
  [[ "$output" == *"approvals.plan"* ]] || false
  [[ "$output" == *"approvals.merge"* ]] || false
}

@test "the security role cannot run on a fast-tier Claude model" {
  cfg_set '.models.claude.security.model = "haiku"'
  run "$ROOT/bin/config.sh" validate --repo "$REPO"
  [ "$status" -eq 1 ]
  [[ "$output" == *"models.claude.security"* ]] || false
}

@test "the approver cannot run on a fast-tier Codex model or low effort" {
  cfg_set '.harnesses = ["claude","codex"] | .models.codex.approver = {"model":"gpt-6-luna","effort":"low"}'
  run "$ROOT/bin/config.sh" validate --repo "$REPO"
  [ "$status" -eq 1 ]
  [[ "$output" == *"fast-tier"* ]] || false
  [[ "$output" == *"below the floor"* ]] || false
}

@test "other roles may use fast models" {
  cfg_set '.models.claude.builder.model = "haiku"'
  run "$ROOT/bin/config.sh" validate --repo "$REPO"
  [ "$status" -eq 0 ]
}

@test "codex models are only checked when codex is an enabled harness" {
  cfg_set 'del(.models.codex)'
  run "$ROOT/bin/config.sh" validate --repo "$REPO"
  [ "$status" -eq 0 ]
  cfg_set '.harnesses = ["claude","codex"]'
  run "$ROOT/bin/config.sh" validate --repo "$REPO"
  [ "$status" -eq 1 ]
  [[ "$output" == *"models.codex.planner.model is required"* ]] || false
}

@test "a switch for security review is refused" {
  cfg_set '.security = {"enabled": false}'
  run "$ROOT/bin/config.sh" validate --repo "$REPO"
  [ "$status" -eq 1 ]
  [[ "$output" == *"mandatory"* ]] || false
}

@test "every problem is reported at once" {
  cfg_set '.sprint.weeks = 0 | .approvals.plan = "x" | .models.claude.security.model = "haiku"'
  run "$ROOT/bin/config.sh" validate --repo "$REPO"
  [ "$status" -eq 1 ]
  [ "$(printf '%s\n' "$output" | grep -c '^  - ')" -eq 3 ]
}

@test "get prints one value" {
  run "$ROOT/bin/config.sh" get --repo "$REPO" .tracker.project
  [ "$output" = "acme/app" ]
}

@test "coverage defaults to 80% of changed lines, not measured until a command is set" {
  [ "$(yq -r .coverage.min_changed "$CFG")" = 80 ]
  [ "$(yq -r .coverage.command "$CFG")" = "" ]
}

@test "a coverage threshold outside 0-100 is rejected" {
  cfg_set '.coverage.min_changed = 120'
  run "$ROOT/bin/config.sh" validate --repo "$REPO"
  [ "$status" -eq 1 ]
  [[ "$output" == *"coverage.min_changed"* ]] || false
}

@test "a coverage command needs the report it writes" {
  cfg_set '.coverage.command = "npm test -- --coverage"'
  run "$ROOT/bin/config.sh" validate --repo "$REPO"
  [ "$status" -eq 1 ]
  [[ "$output" == *"coverage.report is required"* ]] || false
  cfg_set '.coverage.report = "coverage/cobertura.xml"'
  run "$ROOT/bin/config.sh" validate --repo "$REPO"
  [ "$status" -eq 0 ]
}

@test "test_paths must list at least one pattern" {
  cfg_set 'del(.test_paths)'
  run "$ROOT/bin/config.sh" validate --repo "$REPO"
  [ "$status" -eq 1 ]
  [[ "$output" == *"test_paths must list at least one pattern"* ]] || false
}
