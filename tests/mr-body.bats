#!/usr/bin/env bats
load helper

setup() {
  RUN="$BATS_TEST_TMPDIR/run"; mkdir -p "$RUN"
  jq -n '{iid: 8, story: {key: "S-1", verify: ["npm test -- billing/api", "npx playwright test billing/list"]}}' > "$BATS_TEST_TMPDIR/story.json"
  printf -- '- GET /invoices, newest first, 20 per page\n403 for another customer\x27s invoices\n\n' > "$RUN/changes.md"
}
body() { "$ROOT/bin/mr-body.sh" --story "$BATS_TEST_TMPDIR/story.json" --run "$RUN"; }

@test "the merge request description: what changed, how to test it, and the coverage when it was measured" {
  echo '{"status":"ok","percent":86,"min":80,"uncovered":[]}' > "$RUN/coverage.json"
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

Coverage: 86% of changed lines (min 80%)

<!-- compasso:story=S-1 -->
EOF2
  diff "$BATS_TEST_TMPDIR/want" <(printf '%s\n' "$output")
}

@test "coverage below the minimum lists the uncovered lines; not measured says so; none or skipped (the MVP) shows nothing" {
  echo '{"status":"below","percent":72,"min":80,"uncovered":["src/a.py:6","src/a.py:7"]}' > "$RUN/coverage.json"
  run body
  [[ "$output" == *"Coverage: below min: 72% of 80% · uncovered: src/a.py:6, src/a.py:7"* ]] || false
  echo '{"status":"not-measured"}' > "$RUN/coverage.json"
  run body
  [[ "$output" == *"Coverage: not measured"* ]] || false
  echo '{"status":"skipped","percent":null,"min":80,"uncovered":[]}' > "$RUN/coverage.json"
  run body
  [[ "$output" != *"Coverage"* ]] || false
  rm "$RUN/coverage.json"
  run body
  [ "$status" -eq 0 ]
  [[ "$output" != *"Coverage"* ]] || false
  [[ "$output" != *"Review"* ]] || false
}

@test "a missing input stops it" {
  rm "$RUN/changes.md"
  run body
  [ "$status" -eq 2 ]
}
