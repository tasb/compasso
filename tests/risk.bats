#!/usr/bin/env bats
load helper

setup() {
  setup_repo
  cd "$REPO" && git init -q -b main && git config user.email t@t && git config user.name t
  mkdir -p src/auth src/billing && echo a > src/billing/a.js && echo b > src/auth/b.js
  printf '.compasso/runs/\n' > .gitignore && git add . && git commit -qm base
  RUN="$REPO/.compasso/runs/8"; mkdir -p "$RUN"
  echo '[]' > "$RUN/findings.json"
  echo '{"status":"ok","percent":100,"min":80}' > "$RUN/coverage.json"
}
risk() { "$ROOT/bin/risk.sh" --repo "$REPO" --run "$RUN" --base main; }
reasons() { jq -r '.reasons | join(" | ")' "$RUN/risk.json"; }

@test "a small, covered change with no sensitive paths and a clean security review is low risk" {
  echo more >> src/billing/a.js
  run risk
  [ "$status" -eq 0 ]
  [ "$(jq -c '[.level, .changed_lines, .files]' "$RUN/risk.json")" = '["low",1,1]' ]
}

@test "a sensitive path is high risk" {
  cfg_set '.risk.sensitive_paths = ["src/auth/**"]'; git commit -qam config
  echo more >> src/auth/b.js
  run risk
  [ "$status" -eq 3 ]
  [[ "$(reasons)" == *"src/auth/b.js is a sensitive path (src/auth/**)"* ]] || false
}

@test "a change over the line limit is high risk" {
  cfg_set '.risk.max_changed_lines = 3'; git commit -qam config
  printf '1\n2\n3\n4\n' >> src/billing/a.js
  run risk
  [ "$status" -eq 3 ]
  [[ "$(reasons)" == *"4 changed lines, over the 3-line limit"* ]] || false
}

@test "changing dependencies, the pipeline or the Compasso config is high risk" {
  echo '{}' > package.json && git add package.json
  run risk
  [ "$status" -eq 3 ]
  [[ "$(reasons)" == *"package.json changes the build, the pipeline, the Compasso config or dependencies"* ]] || false
}

@test "a blocker or major security finding makes the story high risk, even once fixed" {
  echo more >> src/billing/a.js
  echo '[{"by":"security","severity":"major","status":"fixed","verified_by":"security","summary":"x"}]' > "$RUN/findings.json"
  run risk
  [ "$status" -eq 3 ]
  [[ "$(reasons)" == *"security found 1 blocker or major issue(s)"* ]] || false
  echo '[{"by":"security","severity":"minor","status":"fixed","verified_by":"security","summary":"x"}]' > "$RUN/findings.json"
  run risk
  [ "$status" -eq 0 ]
}

@test "coverage below its minimum, or not measured, is high risk" {
  echo more >> src/billing/a.js
  echo '{"status":"below","percent":50,"min":80}' > "$RUN/coverage.json"
  run risk
  [ "$status" -eq 3 ]
  rm "$RUN/coverage.json"
  run risk
  [[ "$(reasons)" == *"coverage was not measured"* ]] || false
}

@test "the run folder itself never counts as a change" {
  echo noise > "$RUN/notes.txt"
  git add -f "$RUN/notes.txt"
  echo more >> src/billing/a.js
  run risk
  [ "$(jq .files "$RUN/risk.json")" = 1 ]
}

# ---------- merge and digest ----------

gl_setup() {
  export FAKE_GL="$BATS_TEST_TMPDIR/gl"; mkdir -p "$FAKE_GL/issues"; : > "$FAKE_GL/calls.log"
  export PATH="$ROOT/tests/fake:$PATH"
  echo '[]' > "$BATS_TEST_TMPDIR/findings.json"
}
merge() { "$ROOT/bin/tracker/gitlab.sh" merge --repo "$REPO" --mr 31 --body-file "$BATS_TEST_TMPDIR/findings.json" "$@"; }

@test "risk mode merges a low-risk change, labelled for the digest" {
  gl_setup; cfg_set '.approvals.merge = "risk"'
  echo '{"level":"low","reasons":[]}' > "$BATS_TEST_TMPDIR/risk.json"
  run merge --risk "$BATS_TEST_TMPDIR/risk.json"
  [ "$status" -eq 0 ]
  grep -q "PUT projects/acme%2Fapp/merge_requests/31 add_labels=compasso::auto-merged" "$FAKE_GL/calls.log"
  grep -q "PUT projects/acme%2Fapp/merge_requests/31/merge" "$FAKE_GL/calls.log"
}

@test "risk mode leaves a high-risk change, or one with no decision, to a person" {
  gl_setup; cfg_set '.approvals.merge = "risk"'
  echo '{"level":"high","reasons":["x"]}' > "$BATS_TEST_TMPDIR/risk.json"
  run merge --risk "$BATS_TEST_TMPDIR/risk.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"high risk - a person merges it"* ]] || false
  run merge
  [ "$status" -eq 1 ]
  [[ "$output" == *"merge needs --risk"* ]] || false
  [ "$(grep -c '/merge' "$FAKE_GL/calls.log" || true)" -eq 0 ]
}

@test "risk mode still never merges with an open security finding" {
  gl_setup; cfg_set '.approvals.merge = "risk"'
  echo '{"level":"low","reasons":[]}' > "$BATS_TEST_TMPDIR/risk.json"
  echo '[{"by":"security","severity":"minor","status":"open","summary":"x"}]' > "$BATS_TEST_TMPDIR/findings.json"
  run merge --risk "$BATS_TEST_TMPDIR/risk.json"
  [ "$status" -eq 1 ]
}

@test "digest lists what merged without a person since a date" {
  gl_setup
  echo '[{"iid":12,"title":"Year filter","merged_at":"2026-09-25T10:15:00.000Z"},{"iid":9,"title":"List API","merged_at":"2026-09-24T18:00:00Z"}]' > "$FAKE_GL/mr-query.json"
  run "$ROOT/bin/tracker/gitlab.sh" digest --repo "$REPO" --since 2026-09-24
  [ "$status" -eq 0 ]
  [[ "$output" == *"**Merged without a person** · since 2026-09-24"* ]] || false
  [ "$(printf '%s\n' "$output" | grep '^- ' | head -1)" = "- !9 List API · merged 2026-09-24 18:00" ]
  grep -q "merge_requests?state=merged&labels=compasso::auto-merged&updated_after=2026-09-24T00:00:00Z" "$FAKE_GL/calls.log"
}

@test "the merge request says whether it may merge without a person, and why not" {
  jq -n '{iid: 8, story: {key: "S-1", verify: ["npm test"]}}' > "$BATS_TEST_TMPDIR/story.json"
  echo "- A change" > "$RUN/changes.md"
  echo '{"level":"high","changed_lines":40,"files":2,"reasons":["src/auth/b.js is a sensitive path (src/auth/**)"]}' > "$RUN/risk.json"
  run "$ROOT/bin/mr-body.sh" --story "$BATS_TEST_TMPDIR/story.json" --run "$RUN"
  [[ "$output" == *"- Merge: a person approves: src/auth/b.js is a sensitive path (src/auth/**)"* ]] || false
  echo '{"level":"low","changed_lines":12,"files":1,"reasons":[]}' > "$RUN/risk.json"
  run "$ROOT/bin/mr-body.sh" --story "$BATS_TEST_TMPDIR/story.json" --run "$RUN"
  [[ "$output" == *"- Merge: low risk, may merge without a person (12 changed lines in 1 files, nothing sensitive)"* ]] || false
}
