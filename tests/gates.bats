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
# ---------- verify ----------

@test "verify: runs the repo's commands, then the story's, and passes when all pass" {
  cfg_set '.commands.test = "echo testing" | .commands.lint = "true"'
  story '["unit"]' 'echo story-check'
  run "$ROOT/bin/verify.sh" --repo . --run "$RUN" --story "$BATS_TEST_TMPDIR/story.json"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c '^PASS')" -eq 3 ]
  [ "$(jq -r 'map(.label) | join(",")' "$RUN/verify.json")" = "test,lint,story" ]
}

@test "verify: a story Verify command the repo's commands already ran runs once" {
  cfg_set ".commands.test = \"echo ran >> $BATS_TEST_TMPDIR/count\""
  story '["unit"]' "echo ran >> $BATS_TEST_TMPDIR/count"
  run "$ROOT/bin/verify.sh" --repo . --run "$RUN" --story "$BATS_TEST_TMPDIR/story.json"
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$BATS_TEST_TMPDIR/count")" -eq 1 ]
  [[ "$output" == *"SKIP  [story] echo ran >> $BATS_TEST_TMPDIR/count - it already ran as [test]"* ]] || false
  [ "$(jq -r 'map(.label) | join(",")' "$RUN/verify.json")" = test ]
  [[ "$output" == *"all 1 commands passed"* ]] || false
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

@test "verify: e2e runs last, and only when every other command passed" {
  cfg_set ".commands.test = \"false\" | .commands.lint = \"true\" | .commands.e2e = \"touch $BATS_TEST_TMPDIR/e2e-ran\""
  story '["unit","e2e"]' 'echo story-check'
  run "$ROOT/bin/verify.sh" --repo . --run "$RUN" --story "$BATS_TEST_TMPDIR/story.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"SKIP  [e2e] touch $BATS_TEST_TMPDIR/e2e-ran - an earlier command failed"* ]] || false
  [ ! -e "$BATS_TEST_TMPDIR/e2e-ran" ]
  [ "$(jq -r 'map(.label) | join(",")' "$RUN/verify.json")" = "test,lint,story" ]
  cfg_set '.commands.test = "echo ok"'
  run "$ROOT/bin/verify.sh" --repo . --run "$RUN" --story "$BATS_TEST_TMPDIR/story.json"
  [ "$status" -eq 0 ]
  [ "$(jq -r 'map(.label) | join(",")' "$RUN/verify.json")" = "test,lint,story,e2e" ]
}

@test "verify: --e2e runs the e2e command without a story, and fails without one" {
  cfg_set '.commands.test = "true" | .commands.e2e = "echo e2e-ran"'
  run "$ROOT/bin/verify.sh" --repo . --run "$RUN" --e2e
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS  [e2e] echo e2e-ran"* ]] || false
  cfg_set 'del(.commands.e2e)'
  run "$ROOT/bin/verify.sh" --repo . --run "$RUN" --e2e
  [ "$status" -eq 1 ]
  [[ "$output" == *"commands.e2e is empty"* ]] || false
}

@test "verify: each command's time is in verify.json and in the run's events" {
  cfg_set '.commands.test = "sleep 1" | .commands.lint = "true"'
  run "$ROOT/bin/verify.sh" --repo . --run "$RUN"
  [ "$status" -eq 0 ]
  [ "$(jq -c 'map([.label, (.seconds | type)])' "$RUN/verify.json")" = '[["test","number"],["lint","number"]]' ]
  [ "$(jq '.[0].seconds >= 1' "$RUN/verify.json")" = true ]
  [ "$(jq -sc 'map(select(.type == "verify") | [.label, .status, (.seconds | type), (.at | type)])' "$RUN/events.jsonl")" = '[["test","pass","number","string"],["lint","pass","number","string"]]' ]
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

@test "coverage: skipped in stage mvp, without running the command" {
  change_a
  cfg_set ".stage = \"mvp\" | .coverage.command = \"touch $BATS_TEST_TMPDIR/cov-ran\" | .coverage.report = \"cov.xml\""
  run cov
  [ "$status" -eq 0 ]
  [[ "$output" == *"coverage: skipped in stage mvp"* ]] || false
  [ ! -e "$BATS_TEST_TMPDIR/cov-ran" ]
  [ "$(jq -c '[.status, .percent]' "$RUN/coverage.json")" = '["skipped",null]' ]
}

@test "coverage: the coverage command's time is in the run's events" {
  change_a
  cobertura "src/a.py=1:1 2:1 4:1 5:1 6:1 7:1"
  cfg_set '.coverage.command = "true" | .coverage.report = "cov.xml"'
  run cov
  [ "$status" -eq 0 ]
  [ "$(jq -sc 'map(select(.type == "verify") | [.label, (.seconds | type)])' "$RUN/events.jsonl")" = '[["coverage","number"]]' ]
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

@test "verify: with trust.verify_approval, an unapproved Verify command stops the gate before anything runs" {
  cfg_set '.commands.test = "touch ran-test" | .trust.verify_approval = true'
  jq -n '{story: {tests: ["unit"], verify: ["touch ran-verify"]}}' > "$BATS_TEST_TMPDIR/story.json"
  run "$ROOT/bin/verify.sh" --repo . --run "$RUN" --story "$BATS_TEST_TMPDIR/story.json"
  [ "$status" -eq 4 ]
  [[ "$output" == *"not approved to run on this machine"* ]] || false
  [[ "$output" == *"touch ran-verify"* ]] || false
  [ ! -e ran-test ] && [ ! -e ran-verify ]
}

@test "verify: an approved command edited on the tracker needs approving again" {
  cfg_set '.commands.test = "true" | .trust.verify_approval = true'
  story '["unit"]' "true"
  "$ROOT/bin/verify.sh" --repo . --run "$RUN" --story "$BATS_TEST_TMPDIR/story.json" >/dev/null
  jq '.story.verify = ["true; touch pwned"]' "$BATS_TEST_TMPDIR/story.json" > "$BATS_TEST_TMPDIR/s2.json"
  run "$ROOT/bin/verify.sh" --repo . --run "$RUN" --story "$BATS_TEST_TMPDIR/s2.json"
  [ "$status" -eq 4 ]
  [ ! -e pwned ]
}
