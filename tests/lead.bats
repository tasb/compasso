#!/usr/bin/env bats
load helper

# The tech lead merges (team projects). GitHub fake; a real git origin holds main and rui's branch
# story/14-status, whose pull request #31 closes story #14 (in review). The lead works in $REPO,
# rui in $RUI. rui's run posted its findings report on #31; maria is a person, bot1 an agent.
setup() {
  setup_repo
  cfg_set '.tracker.provider = "github" | .tracker.host = "github.com" | .team.enabled = true | .stage = "mvp" | .team.agents = ["bot1"]'
  export FAKE_GH="$BATS_TEST_TMPDIR/gh"; mkdir -p "$FAKE_GH"/{issues,parent,blocked,comments,closing,reviews}; : > "$FAKE_GH/calls.log"
  export PATH="$ROOT/tests/fake:$PATH"
  echo '[{"number":1,"title":"S20"}]' > "$FAKE_GH/milestones.json"
  printf 'dev::ana\ndev::rui\nneeds::lead\nneeds::approval\ncompasso::backlog\n' > "$FAKE_GH/labels.txt"
  cd "$REPO" && git init -q -b main && git config user.email t@t && git config user.name t
  printf '.compasso/runs/\n' > .gitignore && mkdir -p src && echo a > src/a.js && git add -A && git commit -qm base
  ORIGIN="$BATS_TEST_TMPDIR/origin.git"; git clone -q --bare "$REPO" "$ORIGIN"; git remote add origin "$ORIGIN"
  git checkout -q -b story/14-status && printf '1\n2\n3\n' > src/status.js && git add -A && git commit -qm "status filter"
  git push -q origin story/14-status && git checkout -q main && git branch -q -D story/14-status
  RUI="$BATS_TEST_TMPDIR/rui"; mkdir -p "$RUI"; cp -R "$REPO/.compasso" "$RUI/"
  "$ROOT/bin/persona.sh" set --repo "$REPO" --persona tech-lead >/dev/null
  "$ROOT/bin/persona.sh" set --repo "$RUI" --persona developer --name rui >/dev/null
  issue 6 "Invoice history" '["type::feature"]' '**Goal:** g'
  issue 14 "Status filter" '["dev::rui","compasso::in-review"]' $'**Tests:** unit' 6
  issue 31 "Status filter" '[]' 'Closes #14'   # the pull request: GitHub keeps its labels and comments as an issue's
  jq '.pull_request = {}' "$FAKE_GH/issues/31.json" > "$FAKE_GH/tmp" && mv "$FAKE_GH/tmp" "$FAKE_GH/issues/31.json"
  echo '[{"number":31,"state":"OPEN","merged":false,"headRefName":"story/14-status","baseRefName":"main","url":"https://github.com/acme/app/pull/31","mergeCommit":null}]' > "$FAKE_GH/closing/14.json"
  RUN="$BATS_TEST_TMPDIR/run"; mkdir -p "$RUN"
  echo '[{"by":"security","severity":"minor","status":"fixed","verified_by":"security","summary":"verbose error"}]' > "$RUN/findings.json"
  echo '{"status":"ok","percent":100,"min":80}' > "$RUN/coverage.json"
  "$ROOT/bin/mr-report.sh" post --repo "$RUI" --run "$RUN" --mr 31 >/dev/null
}
issue() { # number title labels-json body [parent]
  jq -n --argjson n "$1" --arg t "$2" --argjson l "$3" --arg b "$4" \
    '{number: $n, id: (1000 + $n), node_id: "I_\($n)", title: $t, state: "open", body: $b, labels: ($l | map({name: .})),
      milestone: {number: 1, title: "S20"}, assignees: [], created_at: "2026-10-05T09:00:00Z", closed_at: null}' > "$FAKE_GH/issues/$1.json"
  [ -z "${5:-}" ] || echo "$5" > "$FAKE_GH/parent/$1"
}
team() { local r="$1"; shift; "$ROOT/bin/team.sh" "$@" --repo "$r"; }
labels_of() { jq -c '[.labels[].name] | sort' "$FAKE_GH/issues/$1.json"; }
review_() { team "$REPO" review --iid 14; }
reviews() { echo "$1" > "$FAKE_GH/reviews/31.json"; }
later() { # a person's review, after the lead asked
  reviews "$(jq -cn --arg s "$1" --arg u "$2" --arg b "${3:-}" '[{id: 7, state: $s, body: $b, user: {login: $u}, author_association: "MEMBER", submitted_at: "2026-10-07T09:00:00Z"}]')"
}

@test "review: reads the reports from the pull request and works out the risk from its branch; in mvp nothing waits for a person" {
  run review_
  [ "$status" -eq 0 ]
  [ "$(jq -c '[.mr, .branch, .reports.findings, .gate, .risk.level, .approval]' <<<"$output")" = '[31,"story/14-status",true,"clear","low","not-needed"]' ]
  [ "$(jq -c .infra <<<"$output")" = '[]' ]
  dir="$(jq -r .dir <<<"$output")"
  grep -q '^+++ b/src/status.js' "$dir/diff.patch"
  [ "$(jq .changed_lines "$dir/risk.json")" = 3 ]
  [ "$(jq -r .head <<<"$output")" = "$(git -C "$REPO" rev-parse origin/story/14-status)" ]
  echo '{"approves":true}' > "$dir/approver-x.json"
  review_ >/dev/null
  [ -f "$dir/approver-x.json" ]
}

@test "merge: the lead merges what needs no person, as merged without one" {
  run team "$REPO" merge --iid 14
  [ "$status" -eq 0 ]
  grep -q "^PR merge 31" "$FAKE_GH/calls.log"
  [ "$(labels_of 31)" = '["compasso::auto-merged"]' ]
}

@test "merge: refused without a findings report, with an unresolved security finding, or for an infrastructure change with no cost report" {
  echo '[]' > "$FAKE_GH/comments/31.json"
  run team "$REPO" merge --iid 14
  [ "$status" -eq 1 ]
  [[ "$output" == *"no findings report"* ]] || false
  echo '[{"by":"security","severity":"minor","status":"open","summary":"verbose error"}]' > "$RUN/findings.json"
  "$ROOT/bin/mr-report.sh" post --repo "$RUI" --run "$RUN" --mr 31 >/dev/null
  [ "$(review_ | jq -r .gate)" = blocked ]
  run team "$REPO" merge --iid 14
  [ "$status" -eq 1 ]
  [[ "$output" == *"open findings block the merge"* ]] || false
  ! grep -q "^PR merge" "$FAKE_GH/calls.log"
}

@test "merge: an infrastructure change needs its cost report, and a cost increase needs a person even in mvp" {
  git fetch -q origin story/14-status && git checkout -q -b story/14-status origin/story/14-status
  mkdir -p infra && echo 'resource "x" "y" {}' > infra/main.tf && git add -A && git commit -qm infra && git push -q origin story/14-status
  git checkout -q main
  run review_
  [ "$(jq -c '[.infra, .reports.cost, .approval]' <<<"$output")" = '[["infra/main.tf"],false,"needed"]' ]
  run team "$REPO" merge --iid 14
  [ "$status" -eq 1 ]
  [[ "$output" == *"no cost report"* ]] || false
  jq -n '{result: "increase", monthly_delta: 9, currency: "USD", resources: [], assumptions: [], sources: []}' > "$RUN/cost.json"
  "$ROOT/bin/mr-report.sh" post --repo "$RUI" --run "$RUN" --mr 31 >/dev/null
  run review_
  [ "$(jq -c '[.reports.cost, .approval]' <<<"$output")" = '[true,"needed"]' ]
  [[ "$(jq -r '.risk.reasons | join(" ")' <<<"$output")" == *"the cost report says increase"* ]] || false
  run team "$REPO" merge --iid 14
  [ "$status" -eq 1 ]
  [[ "$output" == *"a person approves it first"* ]] || false
}

@test "ask: in production a high-risk change gets needs::approval and a comment with the reasons" {
  cfg_set '.stage = "production" | .risk.max_changed_lines = 2'
  [ "$(review_ | jq -r .approval)" = needed ]
  run team "$REPO" ask --iid 14
  [ "$status" -eq 0 ]
  [ "$(labels_of 31)" = '["needs::approval"]' ]
  [ "$(jq -r 'last.body' "$FAKE_GH/comments/31.json" | head -1)" = "<!-- compasso:approval -->" ]
  [[ "$(jq -r 'last.body' "$FAKE_GH/comments/31.json")" == *"3 changed lines, over the 2-line limit"* ]] || false
  [ "$(review_ | jq -r .approval)" = asked ]
}

@test "ask: refused when nothing needs a person" {
  run team "$REPO" ask --iid 14
  [ "$status" -eq 1 ]
  [[ "$output" == *"needs no person"* ]] || false
}

@test "a person's approval lets the lead merge; an agent's never counts, nor one given before the lead asked" {
  cfg_set '.stage = "production" | .risk.max_changed_lines = 2'
  reviews '[{"id": 5, "state": "APPROVED", "body": "", "user": {"login": "maria"}, "author_association": "MEMBER", "submitted_at": "2026-10-01T09:00:00Z"}]'
  FAKE_GH_AT=2026-10-06T09:00:00Z team "$REPO" ask --iid 14 >/dev/null
  [ "$(review_ | jq -r .approval)" = asked ]
  later APPROVED bot1
  [ "$(review_ | jq -r .approval)" = asked ]
  run team "$REPO" merge --iid 14
  [ "$status" -eq 1 ]
  later APPROVED maria
  [ "$(review_ | jq -c '[.approval, .approved_by]')" = '["approved",["maria"]]' ]
  run team "$REPO" merge --iid 14
  [ "$status" -eq 0 ]
  grep -q "^PR merge 31" "$FAKE_GH/calls.log"
  [ "$(labels_of 31)" = '[]' ]
}

@test "a person's request for changes sends the story back to the same developer, on the same pull request" {
  cfg_set '.stage = "production" | .risk.max_changed_lines = 2'
  FAKE_GH_AT=2026-10-06T09:00:00Z team "$REPO" ask --iid 14 >/dev/null
  later CHANGES_REQUESTED maria "Show the status as a badge."
  run review_
  [ "$(jq -c '[.approval, .rejection.by, .rejection.text]' <<<"$output")" = '["rejected","maria","Show the status as a badge."]' ]
  printf 'maria asked for changes on #31: show the status as a badge.' > "$BATS_TEST_TMPDIR/m"
  run team "$REPO" return --iid 14 --body-file "$BATS_TEST_TMPDIR/m"
  [ "$status" -eq 0 ]
  [ "$(labels_of 14)" = '["compasso::backlog","dev::rui"]' ]
  [ "$(labels_of 31)" = '[]' ]
  [ "$(jq -r 'last.body' "$FAKE_GH/comments/14.json" | head -1)" = "<!-- compasso:msg from=lead to=rui -->" ]
}

@test "on GitHub a person's comment is not a rejection: only a request for changes is" {
  cfg_set '.stage = "production" | .risk.max_changed_lines = 2'
  FAKE_GH_AT=2026-10-06T09:00:00Z team "$REPO" ask --iid 14 >/dev/null
  later COMMENTED maria "Looks fine to me."
  [ "$(review_ | jq -r .approval)" = asked ]
}

@test "only the tech lead reviews, asks, merges and sends work back" {
  for c in review ask merge; do
    run team "$RUI" "$c" --iid 14
    [ "$status" -eq 6 ]
  done
  echo x > "$BATS_TEST_TMPDIR/m"
  run team "$RUI" return --iid 14 --body-file "$BATS_TEST_TMPDIR/m"
  [ "$status" -eq 6 ]
}

@test "a story with no open pull request has nothing to review" {
  echo '[]' > "$FAKE_GH/closing/14.json"
  run review_
  [ "$status" -eq 1 ]
  [[ "$output" == *"#14 has no open pull request"* ]] || false
}

@test "inbox: the tech lead sees what waits for review and each developer's backlog against the queue" {
  issue 16 "Export CSV" '["dev::ana","compasso::backlog"]' '**Tests:** unit' 6
  issue 17 "Totals" '[]' '**Tests:** unit' 6
  run team "$REPO" inbox --milestone S20 --json
  [ "$(jq -c '[.review[] | [.iid, .dev]]' <<<"$output")" = '[[14,"rui"]]' ]
  [ "$(jq -c '[.queue[] | [.dev, .backlog, .room, .below_min]]' <<<"$output")" = '[["ana",1,14,true],["rui",0,15,true]]' ]
  [ "$(jq -c '[.stage, .nothing]' <<<"$output")" = '["mvp",false]' ]
  run team "$REPO" inbox --milestone S20
  [[ "$output" == *"To review: #14 Status filter (rui)"* ]] || false
  [[ "$output" == *"Backlog (queue 15, at least 5): ana 1, rui 0"* ]] || false
}
