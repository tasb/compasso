#!/usr/bin/env bats
load helper

# bin/cron.sh prints the crontab line for this checkout; bin/compasso-run, the stable path it points at,
# starts the newest Compasso installed.
setup() {
  setup_repo
  cfg_set '.team.enabled = true | .team.developers = ["ana"] | .run.lead_minutes = 15 | .run.dev_minutes = 10'
}
cr() { "$ROOT/bin/cron.sh" --repo "$REPO"; }

@test "the tech lead's line: every run.lead_minutes, through the launcher in the Compasso home, with this PATH and a log" {
  "$ROOT/bin/persona.sh" set --repo "$REPO" --persona tech-lead >/dev/null
  run cr
  [ "$status" -eq 0 ]
  [[ "$output" == "*/15 * * * * PATH='$PATH' '$COMPASSO_HOME/bin/compasso-run' lead --repo '$REPO' >> '$REPO/.compasso/runs/runner/cron.log' 2>&1" ]] || false
  [ -x "$COMPASSO_HOME/bin/compasso-run" ]
  [ -d "$REPO/.compasso/runs/runner" ]
}

@test "a developer's line runs dev with its name, every run.dev_minutes; whole hours repeat by the hour" {
  "$ROOT/bin/persona.sh" set --repo "$REPO" --persona developer --name ana >/dev/null
  [[ "$(cr)" == "*/10 * * * * "*"compasso-run' dev --name ana --repo"* ]] || false
  cfg_set '.run.dev_minutes = 120'
  [[ "$(cr)" == "0 */2 * * * "* ]] || false
  cfg_set '.run.dev_minutes = 90'
  run cr
  [ "$status" -eq 1 ]
  [[ "$output" == *"cannot be repeated by cron"* ]] || false
}

@test "a checkout with no team persona gets no line" {
  run cr
  [ "$status" -eq 1 ]
  [[ "$output" == *"choose tech lead or developer"* ]] || false
  [ ! -e "$COMPASSO_HOME/bin/compasso-run" ]
}

@test "the launcher starts run.sh of the newest version in the plugin cache, else the Codex engine" {
  C="$BATS_TEST_TMPDIR/cache"
  for v in 3.10.0 4.0.0 3.9.9; do
    d="$C/mkt/compasso/$v"; mkdir -p "$d/.claude-plugin" "$d/bin"
    echo "{\"name\": \"compasso\", \"version\": \"$v\"}" > "$d/.claude-plugin/plugin.json"
    printf '#!/usr/bin/env bash\necho "%s $*"\n' "$v" > "$d/bin/run.sh"
  done
  [ "$(COMPASSO_PLUGIN_CACHE="$C" "$ROOT/bin/compasso-run" lead --repo /x)" = "4.0.0 lead --repo /x" ]
  mkdir -p "$COMPASSO_HOME/engine/bin"; printf '#!/usr/bin/env bash\necho "engine $*"\n' > "$COMPASSO_HOME/engine/bin/run.sh"
  [ "$(COMPASSO_PLUGIN_CACHE="$BATS_TEST_TMPDIR/none" "$ROOT/bin/compasso-run" dev --name ana)" = "engine dev --name ana" ]
  rm -rf "$COMPASSO_HOME/engine"
  run env COMPASSO_PLUGIN_CACHE="$BATS_TEST_TMPDIR/none" "$ROOT/bin/compasso-run" lead
  [ "$status" -eq 1 ]
  [[ "$output" == *"no Compasso installed"* ]] || false
}
