#!/usr/bin/env bats
load helper

setup() {
  RUN="$BATS_TEST_TMPDIR/run"; mkdir -p "$RUN"
  jq -n '{iid: 8, story: {key: "S-1", verify: ["npm test -- billing/api", "npx playwright test billing/list"]}}' > "$BATS_TEST_TMPDIR/story.json"
  printf -- '- GET /invoices, newest first, 20 per page\n403 for another customer\x27s invoices\n\n' > "$RUN/changes.md"
  echo '[]' > "$RUN/findings.json"
}
body() { "$ROOT/bin/mr-body.sh" --story "$BATS_TEST_TMPDIR/story.json" --run "$RUN"; }

@test "the merge request description follows the approved format" {
  echo '{"status":"ok","percent":86,"min":80,"uncovered":[]}' > "$RUN/coverage.json"
  jq -n '[{by:"reviewer",severity:"major",status:"fixed",summary:"a"},{by:"reviewer",severity:"blocker",status:"fixed",summary:"b"},
          {by:"reviewer",severity:"minor",status:"followup",followup_iid:52,summary:"c"}]' > "$RUN/findings.json"
  run body
  [ "$status" -eq 0 ]
  cat > "$BATS_TEST_TMPDIR/want" <<'EOF2'
Closes #8

## Changes
- GET /invoices, newest first, 20 per page
- 403 for another customer's invoices

## How to test
1. `npm test -- billing/api`
2. `npx playwright test billing/list`

## Review
- Reviewer: 2 findings fixed · minors → #52
- Security: no findings
- Coverage: 86% of changed lines (min 80%)

<!-- compasso:story=S-1 -->
EOF2
  diff "$BATS_TEST_TMPDIR/want" <(printf '%s\n' "$output")
}

@test "security findings are listed with whether security verified the fix" {
  jq -n '[{by:"security",severity:"major",status:"fixed",verified_by:"security",summary:"IDOR on /invoices/:id"},
          {by:"security",severity:"minor",status:"open",summary:"stack trace in 500"}]' > "$RUN/findings.json"
  run body
  [[ "$output" == *"- Security: "*"  - [major] IDOR on /invoices/:id — fixed, verified by security"* ]] || false
  [[ "$output" == *"  - [minor] stack trace in 500 — open"* ]] || false
}

@test "coverage below the minimum lists the uncovered lines; no result means not measured" {
  echo '{"status":"below","percent":72,"min":80,"uncovered":["src/a.py:6","src/a.py:7"]}' > "$RUN/coverage.json"
  run body
  [[ "$output" == *"- Coverage: below min: 72% of 80% · uncovered: src/a.py:6, src/a.py:7"* ]] || false
  rm "$RUN/coverage.json"
  run body
  [[ "$output" == *"- Coverage: not measured"* ]] || false
}

@test "no reviewer findings says so; open ones are counted" {
  run body
  [[ "$output" == *"- Reviewer: no findings"* ]] || false
  echo '[{"by":"reviewer","severity":"major","status":"open","summary":"x"}]' > "$RUN/findings.json"
  run body
  [[ "$output" == *"- Reviewer: 1 open"* ]] || false
}

@test "a missing input stops it" {
  rm "$RUN/changes.md"
  run body
  [ "$status" -eq 2 ]
}
