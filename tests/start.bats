#!/usr/bin/env bats
load helper

setup() { REPO="$BATS_TEST_TMPDIR/repo"; mkdir -p "$REPO"; export COMPASSO_HOME="$BATS_TEST_TMPDIR/home"; }
stage() { "$ROOT/bin/start.sh" --repo "$REPO" --json | jq -r "$1"; }

@test "the stages follow what exists: setup, discover, backlog, roadmap, plan, build" {
  [ "$(stage .stage)" = setup ]
  "$ROOT/bin/config.sh" init --repo "$REPO" --project acme/app >/dev/null
  [ "$(stage .next)" = /compasso:discover ]
  mkdir -p "$REPO/.compasso/product" && echo "# Shop" > "$REPO/.compasso/product/brief.md"
  [ "$(stage .next)" = /compasso:backlog ]
  cp "$ROOT/tests/fixtures/backlog.yaml" "$REPO/.compasso/backlog.yaml"
  [ "$(stage .next)" = /compasso:roadmap ]
  "$ROOT/bin/roadmap.sh" propose --repo "$REPO" --write >/dev/null
  [ "$(stage .next)" = /compasso:plan ]
  [[ "$(stage .why)" == "sprint S1 is next"* ]] || false
  cp "$ROOT/tests/fixtures/plan.yaml" "$REPO/.compasso/plan.yaml"
  [ "$(stage .stage)" = build ]
}

@test "a backlog without a brief (from a requirements document) is past discovery" {
  "$ROOT/bin/config.sh" init --repo "$REPO" --project acme/app >/dev/null
  cp "$ROOT/tests/fixtures/backlog.yaml" "$REPO/.compasso/backlog.yaml"
  [ "$(stage .stage)" = roadmap ]
}

@test "greenfield: only docs, CI and Compasso files means no product code yet" {
  "$ROOT/bin/config.sh" init --repo "$REPO" --project acme/app >/dev/null
  mkdir -p "$REPO/docs" "$REPO/.github/workflows"; echo x > "$REPO/README.md"; echo x > "$REPO/docs/idea.md"; echo x > "$REPO/.github/workflows/ci.yml"
  [ "$(stage .greenfield)" = true ]
  [[ "$("$ROOT/bin/start.sh" --repo "$REPO")" == *"walking skeleton"* ]] || false
  mkdir -p "$REPO/src" && echo x > "$REPO/src/app.js"
  [ "$(stage .greenfield)" = false ]
}
