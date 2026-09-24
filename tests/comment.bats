#!/usr/bin/env bats
load helper

setup() {
  setup_repo
  cp "$ROOT/tests/fixtures/plan.yaml" "$REPO/.compasso/plan.yaml"
  # as after a push: every item has its GitLab iid
  yq -i '.features[0].gitlab = 6 | .features[1].gitlab = 7 | .blockers[0].gitlab = 13
    | (.features[].stories[] | select(.key == "S-1")).gitlab = 8 | (.features[].stories[] | select(.key == "S-2")).gitlab = 10
    | (.features[].stories[] | select(.key == "S-3")).gitlab = 11 | (.features[].stories[] | select(.key == "S-4")).gitlab = 9' "$REPO/.compasso/plan.yaml"
  echo "no findings" > "$BATS_TEST_TMPDIR/sec.md"
}
plan_comment() { "$ROOT/bin/comment.sh" plan --repo "$REPO" --feature "$1" --approver ana --security-file "${2:-$BATS_TEST_TMPDIR/sec.md}" --date 2026-09-24; }

@test "qa: each question with its answer on the next line, who answered and when" {
  echo '{"round":2,"user":"ana","date":"2026-09-24","items":[{"question":"20 per page?","answer":"Yes"},{"question":"Closed accounts?","answer":"No"}]}' > "$BATS_TEST_TMPDIR/qa.json"
  run "$ROOT/bin/comment.sh" qa --file "$BATS_TEST_TMPDIR/qa.json"
  [ "$status" -eq 0 ]
  cat > "$BATS_TEST_TMPDIR/want" <<'EOF2'
**Questions and answers** · round 2 · answered by @ana in the agent, 2026-09-24

1. 20 per page?\
   → Yes
2. Closed accounts?\
   → No

<!-- compasso:qa round=2 -->
EOF2
  diff "$BATS_TEST_TMPDIR/want" <(printf '%s\n' "$output")
}

@test "qa: refuses a round without answers" {
  echo '{"round":1,"user":"ana","date":"2026-09-24","items":[]}' > "$BATS_TEST_TMPDIR/qa.json"
  run "$ROOT/bin/comment.sh" qa --file "$BATS_TEST_TMPDIR/qa.json"
  [ "$status" -eq 1 ]
}

@test "plan: one row per story of the feature, dependencies as GitLab references" {
  run plan_comment F-1
  [ "$status" -eq 0 ]
  cat > "$BATS_TEST_TMPDIR/want" <<'EOF2'
**Plan** · 3 stories · 14h · critical path 10h

| Story | h | Owner | Depends on |
|---|---|---|---|
| #8 Invoice list API | 4 | agent | — |
| #10 Invoice list UI | 6 | human | #8 |
| #11 Year filter | 4 | either | #8 |

**Security:** no findings

**Approved:** by @ana in the agent, 2026-09-24
EOF2
  diff "$BATS_TEST_TMPDIR/want" <(printf '%s\n' "$output")
}

@test "plan: blockers and existing items appear among the dependencies; one story is singular" {
  yq -i '.features[1].stories[0].depends_on = ["#40"]' "$REPO/.compasso/plan.yaml"
  run plan_comment F-2
  [ "$status" -eq 0 ]
  [[ "$output" == "**Plan** · 1 story · 8h · critical path 8h"* ]] || false
  [[ "$output" == *"| #9 PDF endpoint | 8 | agent | #40, #13 |"* ]] || false
}

@test "plan: a dependency on another feature's story still passes plan-check" {
  yq -i '.features[1].stories[0].depends_on = ["S-1"]' "$REPO/.compasso/plan.yaml"
  run plan_comment F-2
  [ "$status" -eq 0 ]
  [[ "$output" == *"| #9 PDF endpoint | 8 | agent | #8, #13 |"* ]] || false
}

@test "plan: security findings are listed under the Security line" {
  printf -- '- [major] 404 leaks whether an invoice exists\n' > "$BATS_TEST_TMPDIR/sec2.md"
  run plan_comment F-1 "$BATS_TEST_TMPDIR/sec2.md"
  [[ "$output" == *$'**Security:**\n- [major] 404 leaks whether an invoice exists'* ]] || false
}

@test "plan: an unknown feature is refused" {
  run plan_comment F-9
  [ "$status" -eq 1 ]
  [[ "$output" == *"no feature F-9"* ]] || false
}

@test "plan: before the push, stories and dependencies show their plan keys" {
  yq -i '(.features[1].stories[0]).gitlab = null | .blockers[0].gitlab = null' "$REPO/.compasso/plan.yaml"
  run plan_comment F-2
  [[ "$output" == *"| S-4 PDF endpoint | 8 | agent | #12, B-1 |"* ]] || false
}
