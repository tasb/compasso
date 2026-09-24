#!/usr/bin/env bats
load helper

# a repo with a function, its test, and a clean tree
setup() {
  setup_repo
  cd "$REPO" && git init -q -b main && git config user.email t@t && git config user.name t
  mkdir -p src tests
  printf 'export const adult = (age) => age >= 18;\nexport const label = (age) => (adult(age) ? "adult" : "minor");\n' > src/age.js
  printf 'import { adult } from "../src/age.js";\nif (adult(18) !== true || adult(17) !== false) process.exit(1);\n' > tests/age.test.mjs
  printf '.compasso/runs/\n' > .gitignore
  git add . && git commit -qm base
  M="$BATS_TEST_TMPDIR/mutants"; mkdir -p "$M"
}
mutant() { # id sed-expr file [behaviour]
  sed -i '' "$2" "$3"; p="$(git diff -- "$3")"; git checkout -q -- "$3"
  jq -n --arg id "$1" --arg f "$3" --arg p "$p" --arg b "${4:-Adults are 18 or older}" \
    '{id: $id, file: $f, behaviour: $b, description: "d", patch: $p}' > "$M/$1.json"
}
run_mutants() { "$ROOT/bin/mutate.sh" run --repo "$REPO" --mutants "$M" --test "node tests/age.test.mjs" --timeout "${1:-20}" --out "$BATS_TEST_TMPDIR/results.json"; }
status_of() { jq -r --arg i "$1" '.[] | select(.id == $i) | .status' "$BATS_TEST_TMPDIR/results.json"; }

@test "run: a mutant the tests catch is killed, one they miss survives, and the tree is restored" {
  mutant boundary 's/age >= 18/age > 18/' src/age.js
  mutant label 's/"adult" : "minor"/"minor" : "adult"/' src/age.js "The label says adult or minor"
  run run_mutants
  [ "$status" -eq 0 ]
  [ "$(status_of boundary)" = killed ]
  [ "$(status_of label)" = survived ]
  [ -z "$(git status --porcelain --untracked-files=no)" ]
  [[ "$output" == *"2 mutants - 1 killed, 1 survived, 0 not applicable"* ]] || false
}

@test "run: a patch that does not apply, or changes nothing, is not a mutant" {
  jq -n '{id: "stale", file: "src/age.js", patch: "--- a/src/age.js\n+++ b/src/age.js\n@@ -1 +1 @@\n-nothing like this\n+x\n"}' > "$M/stale.json"
  jq -n '{id: "empty", file: "src/age.js", patch: ""}' > "$M/empty.json"
  line="$(head -1 src/age.js)"
  jq -n --arg l "$line" '{id: "same", file: "src/age.js", patch: ("--- a/src/age.js\n+++ b/src/age.js\n@@ -1 +1 @@\n-" + $l + "\n+" + $l + "\n")}' > "$M/same.json"
  run run_mutants
  [ "$status" -eq 0 ]
  [ "$(status_of stale)" = not-applicable ]
  [ "$(status_of empty)" = not-applicable ]
  [ "$(status_of same)" = not-applicable ]
}

@test "run: a mutant that hangs the tests times out, counts as caught, and leaves nothing running" {
  mutant hang 's/age >= 18/(() => { while (true) {} })()/' src/age.js
  run run_mutants 2
  [ "$status" -eq 0 ]
  [ "$(status_of hang)" = timeout ]
  [[ "$output" == *"1 killed"* ]] || false
  sleep 1
  ! pgrep -f "tests/age.test.mjs" >/dev/null
}

@test "run: refused on a tree with uncommitted changes" {
  mutant boundary 's/age >= 18/age > 18/' src/age.js
  echo "// wip" >> src/age.js
  run run_mutants
  [ "$status" -eq 2 ]
  [[ "$output" == *"uncommitted changes"* ]] || false
}

@test "scope: the diff of the merge commits, without test files" {
  git checkout -q -b story/1
  printf 'export const senior = (age) => age >= 65;\n' >> src/age.js
  echo 'console.log(1)' >> tests/age.test.mjs
  git commit -qam story
  git checkout -q main && git merge -q --no-ff story/1 -m "Merge branch 'story/1'"
  run "$ROOT/bin/mutate.sh" scope --repo "$REPO" --commits "$(git rev-parse HEAD)" --out "$BATS_TEST_TMPDIR/scope.patch"
  [ "$status" -eq 0 ]
  grep -q '^+export const senior' "$BATS_TEST_TMPDIR/scope.patch"
  [ "$(grep -c 'tests/age.test.mjs' "$BATS_TEST_TMPDIR/scope.patch")" -eq 0 ]
  [[ "$output" == *"1 changed lines in 1 files"* ]] || false
}

@test "scope: an unknown commit is refused" {
  run "$ROOT/bin/mutate.sh" scope --repo "$REPO" --commits "deadbeef" --out "$BATS_TEST_TMPDIR/scope.patch"
  [ "$status" -eq 2 ]
}

@test "report: counts, and one line per gap with its story" {
  jq -n '[{id: "a", behaviour: "Adults are 18 or older", description: "boundary", status: "killed"},
          {id: "b", behaviour: "The label says adult or minor", description: "swap labels", status: "survived"},
          {id: "c", behaviour: "x", description: "y", status: "survived"},
          {id: "d", behaviour: "x", description: "y", status: "not-applicable"}]' > "$BATS_TEST_TMPDIR/r.json"
  echo '[{"id":"b","verdict":"gap","story":31},{"id":"c","verdict":"equivalent"}]' > "$BATS_TEST_TMPDIR/v.json"
  run "$ROOT/bin/mutate.sh" report --results "$BATS_TEST_TMPDIR/r.json" --verdicts "$BATS_TEST_TMPDIR/v.json" --feature 6
  [ "$status" -eq 0 ]
  cat > "$BATS_TEST_TMPDIR/want" <<'EOF2'
**Hardening** · mutation testing · 3 mutants

- Caught by the tests: 1 · Gaps: 1 · No observable effect: 1 · Not applicable: 1
- Gap: The label says adult or minor — swap labels → #31

<!-- compasso:harden feature=6 -->
EOF2
  diff "$BATS_TEST_TMPDIR/want" <(printf '%s\n' "$output")
}

@test "report: every survivor needs the tester's verdict" {
  jq -n '[{id: "b", behaviour: "x", description: "y", status: "survived"}]' > "$BATS_TEST_TMPDIR/r.json"
  echo '[]' > "$BATS_TEST_TMPDIR/v.json"
  run "$ROOT/bin/mutate.sh" report --results "$BATS_TEST_TMPDIR/r.json" --verdicts "$BATS_TEST_TMPDIR/v.json"
  [ "$status" -eq 2 ]
  [[ "$output" == *"no verdict for survivor(s): b"* ]] || false
}

# ---------- tracker ----------

gl_setup() {
  export FAKE_GL="$BATS_TEST_TMPDIR/gl"; mkdir -p "$FAKE_GL/issues" "$FAKE_GL/parent" "$FAKE_GL/closed_by"; : > "$FAKE_GL/calls.log"
  export PATH="$ROOT/tests/fake:$PATH"
}

@test "merge-commit: the merged merge request's commit, squash first" {
  gl_setup
  echo '[{"state":"closed","merge_commit_sha":"old"},{"state":"merged","merge_commit_sha":"abc","squash_commit_sha":null}]' > "$FAKE_GL/closed_by/8.json"
  run "$ROOT/bin/tracker/gitlab.sh" merge-commit --repo "$REPO" --iid 8
  [ "$output" = abc ]
  echo '[{"state":"merged","merge_commit_sha":"abc","squash_commit_sha":"sq1"}]' > "$FAKE_GL/closed_by/8.json"
  run "$ROOT/bin/tracker/gitlab.sh" merge-commit --repo "$REPO" --iid 8
  [ "$output" = sq1 ]
  echo '[]' > "$FAKE_GL/closed_by/8.json"
  run "$ROOT/bin/tracker/gitlab.sh" merge-commit --repo "$REPO" --iid 8
  [ "$status" -eq 1 ]
}

@test "followup --milestone none files the story in the backlog" {
  gl_setup
  echo '{"iid":6,"id":1006,"milestone":{"id":501}}' > "$FAKE_GL/issues/6.json"
  echo "**As** a dev" > "$BATS_TEST_TMPDIR/s.md"
  "$ROOT/bin/tracker/gitlab.sh" followup --repo "$REPO" --parent 6 --title "Strengthen tests" --body-file "$BATS_TEST_TMPDIR/s.md" --labels owner::agent --milestone none >/dev/null
  grep -q "POST projects/acme%2Fapp/issues title=Strengthen tests issue_type=task labels=owner::agent" "$FAKE_GL/calls.log"
  [ "$(grep -c 'milestone_id' "$FAKE_GL/calls.log")" -eq 0 ]
}
