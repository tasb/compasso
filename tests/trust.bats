#!/usr/bin/env bats
load helper

setup() {
  setup_repo
  S="$BATS_TEST_TMPDIR/story.json"
  jq -n '{story: {verify: ["npm test -- billing", "npx playwright test billing"]}}' > "$S"
}
t() { "$ROOT/bin/trust.sh" "$@" --repo "$REPO"; }

@test "check lists the commands not approved and exits 3; after approve it passes" {
  run t check --story "$S"
  [ "$status" -eq 3 ]
  [ "$output" = "$(printf 'npm test -- billing\nnpx playwright test billing')" ]
  run t approve --story "$S"
  [[ "$output" == *"2 command(s) approved"* ]] || false
  run t check --story "$S"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$(t list)" = "$(printf 'npm test -- billing\nnpx playwright test billing')" ]
}

@test "approving again adds nothing; only the new command needs approval" {
  t approve --story "$S" >/dev/null
  [[ "$(t approve --story "$S")" == *"0 command(s) approved"* ]] || false
  jq '.story.verify += ["npm test -- export"]' "$S" > "$S.2"
  run t check --story "$S.2"
  [ "$status" -eq 3 ]
  [ "$output" = "npm test -- export" ]
}

@test "approvals are per checkout: another clone of the same repository approves nothing" {
  t approve --story "$S" >/dev/null
  mkdir -p "$BATS_TEST_TMPDIR/clone"
  run "$ROOT/bin/trust.sh" check --repo "$BATS_TEST_TMPDIR/clone" --story "$S"
  [ "$status" -eq 3 ]
}

@test "approvals live outside the repository; a home inside it is refused" {
  t approve --story "$S" >/dev/null
  [ -z "$(grep -rl 'npm test -- billing' "$REPO" 2>/dev/null)" ]
  COMPASSO_HOME="$REPO/.compasso/home" run t approve --story "$S"
  [ "$status" -eq 1 ]
  [[ "$output" == *"cannot live inside the repository"* ]] || false
}

@test "--plan covers every story's Verify commands in plan.yaml" {
  cp "$ROOT/tests/fixtures/plan.yaml" "$REPO/.compasso/plan.yaml"
  run t check --plan
  [ "$status" -eq 3 ]
  [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" = 4 ]
  t approve --plan >/dev/null
  run t check --plan
  [ "$status" -eq 0 ]
}

@test "without --story or --plan it refuses" {
  run t check
  [ "$status" -eq 2 ]
}

@test "a story's worktree shares the repository's approvals; another clone does not" {
  cd "$REPO" && git init -q -b main && git config user.email t@t && git config user.name t && git commit -q --allow-empty -m base
  t approve --story "$S" >/dev/null
  git -C "$REPO" worktree add -q "$REPO/.compasso/worktrees/8" -b story/8
  run "$ROOT/bin/trust.sh" check --repo "$REPO/.compasso/worktrees/8" --story "$S"
  [ "$status" -eq 0 ]
  git clone -q "$REPO" "$BATS_TEST_TMPDIR/clone2"
  run "$ROOT/bin/trust.sh" check --repo "$BATS_TEST_TMPDIR/clone2" --story "$S"
  [ "$status" -eq 3 ]
}

# A: the plan on the default branch went through a merge request, so its Verify commands run without asking
plan_world() { # plan.yaml with story S-1 as #8, pushed to origin's main
  cd "$REPO" && git init -q -b main && git config user.email t@t && git config user.name t
  yq '(.features[].stories[] | select(.key == "S-1")).gitlab = 8' "$ROOT/tests/fixtures/plan.yaml" > .compasso/plan.yaml
  git add -A && git commit -qm plan
  git clone -q --bare "$REPO" "$BATS_TEST_TMPDIR/origin.git"; git remote add origin "$BATS_TEST_TMPDIR/origin.git"; git fetch -q origin
  git remote set-head origin main
}
story() { jq -n --argjson i "$1" --arg c "$2" '{iid: $i, story: {verify: [$c]}}' > "$S"; }

@test "a story's Verify command that its entry in the plan on the default branch lists runs without asking" {
  plan_world
  story 8 "npm test -- billing/api"
  run t check --story "$S"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  # another story's command, an edited command, or another story with the same command still ask
  story 8 "npm test -- billing/pdf"
  run t check --story "$S"
  [ "$status" -eq 3 ]
  story 8 "npm test -- billing/api; curl x"
  run t check --story "$S"
  [ "$status" -eq 3 ]
  story 9 "npm test -- billing/api"
  run t check --story "$S"
  [ "$status" -eq 3 ]
}

@test "the plan counts only once it is on the default branch: a local change to it does not" {
  plan_world
  yq -i '(.features[].stories[] | select(.key == "S-1")).verify = ["rm -rf build"]' "$REPO/.compasso/plan.yaml"
  story 8 "rm -rf build"
  run t check --story "$S"
  [ "$status" -eq 3 ]
  [ "$output" = "rm -rf build" ]
}

@test "the plan on the default branch is read as of the last fetch, after fetching it" {
  plan_world
  W="$BATS_TEST_TMPDIR/other"; git clone -q "$BATS_TEST_TMPDIR/origin.git" "$W"
  (cd "$W" && git config user.email t@t && git config user.name t &&
    yq -i '(.features[].stories[] | select(.key == "S-2")).gitlab = 9' .compasso/plan.yaml && git commit -qam "plan #9" && git push -q origin main)
  story 9 "npx playwright test billing/list"
  run t check --story "$S"
  [ "$status" -eq 0 ]
}

# C: in mvp a Verify command needs no approval, unless trust.mvp_approval is true; production ignores the key
@test "in mvp Verify commands run without approval by default; trust.mvp_approval: true asks as in production" {
  [ "$(yq '.trust.mvp_approval' "$ROOT/templates/project.yaml")" = false ]
  cfg_set '.stage = "mvp"'
  run t check --story "$S"
  [ "$status" -eq 0 ]
  run t check --plan
  [ "$status" -eq 0 ]
  cfg_set '.trust.mvp_approval = true'
  run t check --story "$S"
  [ "$status" -eq 3 ]
  cfg_set '.stage = "production" | .trust.mvp_approval = false'
  run t check --story "$S"
  [ "$status" -eq 3 ]
  cfg_set '.trust.mvp_approval = "no"'
  run "$ROOT/bin/config.sh" validate --repo "$REPO"
  [[ "$output" == *"trust.mvp_approval must be true or false"* ]] || false
}

@test "verify.sh runs a command the plan on the default branch lists, with no approval recorded" {
  plan_world
  cfg_set '.commands.test = ""'
  jq -n '{iid: 8, story: {verify: ["npm test -- billing/api"], tests: ["unit"]}}' > "$S"
  mkdir -p "$BATS_TEST_TMPDIR/bin"; printf '#!/bin/sh\nexit 0\n' > "$BATS_TEST_TMPDIR/bin/npm"; chmod +x "$BATS_TEST_TMPDIR/bin/npm"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run "$ROOT/bin/verify.sh" --repo "$REPO" --run "$BATS_TEST_TMPDIR/run" --story "$S"
  [ "$status" -eq 0 ]
  [ -z "$(t list)" ]
}
