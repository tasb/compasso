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
  cfg_set '.approvals.plan = "maybe"'
  run "$ROOT/bin/config.sh" validate --repo "$REPO"
  [ "$status" -eq 1 ]
  [[ "$output" == *"approvals.plan"* ]] || false
}

@test "the security role cannot run on a fast-tier Claude model" {
  cfg_set '.models.claude.security.model = "haiku"'
  run "$ROOT/bin/config.sh" validate --repo "$REPO"
  [ "$status" -eq 1 ]
  [[ "$output" == *"models.claude.security"* ]] || false
}

@test "security cannot run on a fast-tier Codex model or low effort" {
  cfg_set '.harnesses = ["claude","codex"] | .models.codex.security = {"model":"gpt-6-luna","effort":"low"}'
  run "$ROOT/bin/config.sh" validate --repo "$REPO"
  [ "$status" -eq 1 ]
  [[ "$output" == *"fast-tier"* ]] || false
  [[ "$output" == *"below the floor"* ]] || false
}

@test "other roles may use fast models" {
  cfg_set '.models.claude.tester.model = "haiku"'
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

@test "upgrade adds keys a newer Compasso introduced and keeps every value" {
  cfg_set 'del(.test_paths) | del(.ci) | .sprint.weeks = 3 | .models.claude.tester.model = "opus"'
  run "$ROOT/bin/config.sh" validate --repo "$REPO"
  [ "$status" -eq 1 ]
  [[ "$output" == *"config.sh upgrade"* ]] || false
  run "$ROOT/bin/config.sh" upgrade --repo "$REPO"
  [ "$status" -eq 0 ]
  [ "$(yq -r '.test_paths | length' "$CFG")" -gt 0 ]
  [ "$(yq -r '.ci.image' "$CFG")" = "" ]
  [ "$(yq -r .sprint.weeks "$CFG")" = 3 ]
  [ "$(yq -r .models.claude.tester.model "$CFG")" = opus ]
  [ "$(yq -r .tracker.project "$CFG")" = acme/app ]
  "$ROOT/bin/config.sh" validate --repo "$REPO"
}

@test "language: English by default, one of the languages Compasso ships, and an older choice survives the upgrade" {
  [ "$(yq -r .language "$CFG")" = en ]
  cfg_set '.language = "pt-PT"'
  "$ROOT/bin/config.sh" validate --repo "$REPO" >/dev/null
  cfg_set '.language = "xx"'
  run "$ROOT/bin/config.sh" validate --repo "$REPO"
  [ "$status" -eq 1 ]
  [[ "$output" == *"language 'xx' has no texts"* ]] || false
  cfg_set 'del(.language) | .test_guide.language = "pt-BR"'
  "$ROOT/bin/config.sh" upgrade --repo "$REPO" >/dev/null
  [ "$(yq -r .language "$CFG")" = pt-BR ]
  [ "$(yq -r '.test_guide | has("language")' "$CFG")" = false ]
}

@test "report prices are optional numbers per model" {
  run "$ROOT/bin/config.sh" validate --repo "$REPO"
  [ "$status" -eq 0 ]
  cfg_set '.metrics.prices = {"opus": 30, "sonnet": 6.5}'
  run "$ROOT/bin/config.sh" validate --repo "$REPO"
  [ "$status" -eq 0 ]
  cfg_set '.metrics.prices = {"opus": "cheap"}'
  run "$ROOT/bin/config.sh" validate --repo "$REPO"
  [ "$status" -eq 1 ]
  [[ "$output" == *"metrics.prices must map each model to a number"* ]] || false
}

@test "tracker: the provider is gitlab or github, and GitHub needs its Project fields and status options" {
  cfg_set '.tracker.provider = "jira"'
  run "$ROOT/bin/config.sh" validate --repo "$REPO"
  [ "$status" -eq 1 ]
  [[ "$output" == *"tracker.provider must be gitlab or github"* ]] || false
  cfg_set '.tracker.provider = "github" | .tracker.github.project = "seven" | .tracker.github.fields.estimate = "" | del(.tracker.github.status.done)'
  run "$ROOT/bin/config.sh" validate --repo "$REPO"
  [ "$status" -eq 1 ]
  [[ "$output" == *"tracker.github.project must be a Project number"* ]] || false
  [[ "$output" == *"tracker.github.fields.estimate is required"* ]] || false
  [[ "$output" == *"tracker.github.status.done is required"* ]] || false
  cfg_set '.tracker.github.project = 7 | .tracker.github.fields.estimate = "Estimate (h)" | .tracker.github.status.done = "Done"'
  run "$ROOT/bin/config.sh" validate --repo "$REPO"
  [ "$status" -eq 0 ]
}

@test "stage: production by default, mvp, harden or production only, and a missing stage is fine" {
  [ "$(yq -r .stage "$CFG")" = production ]
  cfg_set '.stage = "beta"'
  run "$ROOT/bin/config.sh" validate --repo "$REPO"
  [ "$status" -eq 1 ]
  [[ "$output" == *"stage must be mvp, harden or production"* ]] || false
  for s in mvp harden production; do
    cfg_set ".stage = \"$s\""
    run "$ROOT/bin/config.sh" validate --repo "$REPO"
    [ "$status" -eq 0 ]
  done
  cfg_set 'del(.stage)'
  run "$ROOT/bin/config.sh" validate --repo "$REPO"
  [ "$status" -eq 0 ]
}

@test "run: how often the lead and the developers wake, how long a job may take, and who answers" {
  [ "$(yq -o=json -I0 '.run | del(.allow)' "$CFG")" = '{"lead_minutes":15,"dev_minutes":10,"job_minutes":60,"failures":2}' ]
  [ "$(yq -o=json -I0 .people "$CFG")" = '{"ask":[]}' ]
  [ "$(yq -o=json -I0 .team.developers "$CFG")" = '[]' ]
  [ "$(yq -o=json -I0 .run.allow "$CFG")" = '[]' ]
  cfg_set '.run.lead_minutes = 0 | .run.dev_minutes = "ten" | .run.job_minutes = 0 | .run.failures = 0 | .people.ask = "ana" | .team.developers = "jobs" | .run.allow = "Bash(make)"'
  run "$ROOT/bin/config.sh" validate --repo "$REPO"
  [ "$status" -eq 1 ]
  [[ "$output" == *"run.lead_minutes must be a whole number of minutes, at least 1"* ]] || false
  [[ "$output" == *"run.dev_minutes must be a whole number of minutes, at least 1"* ]] || false
  [[ "$output" == *"run.job_minutes must be a whole number of minutes, at least 1"* ]] || false
  [[ "$output" == *"run.failures must be at least 1"* ]] || false
  [[ "$output" == *"people.ask must be a list of tracker logins"* ]] || false
  [[ "$output" == *"team.developers must be a list of names"* ]] || false
  [[ "$output" == *"run.allow must be a list of tool rules"* ]] || false
  cfg_set '.run = {"lead_minutes": 5, "dev_minutes": 5, "job_minutes": 30, "failures": 1} | .people.ask = ["ana"] | .team.developers = ["jobs"] | .run.allow = ["Bash(make check)"]'
  run "$ROOT/bin/config.sh" validate --repo "$REPO"
  [ "$status" -eq 0 ]
}

@test "team: the queue" {
  [ "$(yq -o=json -I0 .team.queue "$CFG")" = '{"target":15,"min":5}' ]
  cfg_set '.team.queue = {"target": 4, "min": 5}'
  run "$ROOT/bin/config.sh" validate --repo "$REPO"
  [ "$status" -eq 1 ]
  [[ "$output" == *"team.queue.min must be at least 1 and at most team.queue.target"* ]] || false
}

@test "upgrade to 4.0.0: renamed keys keep their value, keys nothing reads go" {
  cfg_set 'del(.trust.verify_approval) | del(.prototype) | .trust.mvp_approval = true | .harden.images.a11y = "pw:v1.2.3"
    | .limits.agent_runs.total = 30 | .approvals.merge = "risk" | .team.agents = ["bot"] | .team.poll_minutes = 60
    | .models.claude.builder = {"model": "sonnet"} | .risk.infra_paths = ["**/*.tf"]'
  "$ROOT/bin/config.sh" upgrade --repo "$REPO" >/dev/null
  [ "$(yq -r .trust.verify_approval "$CFG")" = true ]
  [ "$(yq -r .prototype.image "$CFG")" = pw:v1.2.3 ]
  for k in .trust.mvp_approval .harden .limits.agent_runs .approvals.merge .team.agents .team.poll_minutes .models.claude.builder .risk.infra_paths; do
    [ "$(yq -r "$k" "$CFG")" = null ] || { echo "$k is still there"; false; }
  done
  [ "$(yq -r .approvals.plan "$CFG")" = human ]
  "$ROOT/bin/config.sh" validate --repo "$REPO"
}
