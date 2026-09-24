#!/usr/bin/env bats
load helper

# ---------- story-metrics ----------

sm() { "$ROOT/bin/story-metrics.sh" "$@"; }

@test "story-metrics: agent runs and events become one summary for the story" {
  RUN="$BATS_TEST_TMPDIR/run"; REPO="$BATS_TEST_TMPDIR/repo"; mkdir -p "$RUN" "$REPO"
  jq -n '{iid: 8, title: "Invoice list API", kind: "story", estimate_h: 4, story: {key: "S-1"}}' > "$RUN/story.json"
  jq -n '[{by: "security", severity: "major", status: "fixed", verified_by: "security", summary: "a"},
          {by: "security", severity: "minor", status: "fixed", summary: "b"},
          {by: "reviewer", severity: "minor", status: "followup", summary: "c"}]' > "$RUN/findings.json"
  echo '{"status":"below","percent":72,"min":80,"uncovered":[]}' > "$RUN/coverage.json"
  sm agent --run "$RUN" --role tester --model sonnet --tokens 1000 --ms 60000
  sm event --run "$RUN" --type round
  sm agent --run "$RUN" --role security --model opus
  sm event --run "$RUN" --type verify-fail
  sm event --run "$RUN" --type round
  run sm write --run "$RUN" --repo "$REPO"
  [ "$status" -eq 0 ]
  m="$REPO/.compasso/metrics/8.json"
  [ "$(jq -c '[.iid, .key, .estimate_h, .review_rounds, .verify_failures, .violations, .replanned]' "$m")" = '[8,"S-1",4,2,1,0,false]' ]
  [ "$(jq -c '.findings' "$m")" = '{"reviewer":{"blocker":0,"major":0,"minor":1},"security":{"blocker":0,"major":1,"minor":1}}' ]
  [ "$(jq '.security_open' "$m")" = 1 ]
  [ "$(jq -c '.coverage' "$m")" = '{"status":"below","percent":72,"min":80}' ]
  [ "$(jq -c '.agents' "$m")" = '[{"role":"tester","model":"sonnet","tokens":1000,"ms":60000},{"role":"security","model":"opus"}]' ]
}

@test "story-metrics: unknown events and non-numeric tokens are refused" {
  run sm event --run "$BATS_TEST_TMPDIR/run" --type party
  [ "$status" -eq 2 ]
  run sm agent --run "$BATS_TEST_TMPDIR/run" --role tester --model sonnet --tokens lots
  [ "$status" -eq 2 ]
}

# ---------- collect ----------

collect_setup() {
  setup_repo
  export FAKE_GL="$BATS_TEST_TMPDIR/gl"; mkdir -p "$FAKE_GL/issues" "$FAKE_GL/parent" "$FAKE_GL/events"; : > "$FAKE_GL/calls.log"
  export PATH="$ROOT/tests/fake:$PATH"
  yq -n '.epic = {"key": "E-1", "goal": "Invoices", "sprint": {"number": 20, "start": "2026-10-05", "end": "2026-10-09"}}' > "$REPO/.compasso/plan.yaml"
  # stories #8 (4h, closed 10-06), #11 (4h, open, in review), #9 (8h, blocked), blocker #13, bugs #21 (tester) and #22 (e2e)
  jq -n '[
    {iid: 8, id: 1008, issue_type: "task", title: "List API", state: "closed", labels: ["owner::agent"], description: "",
     time_stats: {time_estimate: 14400}, created_at: "2026-10-05T08:00:00Z", closed_at: "2026-10-06T12:00:00.000Z", assignees: []},
    {iid: 11, id: 1011, issue_type: "task", title: "Year filter", state: "opened", labels: ["owner::either", "compasso::in-review"], description: "",
     time_stats: {time_estimate: 14400}, created_at: "2026-10-05T08:00:00Z", closed_at: null, assignees: []},
    {iid: 9, id: 1009, issue_type: "task", title: "PDF endpoint", state: "opened", labels: ["owner::agent", "blocked"], description: "**Blocked by:** #13",
     time_stats: {time_estimate: 28800}, created_at: "2026-10-05T08:00:00Z", closed_at: null, assignees: []},
    {iid: 13, id: 1013, issue_type: "task", title: "PDF credentials", state: "opened", labels: ["type::blocker"], description: "",
     time_stats: {time_estimate: 0}, created_at: "2026-10-05T08:00:00Z", closed_at: null, assignees: [{username: "ana"}]},
    {iid: 21, id: 1021, issue_type: "task", title: "Filter by year does not work", state: "opened", labels: ["type::bug"],
     description: "**Found in:** S20 test guide · **By:** Ana (business test, 2026-10-08)", time_stats: {time_estimate: 0},
     created_at: "2026-10-08T08:00:00Z", closed_at: null, assignees: []},
    {iid: 22, id: 1022, issue_type: "task", title: "Empty page 2", state: "closed", labels: ["type::bug"],
     description: "**Found in:** !4 · **By:** feature e2e", time_stats: {time_estimate: 0},
     created_at: "2026-10-07T08:00:00Z", closed_at: "2026-10-08T08:00:00Z", assignees: []}]' > "$FAKE_GL/issue-query.json"
  jq -n '[{iid: 1, issue_type: "task", labels: [], time_stats: {time_estimate: 36000}},
          {iid: 2, issue_type: "task", labels: [], time_stats: {time_estimate: 7200}},
          {iid: 3, issue_type: "task", labels: ["type::blocker"], time_stats: {time_estimate: 99999}}]' > "$FAKE_GL/issues-S19.json"
  echo '[]' > "$FAKE_GL/issues-S18.json"; echo '[]' > "$FAKE_GL/issues-S17.json"; echo '[]' > "$FAKE_GL/issues-S16.json"
  jq -n '[{action: "add", label: {name: "compasso::building"}, created_at: "2026-10-05T10:00:00Z"},
          {action: "add", label: {name: "compasso::in-review"}, created_at: "2026-10-05T11:00:00.000Z"}]' > "$FAKE_GL/events/8.json"
  jq -n '[{action: "add", label: {name: "compasso::building"}, created_at: "2026-10-07T10:00:00Z"},
          {action: "add", label: {name: "compasso::in-review"}, created_at: "2026-10-07T12:00:00Z"}]' > "$FAKE_GL/events/11.json"
  mkdir -p "$REPO/.compasso/metrics" "$REPO/docs/releases/S20-results"
  jq -n '{iid: 8, title: "List API", estimate_h: 4, review_rounds: 2, security_open: 0, coverage: {status: "ok", percent: 100, min: 80},
          findings: {reviewer: {blocker: 0, major: 1, minor: 0}, security: {blocker: 0, major: 1, minor: 1}},
          agents: [{role: "tester", model: "sonnet", tokens: 2000000, ms: 120000}, {role: "security", model: "opus", tokens: 1000000, ms: 60000}]}' \
    > "$REPO/.compasso/metrics/8.json"
  jq -n '{iid: 99, title: "Another sprint", review_rounds: 9, findings: {reviewer: {blocker: 9, major: 0, minor: 0}, security: {blocker: 9, major: 0, minor: 0}}, agents: []}' \
    > "$REPO/.compasso/metrics/99.json"
  jq -n '{guide: "S20", tester: "Ana", results: [{status: "pass"}, {status: "pass"}, {status: "fail"}, {status: "blocked"}]}' > "$REPO/docs/releases/S20-results/ana.json"
  OUT="$BATS_TEST_TMPDIR/report.json"
}
collect() { "$ROOT/bin/metrics.sh" collect --repo "$REPO" --out "$OUT" --today "${1:-2026-10-07}" >/dev/null; }
get() { jq -c "$1" "$OUT"; }

@test "collect: planned and done hours count stories and bugs, never blockers" {
  collect_setup; collect
  [ "$(get '.delivery | [.planned_h, .done_h, .stories_total, .stories_done, .stories_blocked]')" = '[16,4,5,2,1]' ]
}

@test "collect: the burn-down runs from the sprint start to today" {
  collect_setup; collect 2026-10-07
  [ "$(get '[.delivery.burndown[] | [.date, .remaining_h]]')" = '[["2026-10-05",16],["2026-10-06",12],["2026-10-07",12]]' ]
}

@test "collect: velocity has past sprints' done hours, without blockers, then this sprint" {
  collect_setup; collect
  [ "$(get '.delivery.velocity')" = '[{"sprint":"S19","done_h":12},{"sprint":"S20","done_h":4}]' ]
}

@test "collect: each open story says what it waits on" {
  collect_setup; collect
  [ "$(get '[.delivery.open[] | [.title, .waiting_on]]')" = '[["Year filter","approval of its merge request"],["PDF endpoint","blocker: PDF credentials"],["Filter by year does not work","nothing - ready to build"]]' ]
  [ "$(get '.delivery.blockers')" = '[{"title":"PDF credentials","owner":"ana","open_days":2,"state":"open"}]' ]
}

@test "collect: flow splits each story into building and waiting for approval" {
  collect_setup; collect
  [ "$(get '[.flow.stories[] | select(.title == "List API") | [.building_h, .waiting_h, .merged]]')" = '[[1,25,true]]' ]
  [ "$(get '[.flow.stories[] | select(.title == "Year filter") | [.building_h, .merged]]')" = '[[2,false]]' ]
}

@test "collect: quality comes from this sprint's stories only" {
  collect_setup; collect
  [ "$(get '.quality | [.findings, .security_open, .review_rounds_avg, .coverage_avg]')" = '[{"reviewer":{"blocker":0,"major":1,"minor":0},"security":{"blocker":0,"major":1,"minor":1}},0,2,100]' ]
  [ "$(get '.quality.bugs')" = '{"testers":1,"feature_e2e":1}' ]
  [ "$(get '.quality.test_guide')" = '{"pass":2,"fail":1,"blocked":1,"not_tested":0}' ]
}

@test "collect: agent effort by role and by story; no cost without prices" {
  collect_setup; collect
  [ "$(get '[.agents.by_role[] | [.role, .model, .runs, .tokens, .minutes]]')" = '[["security","opus",1,1000000,1],["tester","sonnet",1,2000000,2]]' ]
  [ "$(get '[.agents.stories[] | [.title, .estimate_h, .agent_minutes, .tokens, .cost]]')" = '[["List API",4,3,3000000,null]]' ]
  [ "$(get '.agents.cost')" = null ]
}

@test "collect: with prices, cost per story and in total" {
  collect_setup
  cfg_set '.metrics.prices = {"sonnet": 3, "opus": 15} | .metrics.currency = "EUR"'
  collect
  [ "$(get '.agents.stories[0].cost')" = 21 ]
  [ "$(get '.agents.cost')" = '{"currency":"EUR","total":21}' ]
}

@test "collect: without a plan it refuses" {
  collect_setup; rm "$REPO/.compasso/plan.yaml"
  run "$ROOT/bin/metrics.sh" collect --repo "$REPO" --out "$OUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"/compasso:plan"* ]] || false
}

# ---------- report ----------

@test "report: renders the fixture into a self-contained page with its data intact" {
  OUT="$BATS_TEST_TMPDIR/r.html"
  run "$ROOT/bin/report.sh" --data "$ROOT/tests/fixtures/report.json" --out "$OUT"
  [ "$status" -eq 0 ]
  [ "$(awk -F'type="application/json">' '/id="report-data"/{print $2}' "$OUT" | sed 's#</script>$##' | jq -c .)" = "$(jq -c . "$ROOT/tests/fixtures/report.json")" ]
  [ "$(grep -Ec '<(script|link)[^>]* (src|href)=' "$OUT")" -eq 0 ]
  [ "$(grep -Ec 'innerHTML|outerHTML|insertAdjacentHTML|document\.write' "$OUT")" -eq 0 ]
  awk '/<script>$/{f=1;next} /<\/script>/{f=0} f' "$OUT" > "$BATS_TEST_TMPDIR/r.js"
  node --check "$BATS_TEST_TMPDIR/r.js"
}

@test "report: text containing </script> cannot end the data block" {
  jq '.sprint.goal = "x</script><script>alert(1)</script>"' "$ROOT/tests/fixtures/report.json" > "$BATS_TEST_TMPDIR/d.json"
  "$ROOT/bin/report.sh" --data "$BATS_TEST_TMPDIR/d.json" --out "$BATS_TEST_TMPDIR/r.html" >/dev/null
  [ "$(grep -c '</script><script>alert' "$BATS_TEST_TMPDIR/r.html")" -eq 0 ]
}

@test "report: missing sections are refused" {
  jq 'del(.flow) | del(.sprint.goal)' "$ROOT/tests/fixtures/report.json" > "$BATS_TEST_TMPDIR/d.json"
  run "$ROOT/bin/report.sh" --data "$BATS_TEST_TMPDIR/d.json" --out "$BATS_TEST_TMPDIR/r.html"
  [ "$status" -eq 1 ]
  [[ "$output" == *"flow is required"* ]] || false
  [[ "$output" == *"sprint.goal is required"* ]] || false
}
