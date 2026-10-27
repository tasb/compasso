#!/usr/bin/env bats
load helper

setup() { REPO="$BATS_TEST_TMPDIR/repo"; mkdir -p "$REPO"; export COMPASSO_HOME="$BATS_TEST_TMPDIR/home"; }
stage() { "$ROOT/bin/start.sh" --repo "$REPO" --json | jq -r "$1"; }

@test "the stages follow what exists: setup, discover, backlog, architect, roadmap, plan, build" {
  [ "$(stage .stage)" = setup ]
  "$ROOT/bin/config.sh" init --repo "$REPO" --project acme/app >/dev/null
  [ "$(stage .next)" = /compasso:discover ]
  mkdir -p "$REPO/.compasso/product" && echo "# Shop" > "$REPO/.compasso/product/brief.md"
  [ "$(stage .next)" = /compasso:backlog ]
  cp "$ROOT/tests/fixtures/backlog.yaml" "$REPO/.compasso/backlog.yaml"
  [ "$(stage .next)" = /compasso:architect ]
  cp "$ROOT/tests/fixtures/architecture.yaml" "$REPO/.compasso/product/architecture.yaml"
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
  [ "$(stage .stage)" = architect ]
}

@test "greenfield: only docs, CI and Compasso files means no product code yet" {
  "$ROOT/bin/config.sh" init --repo "$REPO" --project acme/app >/dev/null
  mkdir -p "$REPO/docs" "$REPO/.github/workflows"; echo x > "$REPO/README.md"; echo x > "$REPO/docs/idea.md"; echo x > "$REPO/.github/workflows/ci.yml"
  [ "$(stage .greenfield)" = true ]
  [[ "$("$ROOT/bin/start.sh" --repo "$REPO")" == *"walking skeleton"* ]] || false
  mkdir -p "$REPO/src" && echo x > "$REPO/src/app.js"
  [ "$(stage .greenfield)" = false ]
}

# a plugin cache as Claude Code keeps it: <marketplace>/compasso/<version>/.claude-plugin/plugin.json
installed() { local d="$BATS_TEST_TMPDIR/cache/$1/compasso/$2/.claude-plugin"; mkdir -p "$d"; jq -n --arg v "$2" '{name: "compasso", version: $v}' > "$d/plugin.json"; }

@test "start warns when these scripts are older than the newest Compasso installed" {
  export COMPASSO_PLUGIN_CACHE="$BATS_TEST_TMPDIR/cache"
  running="$(jq -r .version "$ROOT/.claude-plugin/plugin.json")"
  installed tasb "$running"; installed tasb 1.2.1
  run "$ROOT/bin/start.sh" --repo "$REPO"
  [[ "$output" != *"is installed"* ]] || false
  installed other 99.0.0
  run "$ROOT/bin/start.sh" --repo "$REPO"
  [ "$status" -eq 0 ]
  [[ "$output" == *"version $running, but 99.0.0 is installed"* ]] || false
  # the JSON on stdout stays one document
  "$ROOT/bin/start.sh" --repo "$REPO" --json 2>/dev/null | jq -e .stage >/dev/null
  # a newer minor and patch count too, compared as numbers
  rm -rf "$BATS_TEST_TMPDIR/cache/other"; installed other "${running%%.*}.$(( $(echo "$running" | cut -d. -f2) + 10 )).0"
  run "$ROOT/bin/start.sh" --repo "$REPO"
  [[ "$output" == *"is installed"* ]] || false
}
