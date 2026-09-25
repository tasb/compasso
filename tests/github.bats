#!/usr/bin/env bats
load helper

# acme/app on GitHub with Project 7 (Estimate (h), Iteration, Status); the plan fixture
# has features F-1, F-2, stories S-1..S-4 (S-4 depends on #12 and is blocked by B-1).
setup() {
  setup_repo
  cfg_set '.tracker.provider = "github" | .tracker.host = "github.com" | .tracker.github.project = 7'
  PLAN="$REPO/.compasso/plan.yaml"
  cp "$ROOT/tests/fixtures/plan.yaml" "$PLAN"
  export FAKE_GH="$BATS_TEST_TMPDIR/gh"; mkdir -p "$FAKE_GH"/{issues,parent,blocked,est,status,events,closing}; : > "$FAKE_GH/calls.log"
  export PATH="$ROOT/tests/fake:$PATH"
  echo 20 > "$FAKE_GH/next_number"
  issue 12 "Old work" open '[]' ''
  cat > "$FAKE_GH/project.json" <<'EOF'
{"id": "PVT_7", "fields": {"nodes": [
  {"id": "F_EST", "name": "Estimate (h)", "dataType": "NUMBER"},
  {"id": "F_ITER", "name": "Iteration", "dataType": "ITERATION",
   "configuration": {"duration": 14, "startDay": 1, "iterations": [{"id": "IT_S19", "title": "S19", "startDate": "2026-09-21", "duration": 14}], "completedIterations": []}},
  {"id": "F_STATUS", "name": "Status", "dataType": "SINGLE_SELECT",
   "options": [{"id": "O_TODO", "name": "Todo"}, {"id": "O_PROG", "name": "In progress"}, {"id": "O_REV", "name": "In review"}, {"id": "O_DONE", "name": "Done"}]}]}}
EOF
}
issue() { # number title state labels-json body [milestone-number]
  jq -n --argjson n "$1" --arg t "$2" --arg s "$3" --argjson l "$4" --arg b "$5" --arg m "${6:-}" \
    '{number: $n, id: (1000 + $n), node_id: "I_\($n)", title: $t, state: $s, body: $b, labels: ($l | map({name: .})),
      milestone: (if $m == "" then null else {number: ($m | tonumber), title: "S20"} end), assignees: [],
      created_at: "2026-10-05T09:00:00Z", closed_at: (if $s == "closed" then "2026-10-07T09:00:00Z" else null end)}' > "$FAKE_GH/issues/$1.json"
}
gh_() { "$ROOT/bin/tracker/github.sh" "$@" --repo "$REPO"; }
calls() { grep -c -- "$1" "$FAKE_GH/calls.log" || true; }
num() { K="$1" yq -r '(.features[] | select(.key == strenv(K)) | .gitlab), (.blockers[] | select(.key == strenv(K)) | .gitlab), (.features[].stories[] | select(.key == strenv(K)) | .gitlab)' "$PLAN"; }
labels_of() { jq -c '[.labels[].name] | sort' "$FAKE_GH/issues/$1.json"; }

# ---------- dispatch and check ----------

@test "tracker.sh sends a GitHub project to the GitHub adapter" {
  run "$ROOT/bin/tracker.sh" check --repo "$REPO"
  [ "$status" -eq 0 ]
  [ "$(jq -r .tier <<<"$output")" = github ]
  [ "$(jq -c '.capabilities | [.github_project, .code_scanning, .secret_scanning]' <<<"$output")" = "[true,true,true]" ]
}

@test "check: no push access is refused" {
  echo '{"id":7,"visibility":"public","permissions":{"push":false}}' > "$FAKE_GH/repo.json"
  run gh_ check
  [ "$status" -eq 4 ]
  [[ "$output" == *"cannot push to acme/app"* ]] || false
}

@test "check: a private repository without Advanced Security has no GitHub code scanning" {
  echo '{"id":7,"visibility":"private","permissions":{"push":true}}' > "$FAKE_GH/repo.json"
  [ "$(gh_ check | jq .capabilities.code_scanning)" = false ]
}

@test "check: a configured Project that cannot be read is an error" {
  rm "$FAKE_GH/project.json"
  run gh_ check
  [ "$status" -eq 3 ]
  [[ "$output" == *"Project 7 of acme is not reachable"* ]] || false
}

@test "ensure-labels: creates the missing labels once, colours without #" {
  echo "compasso::new" > "$FAKE_GH/labels.txt"
  run gh_ ensure-labels
  [ "$status" -eq 0 ]
  [ "$(calls 'POST repos/acme/app/labels')" -eq $(( $(wc -l < "$ROOT/bin/tracker/labels.txt") - 1 )) ]
  [ "$(calls 'color=#')" -eq 0 ]
  gh_ ensure-labels >/dev/null
  [ "$(calls 'POST repos/acme/app/labels')" -eq $(( $(wc -l < "$ROOT/bin/tracker/labels.txt") - 1 )) ]
}

# ---------- push-plan ----------

@test "push-plan: milestone, epic, features and stories, with every number written back" {
  run gh_ push-plan
  [ "$status" -eq 0 ]
  [ "$(jq -c '[.[].title]' "$FAKE_GH/milestones.json")" = '["S20"]' ]
  grep -q "POST repos/acme/app/milestones title=S20 due_on=2026-10-16T23:59:59Z" "$FAKE_GH/calls.log"
  for k in F-1 F-2 B-1 S-1 S-2 S-3 S-4; do [ "$(num $k)" != null ]; done
  [ "$(labels_of "$(yq .epic.gitlab.issue "$PLAN")")" = '["type::epic"]' ]
  [ "$(labels_of "$(num F-1)")" = '["type::feature"]' ]
  [ "$(labels_of "$(num S-4)")" = '["blocked","owner::agent"]' ]
  [ "$(labels_of "$(num B-1)")" = '["priority::urgent","type::blocker"]' ]
  [ "$(jq -r .milestone.title "$FAKE_GH/issues/$(num S-1).json")" = S20 ]
}

@test "push-plan: features are sub-issues of the epic, stories of their feature, blockers of neither" {
  gh_ push-plan >/dev/null
  [ "$(cat "$FAKE_GH/parent/$(num F-1)")" = "$(yq .epic.gitlab.issue "$PLAN")" ]
  [ "$(cat "$FAKE_GH/parent/$(num S-3)")" = "$(num F-1)" ]
  [ "$(cat "$FAKE_GH/parent/$(num S-4)")" = "$(num F-2)" ]
  [ ! -e "$FAKE_GH/parent/$(num B-1)" ]
}

@test "push-plan: dependencies and blockers are GitHub's native blocked-by, not description lines" {
  gh_ push-plan >/dev/null
  [ "$(cat "$FAKE_GH/blocked/$(num S-2)")" = "$(num S-1)" ]
  [ "$(sort "$FAKE_GH/blocked/$(num S-4)" | paste -sd, -)" = "$(printf '%s\n' 12 "$(num B-1)" | sort | paste -sd, -)" ]
  [ "$(jq -r .body "$FAKE_GH/issues/$(num S-2).json" | grep -c 'Depends on' || true)" -eq 0 ]
  jq -r .body "$FAKE_GH/issues/$(num S-4).json" | grep -q "^\*\*Blocked by:\*\* #$(num B-1)"
}

@test "push-plan: the blocker is assigned; an assignee who cannot be assigned stops the push" {
  gh_ push-plan >/dev/null
  [ "$(jq -r '.assignees[0].login' "$FAKE_GH/issues/$(num B-1).json")" = ana ]
  jq -r .body "$FAKE_GH/issues/$(num B-1).json" | grep -q "#$(num S-4)"
  yq -i '.blockers[0].assignee = "ghost"' "$PLAN"
  run gh_ push-plan
  [ "$status" -eq 1 ]
  [[ "$output" == *"ghost cannot be assigned blocker B-1"* ]] || false
}

@test "push-plan: every item joins the Project in iteration S20, stories with their estimate and Todo" {
  gh_ push-plan >/dev/null
  grep -q 'FIELD iterations \["S19","S20"\]' "$FAKE_GH/calls.log"
  [ "$(calls "ITEM set #$(num S-1) F_ITER iterationId: \"IT_S20\"")" -eq 1 ]
  [ "$(calls "ITEM set #$(num F-1) F_ITER")" -eq 1 ]
  [ "$(cat "$FAKE_GH/est/$(num S-4)")" = 8 ]
  [ "$(cat "$FAKE_GH/status/$(num S-1)")" = O_TODO ]
  [ ! -e "$FAKE_GH/est/$(num F-1)" ]
}

@test "push-plan: a second push creates nothing, keeps states and does not add the iteration again" {
  gh_ push-plan >/dev/null
  : > "$FAKE_GH/calls.log"
  run gh_ push-plan
  [ "$status" -eq 0 ]
  [ "$(calls 'POST repos/acme/app/issues ')" -eq 0 ]
  [ "$(calls 'POST repos/acme/app/milestones')" -eq 0 ]
  [ "$(calls 'sub_issues')" -eq 0 ]
  [ "$(calls 'POST repos/acme/app/issues/[0-9]*/dependencies')" -eq 0 ]
  [ "$(calls 'FIELD iterations')" -eq 0 ]
  [ "$(calls 'F_STATUS')" -eq 0 ]
}

@test "push-plan: an owner change drops the old owner label" {
  gh_ push-plan >/dev/null
  yq -i '(.features[0].stories[0].owner) = "human"' "$PLAN"
  gh_ push-plan >/dev/null
  [ "$(labels_of "$(num S-1)")" = '["owner::human"]' ]
}

@test "push-plan: without a Project, nothing touches Projects" {
  cfg_set '.tracker.github.project = 0'
  run gh_ push-plan
  [ "$status" -eq 0 ]
  [ "$(calls ITEM)" -eq 0 ]
  [ "$(calls graphql)" -eq 0 ]
}

# ---------- story ----------

story_fixture() {
  issue 6 "Invoice history" open '["type::feature"]' $'**Goal:** g\\\n**Coverage:** 85%' 1
  issue 8 "Invoice list API" open '["owner::agent"]' $'**As** a customer **I want** a list **so that** I see history.\n\n## Acceptance\n- [ ] Given 3, When GET, Then 3\n\n## Verify\n- `npm test`\n\n**Tests:** unit, e2e\n\n<!-- compasso:key=S-1 -->' 1
  issue 3 "Done dep" closed '[]' ''
  issue 4 "Open dep" open '[]' ''
  issue 13 "Credentials" open '["type::blocker"]' ''
  issue 30 "S20: goal" open '["type::epic"]' '**Coverage:** 70%' 1
  echo '[{"number":1,"title":"S20"}]' > "$FAKE_GH/milestones.json"
  echo 6 > "$FAKE_GH/parent/8"; mkdir -p "$FAKE_GH/blocked"; printf '3\n4\n13\n' > "$FAKE_GH/blocked/8"
  echo 5.5 > "$FAKE_GH/est/8"
}

@test "story: the GitLab shape, with feature, epic, estimate and native dependencies" {
  story_fixture
  run gh_ story --iid 8
  [ "$status" -eq 0 ]
  [ "$(jq -c '[.iid, .state, .type, .feature, .epic, .estimate_h, .milestone]' <<<"$output")" = '[8,"opened","task",6,30,5.5,"S20"]' ]
  [ "$(jq -c '[.story.depends_on, .story.blocked_by, .story.tests]' <<<"$output")" = '[[3,4],[13],["unit","e2e"]]' ]
  [ "$(jq -c '.open_dependencies | map([.iid, .kind])' <<<"$output")" = '[[4,"depends_on"],[13,"blocked_by"]]' ]
  [ "$(jq .coverage_min <<<"$output")" = 85 ]
}

@test "story: an unknown issue is an error" {
  run gh_ story --iid 99
  [ "$status" -eq 1 ]
  [[ "$output" == *"no work item #99"* ]] || false
}

# ---------- set-state ----------

@test "set-state: one compasso state label, and the Project status follows" {
  issue 8 "t" open '["owner::agent","compasso::new"]' ''
  run gh_ set-state --iid 8 --state in-review
  [ "$status" -eq 0 ]
  [ "$(labels_of 8)" = '["compasso::in-review","owner::agent"]' ]
  [ "$(cat "$FAKE_GH/status/8")" = O_REV ]
}

@test "set-state: a state with no Status option only changes the label; an unknown state is refused" {
  issue 8 "t" open '[]' ''
  gh_ set-state --iid 8 --state verifying >/dev/null
  [ "$(labels_of 8)" = '["compasso::verifying"]' ]
  [ "$(calls F_STATUS)" -eq 0 ]
  run gh_ set-state --iid 8 --state shipped
  [ "$status" -eq 1 ]
}

# ---------- pull requests ----------

@test "open-mr: a pull request to the default branch, or to --target when stacked" {
  issue 8 "Invoice list API" open '[]' ''
  echo "Closes #8" > "$BATS_TEST_TMPDIR/b.md"
  run gh_ open-mr --iid 8 --branch story/8-list --body-file "$BATS_TEST_TMPDIR/b.md"
  [ "$status" -eq 0 ]
  [ "$(jq -c . <<<"$output")" = '{"iid":31,"web_url":"https://github.com/acme/app/pull/31"}' ]
  grep -q "POST repos/acme/app/pulls head=story/8-list base=main title=Invoice list API" "$FAKE_GH/calls.log"
  gh_ open-mr --iid 8 --branch story/9-next --body-file "$BATS_TEST_TMPDIR/b.md" --target story/8-list >/dev/null
  grep -q "head=story/9-next base=story/8-list" "$FAKE_GH/calls.log"
}

@test "open-mr: updates the branch's open pull request instead of opening another" {
  issue 8 "t" open '[]' ''
  echo '[{"number":40}]' > "$FAKE_GH/pr-query.json"
  echo "Closes #8" > "$BATS_TEST_TMPDIR/b.md"
  [ "$(gh_ open-mr --iid 8 --branch story/8-list --body-file "$BATS_TEST_TMPDIR/b.md" | jq .iid)" = 40 ]
  [ "$(calls 'POST repos/acme/app/pulls')" -eq 0 ]
}

@test "followup: a sub-issue of the parent, in its milestone unless --milestone none" {
  issue 6 "Feature" open '["type::feature"]' '' 1
  echo '[{"number":1,"title":"S20"}]' > "$FAKE_GH/milestones.json"
  echo "x" > "$BATS_TEST_TMPDIR/f.md"
  n="$(gh_ followup --parent 6 --title "Rename helper" --body-file "$BATS_TEST_TMPDIR/f.md")"
  [ "$(cat "$FAKE_GH/parent/$n")" = 6 ]
  [ "$(labels_of "$n")" = '["owner::either"]' ]
  [ "$(jq -r .milestone.title "$FAKE_GH/issues/$n.json")" = S20 ]
  n="$(gh_ followup --parent 6 --title "Later" --body-file "$BATS_TEST_TMPDIR/f.md" --milestone none --labels type::bug,severity::minor)"
  [ "$(jq -r .milestone "$FAKE_GH/issues/$n.json")" = null ]
  [ "$(labels_of "$n")" = '["severity::minor","type::bug"]' ]
}

@test "merge: refused while a person merges; an open security finding always stops an agent" {
  echo '[]' > "$BATS_TEST_TMPDIR/f.json"
  run gh_ merge --mr 31 --body-file "$BATS_TEST_TMPDIR/f.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"a person merges"* ]] || false
  cfg_set '.approvals.merge = "agent"'
  echo '[{"by":"security","severity":"minor","status":"open","summary":"x"}]' > "$BATS_TEST_TMPDIR/f.json"
  run gh_ merge --mr 31 --body-file "$BATS_TEST_TMPDIR/f.json"
  [ "$status" -eq 1 ]
  [ "$(calls 'PR merge')" -eq 0 ]
}

@test "merge: an agent labels the pull request and turns on auto-merge" {
  cfg_set '.approvals.merge = "agent"'
  issue 31 "PR" open '[]' ''
  echo '[]' > "$BATS_TEST_TMPDIR/f.json"
  run gh_ merge --mr 31 --body-file "$BATS_TEST_TMPDIR/f.json"
  [ "$status" -eq 0 ]
  [ "$(labels_of 31)" = '["compasso::auto-merged"]' ]
  grep -q "PR merge 31 --repo github.com/acme/app --auto --merge" "$FAKE_GH/calls.log"
}

@test "merge: with approvals.merge risk, a high-risk change is left to a person" {
  cfg_set '.approvals.merge = "risk"'
  echo '[]' > "$BATS_TEST_TMPDIR/f.json"; echo '{"level":"high"}' > "$BATS_TEST_TMPDIR/r.json"
  run gh_ merge --mr 31 --body-file "$BATS_TEST_TMPDIR/f.json" --risk "$BATS_TEST_TMPDIR/r.json"
  [ "$status" -eq 1 ]
  [ "$(calls 'PR merge')" -eq 0 ]
}

@test "mr-info: the GitLab shape, with the issues it closes" {
  echo '{"number":31,"title":"t","state":"MERGED","url":"u","isDraft":false,"headRefName":"feat","baseRefName":"main","author":{"login":"ana"},"closingIssuesReferences":{"nodes":[{"number":8}]}}' > "$FAKE_GH/pr-31.json"
  run gh_ mr-info --mr 31
  [ "$status" -eq 0 ]
  [ "$(jq -c '[.state, .source_branch, .target_branch, .author, .closes]' <<<"$output")" = '["merged","feat","main","ana",[8]]' ]
  run gh_ mr-info --mr 32
  [ "$status" -eq 1 ]
}

@test "comment: pull requests and issues both take issue comments" {
  echo "hi" > "$BATS_TEST_TMPDIR/c.md"
  gh_ comment --mr 31 --body-file "$BATS_TEST_TMPDIR/c.md" >/dev/null
  gh_ comment --iid 8 --body-file "$BATS_TEST_TMPDIR/c.md" >/dev/null
  [ "$(calls 'POST repos/acme/app/issues/31/comments')" -eq 1 ]
  [ "$(calls 'POST repos/acme/app/issues/8/comments')" -eq 1 ]
}

@test "merge-commit and open-mr-branch come from the pull requests that close the story" {
  mkdir -p "$FAKE_GH/closing"
  echo '[{"number":30,"state":"CLOSED","merged":false,"headRefName":"old","mergeCommit":null},{"number":31,"state":"MERGED","merged":true,"headRefName":"story/8","mergeCommit":{"oid":"abc123"}},{"number":32,"state":"OPEN","merged":false,"headRefName":"story/8-fix","mergeCommit":null}]' > "$FAKE_GH/closing/8.json"
  [ "$(gh_ merge-commit --iid 8)" = abc123 ]
  [ "$(gh_ open-mr-branch --iid 8)" = story/8-fix ]
  run gh_ merge-commit --iid 9
  [ "$status" -eq 1 ]
  run gh_ open-mr-branch --iid 9
  [ "$status" -eq 1 ]
}

@test "digest: merged auto-merged pull requests since a date" {
  echo '{"items":[{"number":31,"title":"Invoice list","pull_request":{"merged_at":"2026-10-06T10:30:00Z"}}]}' > "$FAKE_GH/search.json"
  run gh_ digest --since 2026-10-06
  [ "$status" -eq 0 ]
  [[ "$output" == *"- #31 Invoice list · merged 2026-10-06 10:30"* ]] || false
  grep -q "q=repo:acme/app is:pr is:merged label:compasso::auto-merged merged:>=2026-10-06" "$FAKE_GH/calls.log"
}

# ---------- sprint ----------

sprint_fixture() {
  echo '[{"number":1,"title":"S20"}]' > "$FAKE_GH/milestones.json"
  issue 6 "Invoice history" open '["type::feature"]' '**Goal:** g' 1
  issue 30 "S20: goal" open '["type::epic"]' '**Goal:** g' 1
  issue 8 "List API" closed '["compasso::in-review","owner::agent"]' '**Tests:** unit' 1
  issue 11 "Year filter" open '["owner::either"]' '**Tests:** unit' 1
  issue 9 "PDF" open '["owner::agent","blocked"]' '**Tests:** unit' 1
  issue 13 "Credentials" open '["type::blocker","priority::urgent"]' '## Steps' 1
  for n in 8 11 9; do echo 6 > "$FAKE_GH/parent/$n"; done
  mkdir -p "$FAKE_GH/blocked"; echo 8 > "$FAKE_GH/blocked/11"; echo 13 > "$FAKE_GH/blocked/9"
  echo 4 > "$FAKE_GH/est/8"; echo 2.5 > "$FAKE_GH/est/11"; echo 3 > "$FAKE_GH/est/13"
}

@test "sprint-sync: native blocked-by drives runnable and blocked, and closed stories lose in-progress labels" {
  sprint_fixture
  run gh_ sprint-sync --milestone S20
  [ "$status" -eq 0 ]
  [ "$(jq -c '[.runnable[].iid]' <<<"$output")" = '[11]' ]
  [ "$(jq -c '[.blocked[].iid]' <<<"$output")" = '[9]' ]
  [ "$(labels_of 8)" = '["owner::agent"]' ]
}

@test "sprint-items and sprint-done: label history in the GitLab shape, and hours done" {
  sprint_fixture
  mkdir -p "$FAKE_GH/events"
  echo '[{"event":"labeled","label":{"name":"compasso::building"},"created_at":"2026-10-06T09:00:00Z"},{"event":"closed","created_at":"2026-10-07T09:00:00Z"}]' > "$FAKE_GH/events/8.json"
  run gh_ sprint-items --milestone S20
  [ "$status" -eq 0 ]
  [ "$(jq -c '.[] | select(.iid == 8) | [.state, .time_stats.time_estimate, .label_events]' <<<"$output")" = '["closed",14400,[{"action":"add","label":{"name":"compasso::building"},"created_at":"2026-10-06T09:00:00Z"}]]' ]
  [ "$(gh_ sprint-done --milestone S20)" = 4 ]
  [ "$(gh_ sprint-done --milestone S99)" = null ]
}

# ---------- protect ----------

workflow() { cfg_set '.ci.image = "node:22" | .commands.test = "npm test"'"${1:-}"; "$ROOT/bin/ci.sh" --repo "$REPO" >/dev/null; }

@test "protect: needs the workflow first, so required checks exist" {
  run gh_ protect
  [ "$status" -eq 1 ]
  [[ "$output" == *"run bin/ci.sh first"* ]] || false
}

@test "protect: pull requests only, the workflow's gates required, CodeQL on a public repository, auto-merge on" {
  workflow ' | .commands.e2e = "npx playwright test" | .coverage.command = "npm run cov" | .coverage.report = "coverage.xml"'
  run gh_ protect
  [ "$status" -eq 0 ]
  grep -q "PATCH repos/acme/app allow_auto_merge=true delete_branch_on_merge=true" "$FAKE_GH/calls.log"
  grep -q "PATCH repos/acme/app/code-scanning/default-setup state=configured" "$FAKE_GH/calls.log"
  [ "$(jq -c '[.rules[].type]' "$FAKE_GH/ruleset.json")" = '["deletion","non_fast_forward","pull_request","required_status_checks","code_scanning"]' ]
  [ "$(jq -c '[.rules[] | select(.type == "required_status_checks") | .parameters.required_status_checks[].context]' "$FAKE_GH/ruleset.json")" = '["compasso-verify","compasso-e2e"]' ]
  [ "$(jq '.rules[] | select(.type == "pull_request") | .parameters.required_approving_review_count' "$FAKE_GH/ruleset.json")" = 0 ]
}

@test "protect: without GitHub code scanning the scan gate is required and there is no CodeQL rule; an existing ruleset is updated" {
  echo '{"id":7,"visibility":"private","permissions":{"push":true}}' > "$FAKE_GH/repo.json"
  echo '[{"id":5,"name":"compasso"}]' > "$FAKE_GH/rulesets.json"
  workflow
  gh_ protect >/dev/null
  [ "$(calls code-scanning)" -eq 0 ]
  [ "$(calls 'PUT repos/acme/app/rulesets/5')" -eq 1 ]
  [ "$(jq -c '[.rules[].type] | index("code_scanning")' "$FAKE_GH/ruleset.json")" = null ]
  [ "$(jq -c '[.rules[] | select(.type == "required_status_checks") | .parameters.required_status_checks[].context]' "$FAKE_GH/ruleset.json")" = '["compasso-verify","compasso-scan-gate"]' ]
}

@test "protect: when CodeQL cannot be set up yet, its rule is left out so pull requests are not stuck waiting" {
  workflow
  export FAKE_GH_FAIL='PATCH repos/acme/app/code-scanning/default-setup'
  run gh_ protect
  [ "$status" -eq 0 ]
  [[ "$output" == *"run protect again later"* ]] || false
  [ "$(jq -c '[.rules[].type] | index("code_scanning")' "$FAKE_GH/ruleset.json")" = null ]
}

@test "check: a failing login call is not logged in, even though gh prints the error body" {
  export FAKE_GH_FAIL='GET user'
  run gh_ check
  [ "$status" -eq 2 ]
  [[ "$output" == *"not logged in"* ]] || false
}

# ---------- push-backlog ----------

@test "push-backlog: features become issues in no sprint, MVP labelled, numbers written back" {
  cp "$ROOT/tests/fixtures/backlog.yaml" "$REPO/.compasso/backlog.yaml"
  run gh_ push-backlog
  [ "$status" -eq 0 ]
  n="$(yq '.features[1].gitlab' "$REPO/.compasso/backlog.yaml")"
  [ "$n" != null ]
  [ "$(labels_of "$n")" = '["mvp","type::feature"]' ]
  [ "$(jq -r .milestone "$FAKE_GH/issues/$n.json")" = null ]
  [ "$(labels_of "$(yq '.features[4].gitlab' "$REPO/.compasso/backlog.yaml")")" = '["type::feature"]' ]
  [ "$(calls 'milestones')" -eq 0 ]
}

@test "push-backlog: a second push creates nothing; a feature moved below the MVP line loses the label" {
  cp "$ROOT/tests/fixtures/backlog.yaml" "$REPO/.compasso/backlog.yaml"
  gh_ push-backlog >/dev/null
  : > "$FAKE_GH/calls.log"
  yq -i '.features[2].mvp = false | .features[3].mvp = false' "$REPO/.compasso/backlog.yaml"
  gh_ push-backlog >/dev/null
  [ "$(calls 'POST repos/acme/app/issues ')" -eq 0 ]
  [ "$(labels_of "$(yq '.features[2].gitlab' "$REPO/.compasso/backlog.yaml")")" = '["type::feature"]' ]
}

@test "push-backlog: a backlog feature planned into a sprint keeps its issue and joins the sprint" {
  cp "$ROOT/tests/fixtures/backlog.yaml" "$REPO/.compasso/backlog.yaml"
  gh_ push-backlog >/dev/null
  n="$(yq '.features[1].gitlab' "$REPO/.compasso/backlog.yaml")"
  N="$n" yq -i '.features[0].gitlab = (strenv(N) | tonumber)' "$PLAN"
  gh_ push-plan >/dev/null
  [ "$(jq -r .milestone.title "$FAKE_GH/issues/$n.json")" = S20 ]
  [ "$(cat "$FAKE_GH/parent/$n")" = "$(yq .epic.gitlab.issue "$PLAN")" ]
  [ "$(num F-1)" = "$n" ]
}

@test "push-backlog: refused while the backlog does not pass its check" {
  cp "$ROOT/tests/fixtures/backlog.yaml" "$REPO/.compasso/backlog.yaml"
  yq -i '.features[0].size_h = 0' "$REPO/.compasso/backlog.yaml"
  run gh_ push-backlog
  [ "$status" -eq 1 ]
  [ "$(calls 'POST repos/acme/app/issues')" -eq 0 ]
}
