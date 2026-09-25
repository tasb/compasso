#!/usr/bin/env bats
load helper

setup() {
  setup_repo
  D="$BATS_TEST_TMPDIR/record.json"
  jq -n '{title: "S20 plan", date: "2026-10-02", approved_by: "tasb", ref: "3f2a1c",
    findings: [{by: "security", text: "S-3 exports personal data", outcome: "abuse cases added"}],
    decisions: [{text: "CSV only", by: "tasb", date: "2026-10-02"}, {text: "dates are UTC", assumed: true}],
    takeaways: ["Export needs a platform key"], constraints: ["Capacity 80h; plan uses 9.5h"],
    missing: [{text: "Who owns the exports bucket?", status: "open"}]}' > "$D"
}
rec() { "$ROOT/bin/record.sh" "$@"; }

@test "path: records are grouped by sprint, stories in their own folder" {
  cp "$ROOT/tests/fixtures/plan.yaml" "$REPO/.compasso/plan.yaml"
  [ "$(rec path --repo "$REPO" --kind plan --key plan)" = .compasso/records/S20/plan.md ]
  [ "$(rec path --repo "$REPO" --kind feature --key F-2)" = .compasso/records/S20/F-2.md ]
  [ "$(rec path --repo "$REPO" --kind story --key 8 --sprint S21)" = .compasso/records/S21/stories/8.md ]
  rm "$REPO/.compasso/plan.yaml"
  [ "$(rec path --repo "$REPO" --kind story --key 8)" = .compasso/records/backlog/stories/8.md ]
}

@test "write: the five sections in order, with who and when" {
  run rec write --data "$D" --out "$BATS_TEST_TMPDIR/out/plan.md"
  [ "$status" -eq 0 ]
  [ "$(cat "$BATS_TEST_TMPDIR/out/plan.md")" = "$(cat <<'MD'
# S20 plan · 2026-10-02
Approved by @tasb · plan.yaml @ 3f2a1c

## Findings
- security: S-3 exports personal data → abuse cases added

## Decisions
- CSV only (@tasb, 2026-10-02)
- Assumed: dates are UTC

## Takeaways
- Export needs a platform key

## Constraints
- Capacity 80h; plan uses 9.5h

## Missing points
- Who owns the exports bucket? (open)
MD
)" ]
}

@test "write: an empty section says None, so it reads as considered" {
  jq '.takeaways = [] | .missing = []' "$D" > "$D.2"
  rec write --data "$D.2" --out "$BATS_TEST_TMPDIR/p.md" >/dev/null
  [ "$(grep -A1 '^## Takeaways' "$BATS_TEST_TMPDIR/p.md" | tail -1)" = "- None" ]
  [ "$(tail -1 "$BATS_TEST_TMPDIR/p.md")" = "- None" ]
}

@test "write: a missing section or an empty finding is refused, and nothing is written" {
  jq 'del(.constraints) | .findings[0].by = ""' "$D" > "$D.2"
  run rec write --data "$D.2" --out "$BATS_TEST_TMPDIR/p.md"
  [ "$status" -eq 1 ]
  [[ "$output" == *"constraints must be a list"* ]] || false
  [[ "$output" == *"every finding needs by and text"* ]] || false
  [ ! -e "$BATS_TEST_TMPDIR/p.md" ]
}

@test "story: every finding with what happened to it, plus the run's own decisions" {
  RUN="$BATS_TEST_TMPDIR/run"; mkdir -p "$RUN"
  jq -n '{iid: 8, title: "List API", milestone: "S20"}' > "$RUN/story.json"
  jq -n '[{by: "reviewer", severity: "minor", status: "followup", followup_iid: 31, file: "src/a.js", line: 3, summary: "Vague name."},
          {by: "security", severity: "major", status: "fixed", summary: "Token accepted from __proto__."}]' > "$RUN/findings.json"
  jq -n '{decisions: [{text: "Paginate by cursor, not offset"}], missing: [{text: "Sort order for equal dates", status: "open"}]}' > "$RUN/record.json"
  run rec story --repo "$REPO" --run "$RUN"
  [ "$status" -eq 0 ]
  f="$REPO/.compasso/records/S20/stories/8.md"
  head -1 "$f" | grep -q '^# #8 List API · '
  grep -qx -- '- reviewer: \[minor\] Vague name. (`src/a.js:3`) → follow-up #31' "$f"
  grep -qx -- '- security: \[major\] Token accepted from __proto__. → fixed' "$f"
  grep -qx -- '- Paginate by cursor, not offset' "$f"
  [ "$(grep -A1 '^## Constraints' "$f" | tail -1)" = "- None" ]
}

@test "story: works without record.json; an invalid one is refused" {
  RUN="$BATS_TEST_TMPDIR/run"; mkdir -p "$RUN"
  jq -n '{iid: 9, title: "t", milestone: null}' > "$RUN/story.json"; echo '[]' > "$RUN/findings.json"
  rec story --repo "$REPO" --run "$RUN" >/dev/null
  [ "$(grep -A1 '^## Findings' "$REPO/.compasso/records/backlog/stories/9.md" | tail -1)" = "- None" ]
  echo '{oops' > "$RUN/record.json"
  run rec story --repo "$REPO" --run "$RUN"
  [ "$status" -eq 1 ]
}
