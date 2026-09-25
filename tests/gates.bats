#!/usr/bin/env bats
load helper

# a git repo with a Compasso config and one base commit on main
setup() {
  setup_repo
  RUN="$BATS_TEST_TMPDIR/run"
  cd "$REPO"
  git init -q -b main && git config user.email t@t && git config user.name t
  printf '.compasso/\ncov.xml\n' > .gitignore
  mkdir -p src tests
  printf 'def a():\n    return 1\n' > src/a.py
  echo "test a" > tests/test_a.py
  git add . && git commit -qm base
}
story() { # tests verify-command... (approved, as a person would after reading them)
  local tests="$1"; shift
  jq -n --argjson t "$tests" '{story: {tests: $t, verify: $ARGS.positional}}' --args "$@" > "$BATS_TEST_TMPDIR/story.json"
  "$ROOT/bin/trust.sh" approve --repo "$REPO" --story "$BATS_TEST_TMPDIR/story.json" >/dev/null
}
findings() { echo "$1" > "$BATS_TEST_TMPDIR/f.json"; "$ROOT/bin/review-gate.sh" --findings "$BATS_TEST_TMPDIR/f.json" "${@:2}"; }

# ---------- review-gate ----------

@test "review-gate: open blocker or major findings block the review; minors do not" {
  run findings '[{"by":"reviewer","severity":"minor","status":"open","summary":"naming"}]'
  [ "$status" -eq 0 ]
  run findings '[{"by":"reviewer","severity":"major","status":"open","summary":"off by one","file":"src/a.py","line":2}]'
  [ "$status" -eq 1 ]
  [[ "$output" == *"[reviewer/major] off by one (src/a.py:2)"* ]] || false
}

@test "review-gate: fixed findings no longer block" {
  run findings '[{"by":"reviewer","severity":"blocker","status":"fixed","summary":"crash"}]'
  [ "$status" -eq 0 ]
}

@test "review-gate: only security can resolve a security finding" {
  run findings '[{"by":"security","severity":"major","status":"fixed","summary":"sql injection"}]'
  [ "$status" -eq 1 ]
  run findings '[{"by":"security","severity":"major","status":"fixed","verified_by":"security","summary":"sql injection"}]'
  [ "$status" -eq 0 ]
}

@test "review-gate: a merge is blocked by any open security finding, even a minor one" {
  run findings '[{"by":"security","severity":"minor","status":"open","summary":"verbose error"}]' --for review
  [ "$status" -eq 0 ]
  run findings '[{"by":"security","severity":"minor","status":"open","summary":"verbose error"}]' --for merge
  [ "$status" -eq 1 ]
  run findings '[{"by":"reviewer","severity":"minor","status":"open","summary":"naming"}]' --for merge
  [ "$status" -eq 0 ]
}

@test "review-gate: malformed findings exit 2" {
  run findings '[{"by":"someone","severity":"major","status":"open","summary":"x"}]'
  [ "$status" -eq 2 ]
  run findings '[{"by":"reviewer","severity":"major","status":"open"}]'
  [ "$status" -eq 2 ]
  run findings 'not json'
  [ "$status" -eq 2 ]
}

# ---------- test-hashes ----------

@test "test-hashes: unchanged tests pass" {
  "$ROOT/bin/test-hashes.sh" record --repo . --run "$RUN" >/dev/null
  echo "change" >> src/a.py
  run "$ROOT/bin/test-hashes.sh" verify --repo . --run "$RUN"
  [ "$status" -eq 0 ]
}

@test "test-hashes: a changed, removed or added test file is a violation, each named" {
  echo "old" > src/b.test.js
  "$ROOT/bin/test-hashes.sh" record --repo . --run "$RUN" >/dev/null
  echo "weakened" >> tests/test_a.py
  rm src/b.test.js
  echo "new" > tests/test_new.py
  run "$ROOT/bin/test-hashes.sh" verify --repo . --run "$RUN"
  [ "$status" -eq 1 ]
  [[ "$output" == *"- tests/test_a.py"* ]] || false
  [[ "$output" == *"- src/b.test.js"* ]] || false
  [[ "$output" == *"- tests/test_new.py"* ]] || false
}

@test "test-hashes: a root-level test file matches **/ patterns" {
  echo "t" > root.spec.ts
  run "$ROOT/bin/test-hashes.sh" record --repo . --run "$RUN"
  [[ "$output" == *"recorded 2 test files"* ]] || false
}

@test "test-hashes: patterns are not expanded against the working directory" {
  cfg_set '.test_paths = ["tests/**"]'
  mkdir -p "$BATS_TEST_TMPDIR/elsewhere/tests" && cd "$BATS_TEST_TMPDIR/elsewhere"
  touch tests/decoy
  run "$ROOT/bin/test-hashes.sh" record --repo "$REPO" --run "$RUN"
  [[ "$output" == *"recorded 1 test files"* ]] || false
}

@test "test-hashes: verify without a record exits 2" {
  run "$ROOT/bin/test-hashes.sh" verify --repo . --run "$RUN"
  [ "$status" -eq 2 ]
}

# ---------- verify ----------

@test "verify: runs the repo's commands, then the story's, and passes when all pass" {
  cfg_set '.commands.test = "echo testing" | .commands.lint = "true"'
  story '["unit"]' 'echo story-check'
  run "$ROOT/bin/verify.sh" --repo . --run "$RUN" --story "$BATS_TEST_TMPDIR/story.json"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c '^PASS')" -eq 3 ]
  [ "$(jq -r 'map(.label) | join(",")' "$RUN/verify.json")" = "test,lint,story" ]
}

@test "verify: a failing command fails the gate and shows its output" {
  cfg_set '.commands.test = "printf \"detail-%s\\\\n\" xyz; exit 1"'
  run "$ROOT/bin/verify.sh" --repo . --run "$RUN"
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL  [test]"* ]] || false
  [[ "$output" == *"      detail-xyz"* ]] || false
  [[ "$output" == *"1 of 1 commands failed"* ]] || false
}

@test "verify: commands run from the repo root" {
  cfg_set '.commands.test = "test -f src/a.py"'
  cd /
  run "$ROOT/bin/verify.sh" --repo "$REPO" --run "$RUN"
  [ "$status" -eq 0 ]
}

@test "verify: e2e runs only when the story asks for it" {
  cfg_set '.commands.test = "true" | .commands.e2e = "echo e2e-ran"'
  story '["unit"]'
  run "$ROOT/bin/verify.sh" --repo . --run "$RUN" --story "$BATS_TEST_TMPDIR/story.json"
  [[ "$output" != *"[e2e]"* ]] || false
  story '["unit","e2e"]'
  run "$ROOT/bin/verify.sh" --repo . --run "$RUN" --story "$BATS_TEST_TMPDIR/story.json"
  [[ "$output" == *"PASS  [e2e] echo e2e-ran"* ]] || false
}

@test "verify: a story that needs e2e fails without an e2e command" {
  cfg_set '.commands.test = "true"'
  story '["unit","e2e"]'
  run "$ROOT/bin/verify.sh" --repo . --run "$RUN" --story "$BATS_TEST_TMPDIR/story.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"commands.e2e is empty"* ]] || false
}

@test "verify: nothing to run is a failure, not a pass" {
  run "$ROOT/bin/verify.sh" --repo . --run "$RUN"
  [ "$status" -eq 1 ]
  [[ "$output" == *"nothing to run"* ]] || false
}

# ---------- coverage ----------

cobertura() { # file:hits-per-line... -> cov.xml
  local classes="" f spec lines n h
  for spec in "$@"; do
    f="${spec%%=*}"; lines=""
    for n in ${spec#*=}; do h="${n#*:}"; lines="$lines<line number=\"${n%%:*}\" hits=\"$h\"/>"; done
    classes="$classes<class name=\"$(basename "$f")\" filename=\"$f\" line-rate=\"1\"><lines>$lines</lines></class>"
  done
  printf '<?xml version="1.0" ?><coverage version="7" line-rate="1"><sources><source>.</source></sources><packages><package name="p"><classes>%s</classes></package></packages></coverage>\n' "$classes" > cov.xml
}
change_a() { printf 'def a():\n    return 1\n\ndef b(x):\n    if x:\n        return 2\n    return 3\n' > src/a.py; }
cov() { "$ROOT/bin/coverage.sh" --repo . --base main --run "$RUN" "$@"; }

@test "coverage: without a command it is not measured - a warning, never a pass" {
  run cov
  [ "$status" -eq 3 ]
  [[ "$output" == *"not measured - no coverage.command"* ]] || false
  [ "$(jq -r .status "$RUN/coverage.json")" = not-measured ]
}

@test "coverage: at or above the threshold passes with the percentage" {
  change_a
  cobertura "src/a.py=1:1 2:1 4:1 5:1 6:1 7:1"
  cfg_set '.coverage.command = "true" | .coverage.report = "cov.xml"'
  run cov
  [ "$status" -eq 0 ]
  [[ "$output" == *"coverage: 100% of changed lines (min 80%)"* ]] || false
}

@test "coverage: below the threshold warns with exit 3 and lists the uncovered lines" {
  change_a
  cobertura "src/a.py=1:1 2:1 4:1 5:1 6:0 7:0"
  cfg_set '.coverage.command = "true" | .coverage.report = "cov.xml"'
  run cov
  [ "$status" -eq 3 ]
  [[ "$output" == *"below min - 50% of 80%"* ]] || false
  [[ "$output" == *"- src/a.py:6"* ]] || false
  [ "$(jq -r '.uncovered | join(" ")' "$RUN/coverage.json")" = "src/a.py:6 src/a.py:7" ]
}

@test "coverage: --min overrides the project default" {
  change_a
  cobertura "src/a.py=1:1 2:1 4:1 5:1 6:0 7:0"
  cfg_set '.coverage.command = "true" | .coverage.report = "cov.xml"'
  run cov --min 50
  [ "$status" -eq 0 ]
}

@test "coverage: a changed product file missing from the report counts as uncovered" {
  change_a
  printf 'X = 1\nY = 2\n' > src/new.py
  echo "notes" > README.md
  cobertura "src/a.py=1:1 2:1 4:1 5:1 6:1 7:1"
  cfg_set '.coverage.command = "true" | .coverage.report = "cov.xml" | .coverage.paths = ["src/**"]'
  run cov
  [ "$status" -eq 3 ]
  [[ "$output" == *"66% of 80%"* ]] || false
  [[ "$output" == *"- src/new.py:2"* ]] || false
  [[ "$output" != *"README.md"* ]] || false
}

@test "coverage: a failing coverage command is not measured" {
  change_a
  cfg_set '.coverage.command = "exit 1" | .coverage.report = "cov.xml"'
  run cov
  [ "$status" -eq 3 ]
  [[ "$output" == *"coverage.command failed"* ]] || false
}

@test "coverage: a command that writes no report is not measured" {
  change_a
  cfg_set '.coverage.command = "true" | .coverage.report = "missing.xml"'
  run cov
  [ "$status" -eq 3 ]
  [[ "$output" == *"did not write missing.xml"* ]] || false
}

@test "coverage: an unresolvable base is not measured" {
  run "$ROOT/bin/coverage.sh" --repo . --base no-such-ref --run "$RUN"
  [ "$status" -eq 3 ]
  [[ "$output" == *"does not resolve"* ]] || false
}

@test "coverage: no changed lines passes" {
  cobertura "src/a.py=1:1 2:1"
  cfg_set '.coverage.command = "true" | .coverage.report = "cov.xml"'
  run cov
  [ "$status" -eq 0 ]
  [[ "$output" == *"no changed lines"* ]] || false
}

@test "verify: an unapproved Verify command stops the gate before anything runs" {
  cfg_set '.commands.test = "touch ran-test"'
  jq -n '{story: {tests: ["unit"], verify: ["touch ran-verify"]}}' > "$BATS_TEST_TMPDIR/story.json"
  run "$ROOT/bin/verify.sh" --repo . --run "$RUN" --story "$BATS_TEST_TMPDIR/story.json"
  [ "$status" -eq 4 ]
  [[ "$output" == *"not approved to run on this machine"* ]] || false
  [[ "$output" == *"touch ran-verify"* ]] || false
  [ ! -e ran-test ] && [ ! -e ran-verify ]
}

@test "verify: an approved command edited on the tracker needs approving again" {
  cfg_set '.commands.test = "true"'
  story '["unit"]' "true"
  "$ROOT/bin/verify.sh" --repo . --run "$RUN" --story "$BATS_TEST_TMPDIR/story.json" >/dev/null
  jq '.story.verify = ["true; touch pwned"]' "$BATS_TEST_TMPDIR/story.json" > "$BATS_TEST_TMPDIR/s2.json"
  run "$ROOT/bin/verify.sh" --repo . --run "$RUN" --story "$BATS_TEST_TMPDIR/s2.json"
  [ "$status" -eq 4 ]
  [ ! -e pwned ]
}
