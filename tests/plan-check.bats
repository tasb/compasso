#!/usr/bin/env bats
load helper

setup() {
  setup_repo
  PLAN="$REPO/.compasso/plan.yaml"
  cp "$ROOT/tests/fixtures/plan.yaml" "$PLAN"
}
pc() { "$ROOT/bin/plan-check.sh" --repo "$REPO" "$@"; }
plan_set() { yq -i "$1" "$PLAN"; }
json() { pc --json | jq -r "$1"; }

@test "the fixture plan is valid" {
  run pc
  [ "$status" -eq 0 ]
  [[ "$output" == *"Total: 22h of 80h capacity"* ]] || false
}

@test "without a plan it exits 3 and points at /compasso:plan" {
  rm "$PLAN"
  run pc
  [ "$status" -eq 3 ]
  [[ "$output" == *"/compasso:plan"* ]] || false
}

@test "an invalid config stops the check" {
  cfg_set '.approvals.plan = "x"'
  run pc
  [ "$status" -eq 1 ]
}

@test "a story over one day is refused and told to split" {
  plan_set '.features[0].stories[0].estimate_h = 9'
  run pc
  [ "$status" -eq 1 ]
  [[ "$output" == *"S-1: 9h exceeds the 8h story limit - split it"* ]] || false
}

@test "a story above the target but within the limit is a note, not an error" {
  run pc
  [ "$status" -eq 0 ]
  [[ "$output" == *"S-2: 6h is above the 4h target"* ]] || false
}

@test "the story limit follows the config" {
  cfg_set '.sprint.hours_per_day = 6 | .limits.story_max_hours = 6'
  run pc
  [ "$status" -eq 1 ]
  [[ "$output" == *"S-4: 8h exceeds the 6h story limit"* ]] || false
}

@test "a feature over half a sprint is refused" {
  for i in 1 2 3 4 5; do
    plan_set ".features[0].stories += [{\"key\": \"X-$i\", \"title\": \"t\", \"as\": \"a\", \"want\": \"w\", \"so_that\": \"s\", \"acceptance\": [\"a\"], \"verify\": [\"v\"], \"tests\": [\"unit\"], \"owner\": \"agent\", \"estimate_h\": 6}]"
  done
  run pc
  [ "$status" -eq 1 ]
  [[ "$output" == *"F-1: 44h exceeds half a sprint (40h)"* ]] || false
}

@test "half a sprint follows the sprint length" {
  cfg_set '.sprint.weeks = 1'
  run pc
  [ "$status" -eq 0 ]
  [ "$(json .totals.feature_max)" = 20 ]
}

@test "an epic over capacity is refused" {
  cfg_set '.sprint.capacity_hours = 20'
  run pc
  [ "$status" -eq 1 ]
  [[ "$output" == *"E-1: 22h exceeds sprint capacity (20h)"* ]] || false
}

@test "missing required story fields are each reported" {
  plan_set 'del(.features[0].stories[0].verify) | .features[0].stories[0].acceptance = []'
  run pc
  [ "$status" -eq 1 ]
  [[ "$output" == *"S-1: verify is required"* ]] || false
  [[ "$output" == *"S-1: acceptance is required"* ]] || false
}

@test "missing required feature and epic fields are reported" {
  plan_set 'del(.features[1].scope) | .epic.goal = ""'
  run pc
  [ "$status" -eq 1 ]
  [[ "$output" == *"F-2: scope is required"* ]] || false
  [[ "$output" == *"epic.goal is required"* ]] || false
}

@test "unit tests are always required" {
  plan_set '.features[0].stories[0].tests = ["e2e"]'
  run pc
  [ "$status" -eq 1 ]
  [[ "$output" == *"S-1: tests must include unit"* ]] || false
}

@test "an unknown owner is refused" {
  plan_set '.features[0].stories[0].owner = "robot"'
  run pc
  [ "$status" -eq 1 ]
  [[ "$output" == *"S-1: owner must be agent, human or either"* ]] || false
}

@test "a dependency on an unknown story is refused; #iid references are allowed" {
  plan_set '.features[0].stories[1].depends_on = ["S-9", "#40"]'
  run pc
  [ "$status" -eq 1 ]
  [[ "$output" == *"S-2: depends on unknown story S-9"* ]] || false
  [[ "$output" != *"#40"* ]] || false
}

@test "a dependency cycle is refused and named" {
  plan_set '.features[0].stories[0].depends_on = ["S-3"]'
  run pc
  [ "$status" -eq 1 ]
  [[ "$output" == *"dependency cycle among:"*"S-1"*"S-3"* ]] || false
}

@test "duplicate keys are refused" {
  plan_set '.features[1].stories[0].key = "S-1"'
  run pc
  [ "$status" -eq 1 ]
  [[ "$output" == *"key S-1 is used more than once"* ]] || false
}

@test "a coverage override must be an integer from 0 to 100" {
  plan_set '.features[0].stories[2].coverage = 101 | .epic.coverage = 85'
  run pc
  [ "$status" -eq 1 ]
  [[ "$output" == *"S-3: coverage must be an integer from 0 to 100"* ]] || false
  [[ "$output" != *"E-1: coverage"* ]] || false
}

@test "sprint dates must run forward" {
  plan_set '.epic.sprint.end = "2026-10-01"'
  run pc
  [ "$status" -eq 1 ]
  [[ "$output" == *"epic.sprint.end must be after start"* ]] || false
}

@test "waves put a story after everything it depends on" {
  [ "$(json '.waves | map(join(",")) | join(" | ")')" = "S-1,S-4 | S-2,S-3" ]
}

@test "the critical path is the longest chain of hours" {
  [ "$(json .critical.hours)" = 10 ]
  [ "$(json '.critical.path | join(">")')" = "S-1>S-2" ]
  plan_set '.features[0].stories[2].estimate_h = 7'
  [ "$(json '.critical.path | join(">")')" = "S-1>S-3" ]
}

@test "stories touching overlapping paths are reported, others are not" {
  [ "$(json '.overlaps | map(join("/")) | join(" ")')" = "S-1/S-3" ]
}

@test "every problem is reported at once" {
  plan_set '.features[0].stories[0].estimate_h = 9 | .features[0].stories[1].owner = "x" | .epic.goal = ""'
  [ "$(json '.errors | length')" -eq 3 ]
}

@test "overlap is found whichever story has the broader path" {
  yq -i '.features[1].stories[0].touches = ["src/billing/**"]' "$PLAN"
  [ "$(json '.overlaps | map(join("/")) | join(" ")')" = "S-1/S-3 S-1/S-4 S-2/S-4 S-3/S-4" ]
}

@test "the sprint number must be a positive integer" {
  plan_set '.epic.sprint.number = 20.5'
  run pc
  [ "$status" -eq 1 ]
  plan_set '.epic.sprint.number = "twenty"'
  run pc
  [ "$status" -eq 1 ]
  [[ "$output" == *"epic.sprint.number must be a positive integer"* ]] || false
}

@test "a blocker needs a title, a person and steps" {
  plan_set 'del(.blockers[0].assignee) | .blockers[0].steps = []'
  run pc
  [ "$status" -eq 1 ]
  [[ "$output" == *"B-1: assignee is required"* ]] || false
  [[ "$output" == *"B-1: steps is required"* ]] || false
}

@test "a story can only be blocked by a blocker in the plan" {
  plan_set '.features[0].stories[0].blocked_by = ["B-9"]'
  run pc
  [ "$status" -eq 1 ]
  [[ "$output" == *"S-1: blocked by unknown blocker B-9"* ]] || false
}

@test "a blocker that blocks nothing is refused" {
  plan_set '.features[1].stories[0].blocked_by = []'
  run pc
  [ "$status" -eq 1 ]
  [[ "$output" == *"B-1: blocks no story"* ]] || false
}

@test "a story on a sensitive path needs security's abuse cases before it is built" {
  cfg_set '.risk.sensitive_paths = ["src/billing/api/**"]'
  run pc
  [ "$status" -eq 1 ]
  [[ "$output" == *"S-1: touches a sensitive path (src/billing/api/**); security must add its abuse cases"* ]] || false
  [[ "$output" == *"S-3: touches a sensitive path"* ]] || false
  [[ "$output" != *"S-2: touches a sensitive path"* ]] || false
  plan_set '(.features[].stories[] | select(.key == "S-1" or .key == "S-3")).security_reviewed = true'
  run pc
  [ "$status" -eq 0 ]
}
