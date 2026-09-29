#!/usr/bin/env bats
load helper

setup() { setup_repo; CAT="$ROOT/tests/fixtures/codex-catalog.json"; }
cm() { "$ROOT/bin/codex-models.sh" check --repo "$REPO" --catalog "$CAT" "$@"; }

@test "models the account cannot use are problems, with a proposal by the role's tier" {
  run cm
  [ "$status" -eq 3 ]
  [[ "$output" == *"security: 'gpt-6-astra' is not available to this Codex account -> gpt-9-terra (effort high, strong tier)"* ]] || false
  [[ "$output" == *"builder: 'gpt-6-sol' is not available to this Codex account -> gpt-9-luna (effort medium, standard tier)"* ]] || false
  [[ "$output" == *"shipper: 'gpt-6-luna' is not available to this Codex account -> gpt-9-luna (effort low, fast tier)"* ]] || false
}

@test "hidden models are never proposed; strong roles never get a fast-tier model" {
  run cm
  [[ "$output" != *"gpt-9-secret"* ]] || false
  [ "$(grep -E '^(planner|security|approver|reviewer):' <<<"$output" | grep -c 'gpt-9-terra')" -eq 4 ]
}

@test "--apply writes the proposals, the result passes config validation, and a second check is clean" {
  run cm --apply
  [ "$status" -eq 3 ]
  [ "$(yq -r '.models.codex.security.model' "$CFG")" = gpt-9-terra ]
  "$ROOT/bin/config.sh" validate --repo "$REPO" >/dev/null
  run cm
  [ "$status" -eq 0 ]
  [[ "$output" == *"every role's model is available"* ]] || false
}

@test "an unsupported effort keeps the model and takes its default effort" {
  cm --apply >/dev/null || true
  cfg_set '.models.codex.reviewer.effort = "low"'
  run cm --apply
  [[ "$output" == *"reviewer: 'gpt-9-terra' does not support effort 'low' -> gpt-9-terra (effort medium, strong tier)"* ]] || false
}

@test "without a catalog it says why" {
  run "$ROOT/bin/codex-models.sh" check --repo "$REPO" --catalog /nonexistent
  [ "$status" -eq 1 ]
}
