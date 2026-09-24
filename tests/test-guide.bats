#!/usr/bin/env bats
load helper

setup() {
  GUIDE="$BATS_TEST_TMPDIR/guide.json"; OUT="$BATS_TEST_TMPDIR/guide.html"
  cp "$ROOT/tests/fixtures/guide.json" "$GUIDE"
}
render() { "$ROOT/bin/test-guide.sh" --data "$GUIDE" --out "$OUT"; }
embedded() { awk -F'type="application/json">' '/id="guide-data"/{print $2}' "$OUT" | sed 's#</script>$##'; }
set_guide() { jq "$1" "$GUIDE" > "$GUIDE.new" && mv "$GUIDE.new" "$GUIDE"; }

@test "renders one self-contained page with the guide's data intact, quotes included" {
  run render
  [ "$status" -eq 0 ]
  [ "$(embedded | jq -c .)" = "$(jq -c . "$GUIDE")" ]
  [ "$(grep -c '__GUIDE_DATA__' "$OUT")" -eq 0 ]
  [ "$(grep -Ec '<(script|link)[^>]* (src|href)=' "$OUT")" -eq 0 ]
}

@test "text that contains </script> cannot end the data block early" {
  set_guide '.features[0].whats_new = "evil</script><script>alert(1)</script>"'
  render >/dev/null
  [ "$(grep -c '</script><script>alert' "$OUT")" -eq 0 ]
  [ "$(embedded | jq -r '.features[0].whats_new')" = "evil</script><script>alert(1)</script>" ]
}

@test "the page inserts content as text, never as HTML" {
  render >/dev/null
  [ "$(grep -Ec 'innerHTML|outerHTML|insertAdjacentHTML|document\.write' "$OUT")" -eq 0 ]
}

@test "the page shows no development details" {
  render >/dev/null
  [ "$(grep -Eic 'merge request|work item|commit|gitlab' "$OUT")" -eq 0 ]
}

@test "missing required content is refused, each problem named" {
  set_guide 'del(.goal) | .features[0].scenarios[0].expected = ""'
  run render
  [ "$status" -eq 1 ]
  [[ "$output" == *"goal is required"* ]] || false
  [[ "$output" == *"features[0].scenarios[0].expected is required"* ]] || false
}

@test "duplicate scenario ids are refused" {
  set_guide '.features[1].scenarios[0].id = "F-1.1"'
  run render
  [ "$status" -eq 1 ]
  [[ "$output" == *"scenario id F-1.1 is used more than once"* ]] || false
}

@test "the page script parses" {
  render >/dev/null
  awk '/<script>$/{f=1;next} /<\/script>/{f=0} f' "$OUT" > "$BATS_TEST_TMPDIR/page.js"
  node --check "$BATS_TEST_TMPDIR/page.js"
}

# ---------- results ----------

results_setup() {
  setup_repo
  export FAKE_GL="$BATS_TEST_TMPDIR/gl"; mkdir -p "$FAKE_GL/issues" "$FAKE_GL/parent"; : > "$FAKE_GL/calls.log"
  export PATH="$ROOT/tests/fake:$PATH"
  for i in 6 20; do echo "{\"iid\":$i,\"id\":$((1000 + i)),\"milestone\":{\"id\":501}}" > "$FAKE_GL/issues/$i.json"; done
  RESULTS="$BATS_TEST_TMPDIR/results.json"
  jq -n '{guide: "S20", tester: "Ana Silva", date: "2026-10-15", results: [
    {feature: "F-1", scenario: "F-1.1", status: "pass", comment: ""},
    {feature: "F-1", scenario: "F-1.2", status: "fail", comment: "It shows the 2026 invoices"},
    {feature: "F-1", scenario: "F-1.3", status: "pass", comment: ""},
    {feature: "F-1", scenario: "F-1.4", status: "not-tested", comment: ""},
    {feature: "F-3", scenario: "F-3.1", status: "blocked", comment: "No access to the test mailbox"}]}' > "$RESULTS"
}
import() { "$ROOT/bin/test-results.sh" --repo "$REPO" --guide "$GUIDE" --results "$RESULTS" --epic 12; }

@test "results: a failed scenario becomes a bug under its feature, in the tester's words" {
  results_setup
  run import
  [ "$status" -eq 0 ]
  grep -q "POST projects/acme%2Fapp/issues title=Invoice history: Filter by year does not work milestone_id=501 issue_type=task labels=type::bug,severity::major,owner::agent" "$FAKE_GL/calls.log"
  bug="$(ls "$FAKE_GL/desc/" | head -1)"
  cat > "$BATS_TEST_TMPDIR/want" <<'EOF2'
**Found in:** S20 test guide · **By:** Ana Silva (business test, 2026-10-15)

## Steps
1. Open Billing → Invoices.
2. Choose the year 2025 in the Year filter.

## Expected
- You see the message "No invoices for 2025".

## Actual
- It shows the 2026 invoices

## Evidence
- Reported by Ana Silva in the S20 test guide, scenario "Filter by year"

<!-- compasso:guide=S20 scenario=F-1.2 tester=ana-silva -->
EOF2
  diff "$BATS_TEST_TMPDIR/want" "$FAKE_GL/desc/$bug"
  [ "$(cat "$FAKE_GL/parent/$((1000 + ${bug%.md}))")" = 1006 ]
}

@test "results: a summary goes on the epic" {
  results_setup
  run import
  [[ "$output" == *"**Test results** · Ana Silva · 2026-10-15"* ]] || false
  [[ "$output" == *"- Works: 2 · Doesn't work: 1 · Can't test: 1 · Not tested: 1"* ]] || false
  [[ "$output" == *"- Doesn't work: Filter by year → #"* ]] || false
  [[ "$output" == *"- Can't test: Reminder arrives — No access to the test mailbox"* ]] || false
  grep -q "POST projects/acme%2Fapp/issues/12/notes" "$FAKE_GL/calls.log"
}

@test "results: importing the same file twice files each bug once" {
  results_setup
  import >/dev/null
  import >/dev/null
  [ "$(grep -c 'labels=type::bug' "$FAKE_GL/calls.log")" -eq 1 ]
}

@test "results: a file for another guide is refused" {
  results_setup
  jq '.guide = "S19"' "$RESULTS" > "$RESULTS.x" && mv "$RESULTS.x" "$RESULTS"
  run import
  [ "$status" -eq 1 ]
  [[ "$output" == *"not S20"* ]] || false
}

@test "results: an unknown scenario or a failure without a comment is refused, and nothing is filed" {
  results_setup
  jq '.results[0].scenario = "F-9.9" | .results[1].comment = ""' "$RESULTS" > "$RESULTS.x" && mv "$RESULTS.x" "$RESULTS"
  run import
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown scenario F-9.9"* ]] || false
  [[ "$output" == *"F-1.2 failed without a comment"* ]] || false
  [ "$(grep -c 'POST' "$FAKE_GL/calls.log" || true)" -eq 0 ]
}
