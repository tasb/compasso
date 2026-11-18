#!/usr/bin/env bats
load helper

# tracker.sh assign: the tech lead gives a story to one developer - its dev:: label, back in the
# backlog state, and no other developer's label. Only the tech lead assigns.
setup() {
  setup_repo
  cfg_set '.team.enabled = true'
  "$ROOT/bin/persona.sh" set --repo "$REPO" --persona tech-lead >/dev/null
  export FAKE_GL="$BATS_TEST_TMPDIR/gl"; mkdir -p "$FAKE_GL/issues" "$FAKE_GL/labels"; : > "$FAKE_GL/calls.log"
  export PATH="$ROOT/tests/fake:$PATH"
  echo '{"iid":9,"id":1009,"title":"Search","state":"opened","labels":["type::story","dev::rui","compasso::building"]}' > "$FAKE_GL/issues/9.json"
  echo 'type::story,dev::rui,compasso::building' > "$FAKE_GL/labels/9"
}

@test "gitlab: one developer's label, the backlog state, the other developer's label and states removed" {
  run "$ROOT/bin/tracker.sh" assign --repo "$REPO" --iid 9 --name ana
  [ "$status" -eq 0 ]
  grep -q 'PUT projects/acme%2Fapp/issues/9 add_labels=dev::ana,compasso::backlog remove_labels=dev::rui,compasso::building,compasso::in-review' "$FAKE_GL/calls.log"
  [ "$(cat "$FAKE_GL/labels/9")" = 'type::story,dev::ana,compasso::backlog' ]
}

@test "github: the same labels" {
  cfg_set '.tracker.provider = "github" | .tracker.host = "github.com"'
  export FAKE_GH="$BATS_TEST_TMPDIR/gh"; mkdir -p "$FAKE_GH/issues"; : > "$FAKE_GH/calls.log"
  echo '{"number":9,"title":"Search","state":"open","labels":[{"name":"type::story"},{"name":"dev::rui"},{"name":"compasso::building"}],"body":""}' > "$FAKE_GH/issues/9.json"
  run "$ROOT/bin/tracker.sh" assign --repo "$REPO" --iid 9 --name ana
  [ "$status" -eq 0 ]
  [ "$(jq -r '.labels | map(.name) | sort | join(",")' "$FAKE_GH/issues/9.json")" = 'compasso::backlog,dev::ana,type::story' ]
}

@test "only the tech lead assigns, and a name is needed" {
  run "$ROOT/bin/tracker.sh" assign --repo "$REPO" --iid 9
  [ "$status" -eq 1 ]
  [[ "$output" == *"assign needs --name"* ]] || false
  "$ROOT/bin/persona.sh" set --repo "$REPO" --persona developer --name ana >/dev/null
  run "$ROOT/bin/tracker.sh" assign --repo "$REPO" --iid 9 --name ana
  [ "$status" -eq 6 ]
  [[ "$output" == *"assign is the tech lead's"* ]] || false
  [ ! -s "$FAKE_GL/calls.log" ]
}
