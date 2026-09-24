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

@test "result: mutation counts, and one gap per real gap with its story" {
  jq -n '[{id: "a", behaviour: "Adults are 18 or older", description: "boundary", status: "killed"},
          {id: "b", behaviour: "The label says adult or minor", description: "swap labels", status: "survived"},
          {id: "c", behaviour: "x", description: "y", status: "survived"},
          {id: "d", behaviour: "x", description: "y", status: "not-applicable"}]' > "$BATS_TEST_TMPDIR/r.json"
  echo '[{"id":"b","verdict":"gap","story":31},{"id":"c","verdict":"equivalent"}]' > "$BATS_TEST_TMPDIR/v.json"
  run "$ROOT/bin/mutate.sh" result --results "$BATS_TEST_TMPDIR/r.json" --verdicts "$BATS_TEST_TMPDIR/v.json" --out "$BATS_TEST_TMPDIR/m.json"
  [ "$status" -eq 0 ]
  [ "$(jq -c '[.counts[] | [.label, .n]]' "$BATS_TEST_TMPDIR/m.json")" = '[["mutants",3],["caught",1],["gaps",1],["no observable effect",1]]' ]
  [ "$(jq -c .gaps "$BATS_TEST_TMPDIR/m.json")" = '[{"summary":"The label says adult or minor — swap labels","story":31}]' ]
}

@test "result: every survivor needs the tester's verdict" {
  jq -n '[{id: "b", behaviour: "x", description: "y", status: "survived"}]' > "$BATS_TEST_TMPDIR/r.json"
  echo '[]' > "$BATS_TEST_TMPDIR/v.json"
  run "$ROOT/bin/mutate.sh" result --results "$BATS_TEST_TMPDIR/r.json" --verdicts "$BATS_TEST_TMPDIR/v.json" --out "$BATS_TEST_TMPDIR/m.json"
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

# ---------- the Hardening report ----------

result() { mkdir -p "$BATS_TEST_TMPDIR/results"; echo "$2" > "$BATS_TEST_TMPDIR/results/$1.json"; }
report() { "$ROOT/bin/harden-report.sh" --results "$BATS_TEST_TMPDIR/results" --feature 6 --date 2026-09-25 "$@"; }

@test "harden report: every check of the set in a fixed order, with its gaps and stories" {
  result flaky '{"check":"flaky","title":"Flaky tests","ran":true,"counts":[{"label":"runs","n":5},{"label":"passed","n":5},{"label":"flaky tests","n":0}],"gaps":[]}'
  result mutation '{"check":"mutation","title":"Mutation testing","ran":true,"counts":[{"label":"mutants","n":3},{"label":"caught","n":2}],"gaps":[{"summary":"The 401 body is not checked","story":31}]}'
  result property '{"check":"property","title":"Property-based tests","ran":false,"reason":"no property-based library for this language"}'
  run report --set code
  [ "$status" -eq 0 ]
  cat > "$BATS_TEST_TMPDIR/want" <<'EOF2'
**Hardening** · code checks · 2026-09-25

- Mutation testing: 3 mutants · 2 caught
  - The 401 body is not checked → #31
- Property-based tests: not run — no property-based library for this language
- Flaky tests: 5 runs · 5 passed · 0 flaky tests
- Test smells: not run

<!-- compasso:harden feature=6 set=code -->
EOF2
  diff "$BATS_TEST_TMPDIR/want" <(printf '%s\n' "$output")
}

@test "harden report: the live set, and all checks" {
  result zap '{"check":"zap","title":"Security scan (ZAP)","ran":true,"counts":[{"label":"high","n":0}],"gaps":[]}'
  run report --set live
  [ "$(printf '%s\n' "$output" | grep -c '^- ')" -eq 4 ]
  [[ "$output" == *"- Security scan (ZAP): 0 high"* ]] || false
  run report --set all
  [ "$(printf '%s\n' "$output" | grep -c '^- ')" -eq 8 ]
}

@test "harden report: a malformed result is refused" {
  result smells '{"check":"smells","title":"Test smells","ran":true,"counts":"lots"}'
  run report --set code
  [ "$status" -eq 2 ]
  [[ "$output" == *"smells: does not follow the result format"* ]] || false
  result smells '{"check":"smells","title":"Test smells","ran":false}'
  run report --set code
  [ "$status" -eq 2 ]
}

# ---------- flaky ----------

@test "flaky: all runs pass is stable; mixed is flaky; all fail is a broken build" {
  run "$ROOT/bin/flaky.sh" --repo "$REPO" --test "true" --runs 3 --out "$BATS_TEST_TMPDIR/f1"
  [ "$status" -eq 0 ]
  [ "$(jq length "$BATS_TEST_TMPDIR/f1/runs.json")" -eq 3 ]
  echo 0 > "$BATS_TEST_TMPDIR/count"
  run "$ROOT/bin/flaky.sh" --repo "$REPO" --test "n=\$(cat $BATS_TEST_TMPDIR/count); echo \$((n+1)) > $BATS_TEST_TMPDIR/count; [ \$((n % 2)) -eq 0 ]" --runs 4 --out "$BATS_TEST_TMPDIR/f2"
  [ "$status" -eq 3 ]
  [ "$(jq -c 'map(.status)' "$BATS_TEST_TMPDIR/f2/runs.json")" = '["passed","failed","passed","failed"]' ]
  run "$ROOT/bin/flaky.sh" --repo "$REPO" --test "false" --runs 2 --out "$BATS_TEST_TMPDIR/f3"
  [ "$status" -eq 4 ]
}

@test "flaky: needs at least 2 runs and a clean tree" {
  run "$ROOT/bin/flaky.sh" --repo "$REPO" --test true --runs 1 --out "$BATS_TEST_TMPDIR/f"
  [ "$status" -eq 2 ]
  echo "// wip" >> src/age.js
  run "$ROOT/bin/flaky.sh" --repo "$REPO" --test true --runs 2 --out "$BATS_TEST_TMPDIR/f"
  [ "$status" -eq 2 ]
}

# ---------- live ----------

live() { "$ROOT/bin/live.sh" "$@" --repo "$REPO" --out "$BATS_TEST_TMPDIR/live"; }
lresult() { jq -c "$2" "$BATS_TEST_TMPDIR/live/$1.result.json"; }

@test "live parse zap: medium and high alerts are gaps" {
  mkdir -p "$BATS_TEST_TMPDIR/live"
  jq -n '{site: [{alerts: [
    {name: "Content Security Policy Header Not Set", riskcode: "2", instances: [{}, {}]},
    {name: "Server Leaks Version", riskcode: "1", instances: [{}]},
    {name: "Cookie without HttpOnly", riskcode: "3", instances: [{}]}]}]}' > "$BATS_TEST_TMPDIR/live/zap.json"
  run live parse zap
  [ "$status" -eq 0 ]
  [ "$(lresult zap '[.counts[] | .n]')" = '[1,1,1,0]' ]
  [ "$(lresult zap '[.gaps[].summary]')" = '["Content Security Policy Header Not Set (medium, 2 places)","Cookie without HttpOnly (high, 1 places)"]' ]
}

@test "live parse fuzz: failing operations are gaps" {
  mkdir -p "$BATS_TEST_TMPDIR/live"
  cat > "$BATS_TEST_TMPDIR/live/junit.xml" <<'EOF2'
<?xml version="1.0" ?>
<testsuites><testsuite name="schemathesis" tests="3">
<testcase name="GET /invoices"/>
<testcase name="GET /invoices/{id}"><failure message="Server error">500</failure></testcase>
<testcase name="GET /health"/>
</testsuite></testsuites>
EOF2
  run live parse fuzz
  [ "$(lresult fuzz '[.counts[] | [.label, .n]]')" = '[["operations",3],["failing",1]]' ]
  [ "$(lresult fuzz '[.gaps[].summary]')" = '["GET /invoices/{id} fails on generated input"]' ]
}

@test "live parse perf: limits exceeded are gaps" {
  mkdir -p "$BATS_TEST_TMPDIR/live"
  echo '{"metrics":{"http_reqs":{"count":300},"http_req_duration":{"p(95)":812.4},"http_req_failed":{"value":0.002}}}' > "$BATS_TEST_TMPDIR/live/k6.json"
  run live parse perf
  [ "$(lresult perf '[.counts[] | .n]')" = '[300,812,0.2]' ]
  [ "$(lresult perf '[.gaps[].summary]')" = '["95% of requests take up to 812 ms, over the 500 ms limit"]' ]
}

@test "live parse a11y: serious and critical violations are gaps" {
  mkdir -p "$BATS_TEST_TMPDIR/live"
  jq -n '[{page: "/billing", violations: [{id: "color-contrast", impact: "serious", help: "Elements must meet minimum color contrast", nodes: 3},
                                          {id: "region", impact: "moderate", help: "Content in landmarks", nodes: 1}]},
          {page: "/", violations: []}]' > "$BATS_TEST_TMPDIR/live/a11y.json"
  run live parse a11y
  [ "$(lresult a11y '[.counts[] | .n]')" = '[2,1,1]' ]
  [ "$(lresult a11y '[.gaps[].summary]')" = '["/billing: Elements must meet minimum color contrast (serious, 3 elements)"]' ]
}

@test "live parse: a missing tool report is a check that did not run" {
  run live parse zap
  [ "$status" -eq 1 ]
  [ "$(lresult zap '[.ran, .reason]')" = '[false,"ZAP wrote no report"]' ]
}

@test "live run: needs a configured URL, repeated to confirm it, and Docker" {
  run live run zap --confirm-url http://x
  [ "$status" -eq 1 ]
  [[ "$output" == *"set harden.environment.url"* ]] || false
  cfg_set '.harden.environment.url = "http://localhost:3000"'
  run live run zap --confirm-url http://staging.example.com
  [ "$status" -eq 1 ]
  [[ "$output" == *"--confirm-url must repeat harden.environment.url (http://localhost:3000)"* ]] || false
  mkdir -p "$BATS_TEST_TMPDIR/bin" && printf '#!/bin/sh\nexit 1\n' > "$BATS_TEST_TMPDIR/bin/docker" && chmod +x "$BATS_TEST_TMPDIR/bin/docker"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run live run zap --confirm-url http://localhost:3000
  [ "$status" -eq 1 ]
  [[ "$output" == *"Docker is not running"* ]] || false
}

@test "live run: fuzzing sends only reading requests unless the environment is disposable; localhost becomes host.docker.internal" {
  cfg_set '.harden.environment.url = "http://localhost:3000" | .harden.environment.openapi = "openapi.yaml"'
  echo "openapi: 3.0.0" > openapi.yaml
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/bin/sh\necho "$@" >> %s/docker.log\n' "$BATS_TEST_TMPDIR" > "$BATS_TEST_TMPDIR/bin/docker" && chmod +x "$BATS_TEST_TMPDIR/bin/docker"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run live run fuzz --confirm-url http://localhost:3000
  grep -q -- "run /repo/openapi.yaml --url http://host.docker.internal:3000 --include-method GET --include-method HEAD" "$BATS_TEST_TMPDIR/docker.log"
  cfg_set '.harden.environment.disposable = true'
  : > "$BATS_TEST_TMPDIR/docker.log"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run live run fuzz --confirm-url http://localhost:3000
  [ "$(grep -c -- '--include-method' "$BATS_TEST_TMPDIR/docker.log")" -eq 0 ]
}
