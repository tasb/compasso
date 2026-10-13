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
  [ "$(cat "$FAKE_GL/labels/16")" = "dev::rui" ]
  grep -q 'PUT projects/acme%2Fapp/issues/16 add_labels=dev::rui remove_labels=dev::ana' "$FAKE_GL/calls.log"
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
