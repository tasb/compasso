#!/usr/bin/env bats
load helper

# Sprint S20 on GitHub (no Project): feature #6 with #8 (closed, still labelled in review),
# #11 (runnable), #9 (waits on #11) and #10 (blocked by blocker #13, assigned to ana).
setup() {
  setup_repo
  cfg_set '.tracker.provider = "github" | .tracker.host = "github.com" | .tracker.github.project = 0'
  export FAKE_GH="$BATS_TEST_TMPDIR/gh"; mkdir -p "$FAKE_GH"/{issues,parent,blocked}; : > "$FAKE_GH/calls.log"
  export PATH="$ROOT/tests/fake:$PATH"
  echo '[{"number":1,"title":"S20"}]' > "$FAKE_GH/milestones.json"
  issue 6 "Invoice history" open '["type::feature"]'
  issue 30 "S20: goal" open '["type::epic"]'
  issue 8 "List API" closed '["owner::agent","compasso::in-review"]'
  issue 11 "Year filter" open '["owner::agent"]' '**Verify:** x'
  issue 9 "Status filter" open '["owner::agent"]'
  issue 10 "PDF" open '["owner::agent","blocked"]'
  issue 13 "Credentials" open '["type::blocker"]'
  jq '.assignees = [{login: "ana"}]' "$FAKE_GH/issues/13.json" > "$FAKE_GH/t" && mv "$FAKE_GH/t" "$FAKE_GH/issues/13.json"
  for n in 8 11 9 10; do echo 6 > "$FAKE_GH/parent/$n"; done
  echo 11 > "$FAKE_GH/blocked/9"; echo 13 > "$FAKE_GH/blocked/10"
  cd "$REPO" && git init -q -b main && git config user.email t@t && git config user.name t && git commit -q --allow-empty -m base
}
issue() { # number title state labels [body]
  jq -n --argjson n "$1" --arg t "$2" --arg s "$3" --argjson l "$4" --arg b "${5:-}" \
    '{number: $n, id: (1000 + $n), node_id: "I_\($n)", title: $t, state: $s, body: $b, labels: ($l | map({name: .})),
      milestone: {number: 1, title: "S20"}, assignees: [], created_at: "2026-10-05T09:00:00Z", closed_at: null}' > "$FAKE_GH/issues/$1.json"
}
st() { "$ROOT/bin/status.sh" --repo "$REPO" "$@"; }
R() { mkdir -p "$REPO/.compasso/runs/$1"; echo "$REPO/.compasso/runs/$1"; }

@test "sprint: what can be built, what waits and on whom, and the features" {
  run st --milestone S20
  [ "$status" -eq 0 ]
  [[ "$output" == *"Build now: #11 Year filter"* ]] || false
  [[ "$output" == *"Waiting: #9 on #11"* ]] || false
  [[ "$output" == *"Blocked: #10 by #13 Credentials (@ana)"* ]] || false
  [[ "$output" == *"Features: #6 Invoice history 1/4 done"* ]] || false
}

@test "status changes nothing on the tracker, not even a stale label" {
  st --milestone S20 >/dev/null
  st --iid 11 >/dev/null
  [ "$(grep -cE '^(POST|PATCH|PUT|DELETE)|ITEM' "$FAKE_GH/calls.log" || true)" -eq 0 ]
  [ "$(jq -c '[.labels[].name]' "$FAKE_GH/issues/8.json")" = '["owner::agent","compasso::in-review"]' ]
}

@test "sprint: the plan on the default branch, as of the last fetch" {
  cp "$ROOT/tests/fixtures/plan.yaml" .compasso/plan.yaml
  [[ "$(st)" == *"Plan: not on the default branch (main"* ]] || false
  git init -q --bare -b main "$BATS_TEST_TMPDIR/origin.git" && git remote add origin "$BATS_TEST_TMPDIR/origin.git"
  git add .compasso/plan.yaml && git commit -qm plan && git push -q origin main && git remote set-head origin main
  [[ "$(st)" == *"Plan: on the default branch (main"* ]] || false
  echo "# re-planned" >> .compasso/plan.yaml
  [[ "$(st)" == *"Plan: changed since the default branch"* ]] || false
}

@test "sprint: counts Verify commands not approved on this machine" {
  cp "$ROOT/tests/fixtures/plan.yaml" .compasso/plan.yaml
  [[ "$(st)" == *"Verify commands not approved here: 4"* ]] || false
  "$ROOT/bin/trust.sh" approve --repo "$REPO" --plan >/dev/null
  [[ "$(st)" != *"not approved"* ]] || false
}

@test "a story run's stage and next step come from the files it left" {
  d="$(R 11)"; echo '{}' > "$d/story.json"
  [ "$(st --iid 11 --json | jq -r .run.stage)" = "story read" ]
  : > "$d/test-hashes"
  [ "$(st --iid 11 --json | jq -r .run.next)" = "step 5: build" ]
  echo '[{"status":"fail"},{"status":"pass"}]' > "$d/verify.json"
  [ "$(st --iid 11 --json | jq -r .run.stage)" = "verify failing (1 of 2 commands)" ]
  for i in 1 2 3; do echo '{"type":"verify-fail"}' >> "$d/events.jsonl"; done
  [ "$(st --iid 11 --json | jq -r .run.next)" = "hand back: a person decides" ]
  echo '[{"status":"pass"},{"status":"pass"}]' > "$d/verify.json"; echo '{}' > "$d/coverage.json"
  [ "$(st --iid 11 --json | jq -r .run.next)" = "step 7: review and security review" ]
  echo '[{"by":"reviewer","severity":"major","status":"open","summary":"x"}]' > "$d/findings.json"; echo '{"type":"round"}' >> "$d/events.jsonl"
  [ "$(st --iid 11 --json | jq -r .run.stage)" = "review round 1: 1 open blocker or major" ]
  echo '{"type":"round"}' >> "$d/events.jsonl"; echo '{"type":"round"}' >> "$d/events.jsonl"
  [[ "$(st --iid 11 --json | jq -r .run.stage)" == "review still blocked after 3 rounds"* ]] || false
  echo '[{"by":"reviewer","severity":"major","status":"fixed","summary":"x"}]' > "$d/findings.json"
  [ "$(st --iid 11 --json | jq -r .run.next)" = "step 8: ship" ]
  echo "- change" > "$d/changes.md"; mkdir -p .compasso/metrics && echo '{}' > .compasso/metrics/11.json
  [ "$(st --iid 11 --json | jq -r .run.next)" = "step 9: push the branch and open the merge request" ]
  echo body > "$d/mr.md"
  [ "$(st --iid 11 --json | jq -r .run.step)" = 9 ]
  issue 11 "Year filter" open '["owner::agent","compasso::in-review"]' '**Verify:** x'
  [ "$(st --iid 11 --json | jq -r .run.stage)" = "merge request open, in review" ]
}

@test "story: dependencies, owner and what to do next" {
  run st --iid 10
  [ "$status" -eq 0 ]
  [[ "$output" == *"Waits on: #13 Credentials (blocker)"* ]] || false
  [[ "$output" == *"Next: wait for #13 to close"* ]] || false
  run st --iid 11
  [[ "$output" == *"State: new"*"owner agent"* ]] || false
  [[ "$output" == *"Next: /compasso:story 11"* ]] || false
  run st --iid 8
  [[ "$output" == *"Next: nothing: the story is closed"* ]] || false
}

@test "sprint: local runs are listed with their stage" {
  d="$(R 11)"; echo '{}' > "$d/story.json"; : > "$d/test-hashes"
  mkdir -p .compasso/runs/plan-S20
  run st --milestone S20
  [[ "$output" == *"Local runs:"*"#11 failing tests written and committed → step 5: build"* ]] || false
  [[ "$output" != *"plan-S20"* ]] || false
}

@test "when the tracker cannot be read, the local part is still shown and it exits 1" {
  d="$(R 11)"; echo '{}' > "$d/story.json"
  export FAKE_GH_FAIL='GET user'
  run st --milestone S20
  [ "$status" -eq 1 ]
  [[ "$output" == *"Tracker: github: not logged in"* ]] || false
  [[ "$output" == *"#11 story read"* ]] || false
}

@test "--json is one JSON document" {
  run st --milestone S20 --json
  [ "$(jq -c '[.milestone, (.tracker.runnable | map(.iid))]' <<<"$output")" = '["S20",[11]]' ]
}
