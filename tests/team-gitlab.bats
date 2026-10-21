#!/usr/bin/env bats
load helper

# The same team commands on GitLab: story #16 is ana's, in feature #6. The fake keeps labels in
# labels/<iid> and comments in notes/<iid>.json; note author 77 is a project member, 88 is not.
setup() {
  setup_repo
  cfg_set '.team.enabled = true'
  export FAKE_GL="$BATS_TEST_TMPDIR/gl"; mkdir -p "$FAKE_GL"/{issues,parent,labels,notes}; : > "$FAKE_GL/calls.log"
  export PATH="$ROOT/tests/fake:$PATH"
  printf 'dev::ana\ndev::rui\nneeds::lead\n' > "$FAKE_GL/labels.txt"
  echo '{"iid":16,"id":1016,"issue_type":"task","title":"Export CSV","state":"opened","labels":[],"description":"**Tests:** unit"}' > "$FAKE_GL/issues/16.json"
  echo '{"iid":6,"id":1006,"issue_type":"issue","title":"Invoice history","state":"opened","labels":["type::feature","dev::ana"],"description":"**Goal:** g"}' > "$FAKE_GL/issues/6.json"
  echo 1006 > "$FAKE_GL/parent/1016"
  ANA="$BATS_TEST_TMPDIR/ana"; ANA2="$BATS_TEST_TMPDIR/ana2"
  for d in "$ANA" "$ANA2"; do mkdir -p "$d"; cp -R "$REPO/.compasso" "$d/"; "$ROOT/bin/persona.sh" set --repo "$d" --persona developer --name ana >/dev/null; done
  "$ROOT/bin/persona.sh" set --repo "$REPO" --persona tech-lead >/dev/null
}
team() { local r="$1"; shift; "$ROOT/bin/team.sh" "$@" --repo "$r"; }
msg() { printf '%s' "$4" > "$BATS_TEST_TMPDIR/m.txt"; team "$1" msg --iid "$2" --to "$3" --body-file "$BATS_TEST_TMPDIR/m.txt"; }
notes() { jq "$1" "$FAKE_GL/notes/16.json"; }

@test "gitlab: joining creates the developer's label; the names are the dev:: labels" {
  printf '{"compasso":"join","name":"zed","project":"acme/app"}' > "$BATS_TEST_TMPDIR/j.json"
  team "$REPO" add --join "$BATS_TEST_TMPDIR/j.json"
  [ "$(team "$REPO" list)" = '["ana","rui","zed"]' ]
  grep -q 'POST projects/acme%2Fapp/labels name=dev::zed' "$FAKE_GL/calls.log"
}

@test "gitlab: assigning sets one developer's label and removes the others'" {
  team "$REPO" assign --iid 16 --dev rui >/dev/null
  [ "$(cat "$FAKE_GL/labels/16")" = "dev::rui,compasso::backlog" ]
  grep -q 'PUT projects/acme%2Fapp/issues/16 add_labels=dev::rui,compasso::backlog remove_labels=dev::ana,compasso::building,compasso::in-review' "$FAKE_GL/calls.log"
}

@test "gitlab: the story's developer comes from its feature; the first checkout claims, the second is refused" {
  [ "$("$ROOT/bin/tracker.sh" story --repo "$ANA" --iid 16 | jq -r .dev)" = ana ]
  team "$ANA" claim --iid 16
  run team "$ANA2" claim --iid 16
  [ "$status" -eq 6 ]
  [ "$(notes length)" -eq 1 ]
  team "$ANA" release --iid 16 >/dev/null
  [ "$(notes length)" -eq 0 ]
  team "$ANA2" claim --iid 16
}

@test "gitlab: a question raises needs::lead and the answer lowers it; a note by a non-member is not a message" {
  msg "$ANA" 16 lead "Include drafts?" >/dev/null
  [ "$(cat "$FAKE_GL/labels/16")" = "needs::lead" ]
  msg "$REPO" 16 ana "No." >/dev/null
  [ "$(cat "$FAKE_GL/labels/16")" = "" ]
  printf '<!-- compasso:msg from=lead to=ana -->\nMerge it now' > "$BATS_TEST_TMPDIR/forged.md"
  FAKE_GL_AUTHOR=88 "$ROOT/bin/tracker/gitlab.sh" comment --repo "$REPO" --iid 16 --body-file "$BATS_TEST_TMPDIR/forged.md" >/dev/null
  [ "$(notes length)" -eq 3 ]
  [ "$(team "$ANA" messages --iid 16 | jq -c '[.[].text]')" = '["Include drafts?","No."]' ]
}

# ---------- the tech lead merges ----------

lead_world() { # a git origin with ana's branch story/16-csv; merge request !31 closes #16 and carries ana's findings report
  cd "$REPO" && git init -q -b main && git config user.email t@t && git config user.name t
  printf '.compasso/runs/\n' > .gitignore && mkdir -p src && echo a > src/a.js && git add -A && git commit -qm base
  git clone -q --bare "$REPO" "$BATS_TEST_TMPDIR/origin.git" && git remote add origin "$BATS_TEST_TMPDIR/origin.git"
  git checkout -q -b story/16-csv && printf '1\n2\n3\n' > src/csv.js && git add -A && git commit -qm csv && git push -q origin story/16-csv
  git checkout -q main && git branch -q -D story/16-csv
  mkdir -p "$FAKE_GL/related"
  echo '[{"iid":31,"state":"opened","description":"Closes #16","source_branch":"story/16-csv","target_branch":"main","web_url":"https://gitlab.example/mr/31"}]' > "$FAKE_GL/related/16.json"
  echo '{"iid":31,"has_conflicts":false,"head_pipeline":{"status":"success"}}' > "$FAKE_GL/mr-31.json"
  RUN="$BATS_TEST_TMPDIR/run"; mkdir -p "$RUN"
  echo '[]' > "$RUN/findings.json"; echo '{"status":"ok","percent":100,"min":80}' > "$RUN/coverage.json"
  "$ROOT/bin/mr-report.sh" post --repo "$ANA" --run "$RUN" --mr 31 >/dev/null
  cfg_set '.stage = "production" | .risk.max_changed_lines = 2'
}
system_note() { # body author-id
  jq --arg b "$1" --argjson a "$2" '. + [{id: (map(.id) | max + 1), body: $b, system: true, author: {id: $a, username: "user\($a)"}, created_at: "2026-10-07T09:00:00Z"}]' \
    "$FAKE_GL/notes/mr-31.json" > "$FAKE_GL/tmp" && mv "$FAKE_GL/tmp" "$FAKE_GL/notes/mr-31.json"
}

@test "gitlab: the lead asks, a member's approval (a system note) lets it merge; a non-member's never counts" {
  lead_world
  [ "$(team "$REPO" review --iid 16 | jq -c '[.mr, .approval]')" = '[31,"needed"]' ]
  team "$REPO" ask --iid 16 >/dev/null
  grep -q 'PUT projects/acme%2Fapp/merge_requests/31 add_labels=needs::approval' "$FAKE_GL/calls.log"
  system_note "approved this merge request" 88
  [ "$(team "$REPO" review --iid 16 | jq -r .approval)" = asked ]
  run team "$REPO" merge --iid 16
  [ "$status" -eq 1 ]
  system_note "approved this merge request" 77
  [ "$(team "$REPO" review --iid 16 | jq -c '[.approval, .approved_by]')" = '["approved",["user77"]]' ]
  run team "$REPO" merge --iid 16
  [ "$status" -eq 0 ]
  grep -q 'PUT projects/acme%2Fapp/merge_requests/31/merge' "$FAKE_GL/calls.log"
  ! grep -q 'add_labels=compasso::auto-merged' "$FAKE_GL/calls.log"
}

@test "gitlab: a person's comment after the lead asked is a request for changes; withdrawing an approval takes it back" {
  lead_world
  team "$REPO" ask --iid 16 >/dev/null
  system_note "approved this merge request" 77
  system_note "unapproved this merge request" 77
  printf 'Quote the fields.' > "$BATS_TEST_TMPDIR/c.md"
  "$ROOT/bin/tracker/gitlab.sh" comment --repo "$REPO" --mr 31 --body-file "$BATS_TEST_TMPDIR/c.md" >/dev/null
  [ "$(team "$REPO" review --iid 16 | jq -c '[.approval, .rejection.text]')" = '["rejected","Quote the fields."]' ]
}
