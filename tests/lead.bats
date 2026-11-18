#!/usr/bin/env bats
load helper

# bin/lead.sh: the tech lead's actions - merge, one rework round, the after-MVP list, delivery to
# staging and the revert of a red main. The fake GitLab keeps merge requests in mr-<n>.json, notes in
# notes/, issue labels in labels/ and the default branch's pipelines in pipelines.json.
setup() {
  setup_repo
  cfg_set '.stage = "mvp" | .team.enabled = true | .team.developers = ["ana"] | .people.ask = ["paula"]'
  export FAKE_GL="$BATS_TEST_TMPDIR/gl"; mkdir -p "$FAKE_GL"; : > "$FAKE_GL/calls.log"
  export PATH="$ROOT/tests/fake:$PATH"
  git -C "$REPO" init -q -b main; as lead
  mr 30 success false
  printf 'A finding that is not a blocker.\n' > "$BATS_TEST_TMPDIR/f.md"
}
as() { # as lead | as dev <name>
  local login="svc-${2:-lead}"
  if [ "$1" = lead ]; then "$ROOT/bin/persona.sh" set --repo "$REPO" --persona tech-lead >/dev/null
  else "$ROOT/bin/persona.sh" set --repo "$REPO" --persona developer --name "$2" >/dev/null; fi
  mkdir -p "$COMPASSO_HOME/accounts/gitlab.com"; printf 'glpat-x' > "$COMPASSO_HOME/accounts/gitlab.com/$login"; chmod 600 "$COMPASSO_HOME/accounts/gitlab.com/$login"
  "$ROOT/bin/persona.sh" account --repo "$REPO" --set "$login" --email "$login@agents.example" >/dev/null
}
mr() { # iid pipeline conflicts
  printf '{"iid":%s,"head_pipeline":{"status":"%s"},"has_conflicts":%s,"target_branch":"main","web_url":"https://gitlab.example/mr/%s"}' "$1" "$2" "$3" "$1" > "$FAKE_GL/mr-$1.json"
}
lead() { "$ROOT/bin/lead.sh" "$1" --repo "$REPO" "${@:2}"; }

@test "merge: a green merge request merges when its pipeline succeeds" {
  run lead merge --mr 30
  [ "$status" -eq 0 ]
  grep -q 'PUT projects/acme%2Fapp/merge_requests/30/merge merge_when_pipeline_succeeds=true' "$FAKE_GL/calls.log"
}

@test "merge: a failed pipeline is refused; a conflict goes back to rebase, without a review round" {
  mr 30 failed false
  run lead merge --mr 30
  [ "$status" -eq 1 ]
  [[ "$output" == *"!30 is not merged: its pipeline failed"* ]] || false
  mr 30 success true
  run lead merge --mr 30
  [ "$status" -eq 0 ]
  ! grep -q '/merge ' "$FAKE_GL/calls.log" || false
  grep -q 'PUT projects/acme%2Fapp/merge_requests/30 add_labels=compasso::rework' "$FAKE_GL/calls.log"
  jq -r '.[0].body' "$FAKE_GL/notes/mr-30.json" | grep -q '^!30 conflicts with main: rebase it onto main'
  ! grep -q 'compasso:rework -->' "$FAKE_GL/notes/mr-30.json" || false
}

@test "rework: the first time the blockers go back to the developer, with the rework label" {
  printf '1. Acceptance 2 is not met: the filter ignores case.\n' > "$BATS_TEST_TMPDIR/b.md"
  run lead rework --mr 30 --story 5 --body-file "$BATS_TEST_TMPDIR/b.md"
  [ "$status" -eq 0 ]
  grep -q 'PUT projects/acme%2Fapp/merge_requests/30 add_labels=compasso::rework' "$FAKE_GL/calls.log"
  body="$(jq -r '.[0].body' "$FAKE_GL/notes/mr-30.json")"
  [[ "$body" == "1. Acceptance 2 is not met: the filter ignores case."* ]] || false
  [[ "$body" == *"remove the compasso::rework label"* ]] || false
  [[ "$body" == *"<!-- compasso:rework -->" ]] || false
  ! grep -q 'needs::human' "$FAKE_GL/calls.log" || false
}

@test "rework: blockers again after a rework go to a person, and the story waits" {
  printf 'b\n' > "$BATS_TEST_TMPDIR/b.md"
  lead rework --mr 30 --story 5 --body-file "$BATS_TEST_TMPDIR/b.md" >/dev/null
  : > "$FAKE_GL/calls.log"
  run lead rework --mr 30 --story 5 --body-file "$BATS_TEST_TMPDIR/b.md"
  [ "$status" -eq 0 ]
  ! grep -q 'add_labels=compasso::rework' "$FAKE_GL/calls.log" || false
  [ "$(jq length "$FAKE_GL/notes/mr-30.json")" -eq 2 ]
  head -1 "$FAKE_GL/desc/1.md" | grep -qx '<!-- compasso:ask story=5 key=rework-30 -->'
  grep -q 'https://gitlab.example/mr/30' "$FAKE_GL/desc/1.md"
  grep -q 'title=Compasso: !30 was sent back a second time' "$FAKE_GL/calls.log"
  [ "$(cat "$FAKE_GL/labels/5")" = needs::human ]
}

@test "later: the after-MVP list is one issue, opened once and added to as comments; the oldest list wins" {
  run lead later --body-file "$BATS_TEST_TMPDIR/f.md"
  [ "$status" -eq 0 ]
  grep -q 'POST projects/acme%2Fapp/issues title=After the MVP issue_type=issue labels=compasso::after-mvp' "$FAKE_GL/calls.log"
  [ "$(cat "$FAKE_GL/desc/1.md")" = '<!-- compasso:after-mvp list -->' ]
  [ "$(jq -r '.[0].body' "$FAKE_GL/notes/1.json")" = 'A finding that is not a blocker.' ]
  jq -n '[{iid: 9, web_url: "u", labels: ["compasso::after-mvp"], description: "<!-- compasso:after-mvp list -->"},
          {iid: 3, web_url: "u", labels: ["compasso::after-mvp"], description: "<!-- compasso:after-mvp list -->"},
          {iid: 2, labels: ["compasso::after-mvp"], description: "x\n<!-- compasso:after-mvp story=4 -->"}]' > "$FAKE_GL/issue-query.json"
  run lead later --body-file "$BATS_TEST_TMPDIR/f.md"
  [ "$(grep -c 'POST projects/acme%2Fapp/issues ' "$FAKE_GL/calls.log")" -eq 1 ]
  [ "$(jq length "$FAKE_GL/notes/3.json")" -eq 1 ]
  [ ! -e "$FAKE_GL/notes/9.json" ] && [ ! -e "$FAKE_GL/notes/2.json" ]
}

@test "later: titled in the project's language" {
  cfg_set '.language = "pt-BR"'
  lead later --body-file "$BATS_TEST_TMPDIR/f.md" >/dev/null
  grep -q 'issues title=Depois do MVP ' "$FAKE_GL/calls.log"
}

@test "deliver: people are asked to test on staging, its address first; then the feature is done and closed" {
  cfg_set '.staging.url = "https://staging.acme.example"'
  cat > "$BATS_TEST_TMPDIR/d.json" <<'EOF'
{"need": "Test the CSV export on staging.", "why": ["Its 3 stories are merged and main is green."],
 "steps": ["Open Reports and click Export.", "Check the file has one row per invoice."], "meanwhile": "The developers build the next feature."}
EOF
  run lead deliver --feature 4 --title "Test: CSV export" --from "$BATS_TEST_TMPDIR/d.json"
  [ "$status" -eq 0 ]
  head -1 "$FAKE_GL/desc/1.md" | grep -qx '<!-- compasso:ask story= key=deliver-4 -->'
  grep -qx '1. Open staging: https://staging.acme.example' "$FAKE_GL/desc/1.md"
  grep -qx '2. Open Reports and click Export.' "$FAKE_GL/desc/1.md"
  [ "$(cat "$FAKE_GL/labels/4")" = compasso::done ]
  grep -q 'PUT projects/acme%2Fapp/issues/4 state_event=close' "$FAKE_GL/calls.log"
  jq -r '.[0].body' "$FAKE_GL/notes/4.json" | grep -q 'people test it in #1'
}

@test "a developer cannot merge, reopen, add stories or file for after the MVP; mr-label sets only the runner's labels" {
  as dev ana
  for c in "mr-merge --mr 30" "reopen --iid 5" "after-mvp --title t --body-file $BATS_TEST_TMPDIR/f.md" "add-story --parent 4 --title t --from $BATS_TEST_TMPDIR/f.md" "harden-feature --title t"; do
    # shellcheck disable=SC2086
    run "$ROOT/bin/tracker.sh" $c --repo "$REPO"
    [ "$status" -ne 0 ]
  done
  [ ! -s "$FAKE_GL/calls.log" ]
  run "$ROOT/bin/tracker.sh" mr-label --repo "$REPO" --mr 30 --remove compasso::rework
  [ "$status" -eq 0 ]
  run "$ROOT/bin/tracker.sh" mr-label --repo "$REPO" --mr 30 --add needs::approval
  [ "$status" -eq 1 ]
  [[ "$output" == *"mr-label sets only compasso::rework and compasso::fix-main"* ]] || false
}

story_json() {
  cat > "$BATS_TEST_TMPDIR/s.json" <<'EOF'
{"as": "a manager", "want": "to export invoices as CSV", "so_that": "I can file them",
 "acceptance": ["Given 3 invoices, When I click Export, Then the CSV has 3 rows"],
 "verify": ["npm test -- export"], "tests": ["e2e"], "depends_on": ["#12"]}
EOF
}

@test "story: written straight into the tracker, in the feature's sprint, under it, with its developer and its Feature line" {
  story_json; mkdir -p "$FAKE_GL/issues"
  echo '{"iid":4,"id":1004,"title":"Export","state":"opened","issue_type":"issue","milestone":{"id":501,"title":"S2"},"labels":["type::feature","dev::ana"]}' > "$FAKE_GL/issues/4.json"
  run lead story --feature 4 --title "Export CSV" --from "$BATS_TEST_TMPDIR/s.json"
  [ "$status" -eq 0 ]
  [ "$(jq -c '{iid}' <<<"$output")" = '{"iid":1}' ]
  grep -q 'POST projects/acme%2Fapp/issues title=Export CSV milestone_id=501 issue_type=task labels=dev::ana,compasso::backlog' "$FAKE_GL/calls.log"
  grep -qx '\*\*Feature:\*\* #4\\' "$FAKE_GL/desc/1.md"
  grep -q '^\*\*Depends on:\*\* #12' "$FAKE_GL/desc/1.md"
  grep -qx -- '- \[ \] Given 3 invoices, When I click Export, Then the CSV has 3 rows' "$FAKE_GL/desc/1.md"
  ! grep -q 'compasso:key' "$FAKE_GL/desc/1.md" || false
  [ "$(cat "$FAKE_GL/parent/1001")" = 1004 ]
}

@test "story: a feature with no developer leaves it for the lead to assign; outside a team it is an agent's" {
  story_json; mkdir -p "$FAKE_GL/issues"
  echo '{"iid":4,"id":1004,"title":"Export","state":"opened","issue_type":"issue","milestone":null,"labels":["type::feature"]}' > "$FAKE_GL/issues/4.json"
  lead story --feature 4 --title "Export CSV" --from "$BATS_TEST_TMPDIR/s.json" >/dev/null
  grep -q 'POST projects/acme%2Fapp/issues title=Export CSV issue_type=task labels= *$' "$FAKE_GL/calls.log"
  cfg_set '.team.enabled = false'; "$ROOT/bin/persona.sh" set --repo "$REPO" --persona default >/dev/null
  lead story --feature 4 --title "Export CSV" --from "$BATS_TEST_TMPDIR/s.json" >/dev/null
  grep -q 'POST projects/acme%2Fapp/issues title=Export CSV issue_type=task labels=owner::agent' "$FAKE_GL/calls.log"
}

@test "story: one without acceptance, Verify or tests (unit, e2e) is refused before anything is written" {
  story_json
  for f in '.acceptance = []' '.verify = []' '.tests = []' '.tests = ["manual"]' '.want = ""'; do
    jq "$f" "$BATS_TEST_TMPDIR/s.json" > "$BATS_TEST_TMPDIR/bad.json"
    run lead story --feature 4 --title t --from "$BATS_TEST_TMPDIR/bad.json"
    [ "$status" -eq 1 ]
    [[ "$output" == *"lead: the story needs"* ]] || false
  done
  [ ! -s "$FAKE_GL/calls.log" ]
}

@test "story on github: in the feature's milestone, as its sub-issue" {
  cfg_set '.tracker.provider = "github" | .tracker.host = "github.com"'
  export FAKE_GH="$BATS_TEST_TMPDIR/gh"; mkdir -p "$FAKE_GH/issues"; : > "$FAKE_GH/calls.log"; echo 20 > "$FAKE_GH/next_number"
  echo '[{"number":3,"title":"S2","due_on":"2026-11-27T23:59:59Z"}]' > "$FAKE_GH/milestones.json"
  echo '{"number":4,"id":1004,"title":"Export","state":"open","labels":[{"name":"type::feature"},{"name":"dev::ana"}],"milestone":{"number":3,"title":"S2"},"body":""}' > "$FAKE_GH/issues/4.json"
  story_json
  run lead story --feature 4 --title "Export CSV" --from "$BATS_TEST_TMPDIR/s.json"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.milestone.number' "$FAKE_GH/issues/20.json")" = 3 ]
  [ "$(jq -r '.labels | map(.name) | join(",")' "$FAKE_GH/issues/20.json")" = dev::ana,compasso::backlog ]
  [ "$(cat "$FAKE_GH/parent/20")" = 4 ]
  jq -r .body "$FAKE_GH/issues/20.json" | grep -q '^\*\*Feature:\*\* #4'
}

@test "hardening: one open feature holds the stories drained from the after-MVP list; it is opened once" {
  run lead hardening
  [ "$status" -eq 0 ]
  [ "$(jq -c '{iid}' <<<"$output")" = '{"iid":1}' ]
  grep -q 'POST projects/acme%2Fapp/issues title=Hardening: after the MVP issue_type=issue labels=type::feature,compasso::building' "$FAKE_GL/calls.log"
  head -1 "$FAKE_GL/desc/1.md" | grep -qx '<!-- compasso:harden -->'
  jq -n --rawfile d "$FAKE_GL/desc/1.md" '[{iid: 1, web_url: "u", labels: ["type::feature"], description: $d}]' > "$FAKE_GL/issue-query.json"
  run lead hardening
  [ "$(jq -c '{iid}' <<<"$output")" = '{"iid":1}' ]
  [ "$(grep -c 'POST projects/acme%2Fapp/issues ' "$FAKE_GL/calls.log")" -eq 1 ]
}

@test "hardening on github, and in the project's language" {
  cfg_set '.tracker.provider = "github" | .tracker.host = "github.com" | .language = "pt-BR"'
  export FAKE_GH="$BATS_TEST_TMPDIR/gh"; mkdir -p "$FAKE_GH/issues"; : > "$FAKE_GH/calls.log"; echo 20 > "$FAKE_GH/next_number"
  lead hardening >/dev/null
  lead hardening >/dev/null
  [ "$(jq -r .title "$FAKE_GH/issues/20.json")" = "Hardening: depois do MVP" ]
  [ "$(jq -r '.labels | map(.name) | join(",")' "$FAKE_GH/issues/20.json")" = type::feature,compasso::building ]
  [ ! -e "$FAKE_GH/issues/21.json" ]
}

# red-main: a real git history behind a bare origin; the fake GitLab says which commit broke main
red_world() {
  O="$BATS_TEST_TMPDIR/origin.git"; git init -q --bare -b main "$O"
  git -C "$REPO" config user.email lead@agents.example; git -C "$REPO" config user.name lead
  git -C "$REPO" remote add origin "$O"
  echo ok > "$REPO/app.txt"; git -C "$REPO" add app.txt; git -C "$REPO" commit -qm base
  echo broken > "$REPO/bad.txt"; git -C "$REPO" add bad.txt; git -C "$REPO" commit -qm "story 5"
  BAD="$(git -C "$REPO" rev-parse HEAD)"
  git -C "$REPO" push -q origin main
  printf '[{"id":2,"status":"failed","sha":"%s","web_url":"https://gitlab.example/p/2"},{"id":1,"status":"success","sha":"x"}]' "$BAD" > "$FAKE_GL/pipelines.json"
  mkdir -p "$FAKE_GL/commit-mrs"; echo '[{"iid":30,"state":"merged"}]' > "$FAKE_GL/commit-mrs/$BAD.json"
  echo '[{"iid":5}]' > "$FAKE_GL/closes.json"
}

@test "red-main: the commit that broke main is reverted in a fix-main merge request that merges itself; its story reopens" {
  red_world
  run lead red-main
  [ "$status" -eq 0 ]
  short="$(printf '%s' "$BAD" | cut -c1-8)"
  [ "$(git -C "$O" show "fix/main-$short:app.txt")" = ok ]
  ! git -C "$O" cat-file -e "fix/main-$short:bad.txt" 2>/dev/null || false
  grep -q "POST projects/acme%2Fapp/merge_requests source_branch=fix/main-$short target_branch=main title=Revert $short: main is red" "$FAKE_GL/calls.log"
  grep -q 'PUT projects/acme%2Fapp/merge_requests/31 add_labels=compasso::fix-main' "$FAKE_GL/calls.log"
  grep -q 'PUT projects/acme%2Fapp/merge_requests/31/merge merge_when_pipeline_succeeds=true' "$FAKE_GL/calls.log"
  grep -q 'PUT projects/acme%2Fapp/issues/5 state_event=reopen' "$FAKE_GL/calls.log"
  [[ "$(cat "$FAKE_GL/labels/5")" == *compasso::backlog* ]] || false
  jq -r '.[0].body' "$FAKE_GL/notes/5.json" | grep -q 'reverted in !31'
  [ -z "$(git -C "$REPO" worktree list | sed 1d)" ]
}

@test "red-main: a merge commit is reverted to its first parent" {
  red_world
  git -C "$REPO" reset -q --hard HEAD~1
  git -C "$REPO" checkout -q -b story/6; echo also-broken > "$REPO/bad6.txt"; git -C "$REPO" add bad6.txt; git -C "$REPO" commit -qm "story 6"
  git -C "$REPO" checkout -q main; git -C "$REPO" merge -q --no-ff -m "Merge story 6" story/6
  BAD="$(git -C "$REPO" rev-parse HEAD)"; git -C "$REPO" push -q -f origin main
  printf '[{"id":2,"status":"failed","sha":"%s","web_url":"https://gitlab.example/p/2"}]' "$BAD" > "$FAKE_GL/pipelines.json"
  run lead red-main
  [ "$status" -eq 0 ]
  short="$(printf '%s' "$BAD" | cut -c1-8)"
  [ "$(git -C "$O" show "fix/main-$short:app.txt")" = ok ]
  ! git -C "$O" cat-file -e "fix/main-$short:bad6.txt" 2>/dev/null || false
}

@test "red-main: a revert that conflicts, or a revert whose pipeline failed, goes to a person" {
  red_world
  echo fixed-later > "$REPO/bad.txt"; git -C "$REPO" commit -qam "later change"; git -C "$REPO" push -q origin main
  run lead red-main
  [ "$status" -eq 0 ]
  short="$(printf '%s' "$BAD" | cut -c1-8)"
  head -1 "$FAKE_GL/desc/1.md" | grep -qx "<!-- compasso:ask story= key=red-main-$short -->"
  grep -q 'reverting it conflicts' "$FAKE_GL/desc/1.md"
  ! git -C "$O" rev-parse -q --verify "fix/main-$short" >/dev/null || false
  ! grep -qE '^(POST|PUT) .*merge_requests' "$FAKE_GL/calls.log" || false
  run lead red-main --failed-fix 31
  [ "$status" -eq 0 ]
  grep -q 'its revert !31 failed its pipeline too' "$FAKE_GL/desc/2.md"
}

@test "red-main: nothing to do when main is green" {
  echo '[{"id":1,"status":"success","sha":"x"}]' > "$FAKE_GL/pipelines.json"
  run lead red-main
  [ "$status" -eq 0 ]
  [[ "$output" == "lead: the default branch is not red" ]] || false
}

@test "github: the tech lead merges with auto-merge, reopens, and files the after-MVP list" {
  cfg_set '.tracker.provider = "github" | .tracker.host = "github.com"'
  export FAKE_GH="$BATS_TEST_TMPDIR/gh"; mkdir -p "$FAKE_GH/issues"; : > "$FAKE_GH/calls.log"; echo 20 > "$FAKE_GH/next_number"
  echo '{"number":5,"title":"s","state":"closed","labels":[],"body":""}' > "$FAKE_GH/issues/5.json"
  echo '{"number":30,"title":"pr","state":"open","labels":[],"body":""}' > "$FAKE_GH/issues/30.json"
  run lead merge --mr 30
  [ "$status" -eq 0 ]
  grep -q 'PR merge 30 --repo github.com/acme/app --auto --merge' "$FAKE_GH/calls.log"
  "$ROOT/bin/tracker.sh" reopen --repo "$REPO" --iid 5 >/dev/null
  [ "$(jq -r .state "$FAKE_GH/issues/5.json")" = open ]
  "$ROOT/bin/tracker.sh" mr-label --repo "$REPO" --mr 30 --add compasso::rework >/dev/null
  [ "$(jq -r '.labels | map(.name) | join(",")' "$FAKE_GH/issues/30.json")" = compasso::rework ]
  lead later --body-file "$BATS_TEST_TMPDIR/f.md" >/dev/null
  lead later --body-file "$BATS_TEST_TMPDIR/f.md" >/dev/null
  [ "$(jq -r .body "$FAKE_GH/issues/20.json")" = '<!-- compasso:after-mvp list -->' ]
  [ ! -e "$FAKE_GH/issues/21.json" ]
  [ "$(jq length "$FAKE_GH/comments/20.json")" -eq 2 ]
}
