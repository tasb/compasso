#!/usr/bin/env bats
load helper

# bin/status.sh: what bin/run.sh sees, read-only. The snapshot fixtures (tests/snapshot.bats): stories #10
# and #11 are ana's (#11 depends on #10); #12 is rui's, waiting for a person on #20; bug #13 has merge
# request !7 with a green pipeline; !8 is sent back for rework; !9 is a draft; main's last pipeline failed.
F="$BATS_TEST_DIRNAME/fixtures/snapshot"

setup() {
  setup_repo
  cfg_set '.stage = "mvp" | .team.enabled = true | .team.developers = ["ana", "rui"]'
  setup_glab_stub
  echo '{"default_branch":"main"}' | fixture api --hostname gitlab.com projects/acme%2Fapp
  fixture api --hostname gitlab.com --paginate 'projects/acme%2Fapp/issues?state=opened&per_page=100' < "$F/gl-issues.json"
  fixture api --hostname gitlab.com --paginate 'projects/acme%2Fapp/merge_requests?state=opened&per_page=100' < "$F/gl-mrs.json"
  fixture api --hostname gitlab.com 'projects/acme%2Fapp/pipelines?per_page=100' < "$F/gl-pipelines.json"
  "$ROOT/bin/persona.sh" set --repo "$REPO" --persona tech-lead >/dev/null
}
st() { "$ROOT/bin/status.sh" --repo "$REPO" "$@"; }

@test "the stage, main, what waits for a person, the merge requests and each developer's work" {
  run st
  [ "$status" -eq 0 ]
  [[ "$output" == *"Stage: mvp"* ]] || false
  [[ "$output" == *"Main: failed"* ]] || false
  [[ "$output" == *"#20 "*"(holds #12)"* ]] || false
  [[ "$output" == *"!7 #13 green, waits for review"* ]] || false
  [[ "$output" == *"!8 "*"sent back for rework"* ]] || false
  [[ "$output" == *"!9 "*"draft"* ]] || false
  [[ "$output" == *"rui: "*"#12 waits for a person"* ]] || false
  [[ "$output" == *"#11 blocked by #10"* ]] || false
}

@test "the job bin/run.sh would start next, for the tech lead and each developer" {
  run st --json
  [ "$status" -eq 0 ]
  [ "$(jq -r '.next.lead.job' <<<"$output")" = red-main ]
  [ "$(jq -c '.next | keys' <<<"$output")" = '["ana","lead","rui"]' ]
  [ "$(jq -r '.next.rui' <<<"$output")" = null ]
  run st
  [[ "$output" == *"  lead: red-main"* ]] || false
  [[ "$output" == *"  rui: nothing"* ]] || false
}

@test "status changes nothing: only reads reach the tracker, and no runner file is written" {
  st >/dev/null
  ! grep -qE -- '-X (POST|PUT|DELETE)' "$GLAB_STUB_DIR/calls.log" || false
  [ ! -e "$REPO/.compasso/runs/runner" ]
}

@test "this machine's last runs, and the jobs skipped until a person answers" {
  d="$REPO/.compasso/runs/runner"; mkdir -p "$d"
  for i in 1 2 3 4 5 6; do echo "{\"at\":\"2026-11-1${i}T10:00:00Z\",\"role\":\"dev\",\"name\":\"ana\",\"job\":\"build\",\"key\":\"build:1$i\",\"result\":\"done\",\"seconds\":$i}" >> "$d/events.jsonl"; done
  echo '{"build:11": 2, "review:7": 1}' > "$d/failures.json"
  run st
  [[ "$output" == *"Skipped until a person answers: build:11"* ]] || false
  [[ "$output" != *"review:7"* ]] || false
  [[ "$output" == *"2026-11-16T10:00:00Z dev ana build build:16 done 6s"* ]] || false
  [[ "$output" != *"build:11 done"* ]] || false
}

@test "when the tracker cannot be read, this machine's runs are still shown and it exits 1" {
  rm "$GLAB_STUB_DIR"/*issues_state_opened*
  [ -z "$(ls "$GLAB_STUB_DIR" | grep issues_state_opened)" ]
  d="$REPO/.compasso/runs/runner"; mkdir -p "$d"
  echo '{"at":"2026-11-16T10:00:00Z","role":"lead","name":null,"job":null,"key":null,"result":"idle","seconds":1}' > "$d/events.jsonl"
  run st
  [ "$status" -eq 1 ]
  [[ "$output" == *"Tracker: "* ]] || false
  [[ "$output" == *"lead idle"*"idle 1s"* ]] || false
}

@test "status warns when these scripts are older than the newest Compasso installed" {
  d="$BATS_TEST_TMPDIR/cache/tasb/compasso/99.0.0/.claude-plugin"; mkdir -p "$d"; echo '{"version":"99.0.0"}' > "$d/plugin.json"
  COMPASSO_PLUGIN_CACHE="$BATS_TEST_TMPDIR/cache" run st
  [[ "$output" == *"but 99.0.0 is installed"* ]] || false
}
