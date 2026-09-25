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
