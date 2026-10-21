#!/usr/bin/env bats
load helper

# The comments a developer's run posts on its merge request, for the tech lead to read back:
# the review findings, and the cost of an infrastructure change (the finops report).
setup() {
  setup_repo
  RUN="$BATS_TEST_TMPDIR/run"; mkdir -p "$RUN"
  jq -n '[{by: "reviewer", severity: "minor", status: "followup", followup_iid: 40, summary: "Vague name", file: "src/a.js", line: 3},
          {by: "security", severity: "major", status: "fixed", verified_by: "security", summary: "SQL injection in the filter"}]' > "$RUN/findings.json"
  echo '{"status":"ok","percent":92,"min":80}' > "$RUN/coverage.json"
  echo '{"sensitive":"authentication"}' > "$RUN/sensitive.json"
  jq -n '{result: "increase", monthly_delta: 15.2, currency: "USD",
          resources: [{change: "add", name: "aws_db_instance.history (db.t3.small)", monthly: 15.2}],
          assumptions: ["on demand, 730 hours a month"], sources: ["https://aws.amazon.com/rds/pricing/"]}' > "$RUN/cost.json"
  export PATH="$ROOT/tests/fake:$PATH"
}
report() { "$ROOT/bin/mr-report.sh" "$@" --repo "$REPO"; }
gl() { export FAKE_GL="$BATS_TEST_TMPDIR/gl"; mkdir -p "$FAKE_GL/issues"; : > "$FAKE_GL/calls.log"; }
gh_() {
  cfg_set '.tracker.provider = "github" | .tracker.host = "github.com"'
  export FAKE_GH="$BATS_TEST_TMPDIR/gh"; mkdir -p "$FAKE_GH"/{issues,comments}; : > "$FAKE_GH/calls.log"
}

@test "the findings comment: its marker, the findings in the project's language, and the data, collapsed" {
  run report findings --run "$RUN"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "<!-- compasso:findings -->" ]
  [[ "$output" == *"[security/major] SQL injection in the filter"* ]] || false
  [[ "$output" == *"<details><summary>Data for the tech lead</summary>"* ]] || false
  data="$(printf '%s\n' "$output" | awk '/^```json$/ {on=1; next} /^```$/ {on=0} on')"
  [ "$(jq -c '[(.findings | length), .coverage.percent, .sensitive]' <<<"$data")" = '[2,92,"authentication"]' ]
}

@test "without coverage or security's mark, the data says so" {
  rm "$RUN/coverage.json" "$RUN/sensitive.json"
  data="$(report findings --run "$RUN" | awk '/^```json$/ {on=1; next} /^```$/ {on=0} on')"
  [ "$(jq -c '[.coverage, .sensitive]' <<<"$data")" = '[null,null]' ]
}

@test "the cost comment: the result, the monthly change, each resource, the assumptions and sources, and the data" {
  run report cost --run "$RUN"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "<!-- compasso:cost -->" ]
  [[ "$output" == *"**Result:** increase · +15.2 USD a month"* ]] || false
  [[ "$output" == *"- added: aws_db_instance.history (db.t3.small) · 15.2 USD a month"* ]] || false
  [[ "$output" == *"- on demand, 730 hours a month"* ]] || false
  [[ "$output" == *"https://aws.amazon.com/rds/pricing/"* ]] || false
  data="$(printf '%s\n' "$output" | awk '/^```json$/ {on=1; next} /^```$/ {on=0} on')"
  [ "$(jq -r .result <<<"$data")" = increase ]
}

@test "a cost report must say none, increase, decrease or unknown" {
  echo '{"result":"cheap"}' > "$RUN/cost.json"
  run report cost --run "$RUN"
  [ "$status" -eq 2 ]
  [[ "$output" == *"none, increase, decrease or unknown"* ]] || false
}

@test "GitLab: post writes each comment once and edits it in place after a later round; read gives the data back" {
  gl
  run report post --run "$RUN" --mr 31
  [ "$status" -eq 0 ]
  [ "$(jq length "$FAKE_GL/notes/mr-31.json")" -eq 2 ]
  jq '.[0].severity = "minor"' "$RUN/findings.json" > "$RUN/f" && mv "$RUN/f" "$RUN/findings.json"
  rm "$RUN/cost.json"
  report post --run "$RUN" --mr 31
  [ "$(jq length "$FAKE_GL/notes/mr-31.json")" -eq 2 ]
  grep -q "PUT projects/acme%2Fapp/merge_requests/31/notes/" "$FAKE_GL/calls.log"
  OUT="$BATS_TEST_TMPDIR/lead"; mkdir -p "$OUT"
  run report read --mr 31 --out "$OUT"
  [ "$status" -eq 0 ]
  [ "$(jq -c . <<<"$output")" = '{"findings":true,"cost":true}' ]
  [ "$(jq length "$OUT/findings.json")" -eq 2 ]
  [ "$(jq -r .percent "$OUT/coverage.json")" = 92 ]
  [ "$(jq -r .sensitive "$OUT/sensitive.json")" = authentication ]
  [ "$(jq -r .result "$OUT/cost.json")" = increase ]
}

@test "GitHub: the same, on the pull request's comments" {
  gh_
  report post --run "$RUN" --mr 31
  [ "$(jq length "$FAKE_GH/comments/31.json")" -eq 2 ]
  report post --run "$RUN" --mr 31
  [ "$(jq length "$FAKE_GH/comments/31.json")" -eq 2 ]
  grep -q "PATCH repos/acme/app/issues/comments/" "$FAKE_GH/calls.log"
  OUT="$BATS_TEST_TMPDIR/lead"; mkdir -p "$OUT"
  run report read --mr 31 --out "$OUT"
  [ "$(jq -c . <<<"$output")" = '{"findings":true,"cost":true}' ]
  [ "$(jq -r .result "$OUT/cost.json")" = increase ]
}

@test "post: the findings go on the story too, so it records what was found and fixed, edited in place" {
  gl
  echo '{"iid":8}' > "$RUN/story.json"
  report post --run "$RUN" --mr 31 >/dev/null
  report post --run "$RUN" --mr 31 >/dev/null
  [ "$(jq length "$FAKE_GL/notes/8.json")" -eq 1 ]
  [ "$(jq -r '.[0].body' "$FAKE_GL/notes/8.json" | head -1)" = "<!-- compasso:findings -->" ]
  grep -q "PUT projects/acme%2Fapp/issues/8/notes/" "$FAKE_GL/calls.log"
  gh_
  report post --run "$RUN" --mr 31 >/dev/null
  report post --run "$RUN" --mr 31 >/dev/null
  [ "$(jq length "$FAKE_GH/comments/8.json")" -eq 1 ]
}

@test "read: a comment by someone outside the project counts for nothing, and a missing report is said" {
  gh_
  FAKE_GH_ASSOC=NONE report post --run "$RUN" --mr 31
  OUT="$BATS_TEST_TMPDIR/lead"; mkdir -p "$OUT"
  run report read --mr 31 --out "$OUT"
  [ "$status" -eq 0 ]
  [ "$(jq -c . <<<"$output")" = '{"findings":false,"cost":false}' ]
  [ ! -e "$OUT/findings.json" ]
}
