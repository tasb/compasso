#!/usr/bin/env bats
load helper

# Follow-ups filed before 3.1.0 went to no sprint (and, in a team project, without labels): the
# tech lead moves the open ones into the current sprint, where the queue assigns them.
# GitLab: #40 and #41 are follow-ups in no sprint, #42 is another issue in no sprint; sprint S1 is milestone 501.
setup() {
  setup_repo
  export FAKE_GL="$BATS_TEST_TMPDIR/gl"; mkdir -p "$FAKE_GL/issues"; : > "$FAKE_GL/calls.log"
  export PATH="$ROOT/tests/fake:$PATH"
  jq -n '[{iid: 40, title: "Vague name", state: "opened", labels: [], description: "x\n\n<!-- compasso:followup story=8 -->"},
          {iid: 41, title: "No SCP", state: "opened", labels: [], description: "y\n\n<!-- compasso:followup story=9 -->"},
          {iid: 42, title: "An idea", state: "opened", labels: [], description: "z"}]' > "$FAKE_GL/issues-None.json"
  echo '[{"id":501,"title":"S1"}]' > "$FAKE_GL/milestones.json"
}
fu() { "$ROOT/bin/followups.sh" "$@" --repo "$REPO"; }

@test "lists the open follow-ups in no sprint, and changes nothing without --apply" {
  run fu --milestone S1
  [ "$status" -eq 0 ]
  [[ "$output" == *"#40 Vague name (from #8)"* ]] || false
  [[ "$output" == *"#41 No SCP (from #9)"* ]] || false
  [[ "$output" != *"#42"* ]] || false
  [[ "$output" == *"--apply"* ]] || false
  ! grep -q '^PUT' "$FAKE_GL/calls.log"
}

@test "--apply moves each into the sprint" {
  run fu --milestone S1 --apply
  [ "$status" -eq 0 ]
  grep -q 'PUT projects/acme%2Fapp/issues/40 milestone_id=501' "$FAKE_GL/calls.log"
  grep -q 'PUT projects/acme%2Fapp/issues/41 milestone_id=501' "$FAKE_GL/calls.log"
  ! grep -q 'issues/42 ' "$FAKE_GL/calls.log"
}

@test "the sprint comes from the plan; a sprint that does not exist is refused" {
  mkdir -p "$REPO/.compasso"; printf 'epic:\n  sprint: {number: 1}\n' > "$REPO/.compasso/plan.yaml"
  fu --apply >/dev/null
  grep -q 'issues/40 milestone_id=501' "$FAKE_GL/calls.log"
  run fu --milestone S9 --apply
  [ "$status" -eq 1 ]
  [[ "$output" == *"no sprint S9"* ]] || false
}

@test "in a team project only the tech lead moves them" {
  cfg_set '.team.enabled = true'
  "$ROOT/bin/persona.sh" set --repo "$REPO" --persona developer --name ana >/dev/null
  run fu --milestone S1 --apply
  [ "$status" -eq 6 ]
  ! grep -q '^PUT' "$FAKE_GL/calls.log"
  "$ROOT/bin/persona.sh" set --repo "$REPO" --persona tech-lead >/dev/null
  fu --milestone S1 --apply >/dev/null
  grep -q 'issues/41 milestone_id=501' "$FAKE_GL/calls.log"
}

@test "GitHub: the same commands" {
  cfg_set '.tracker.provider = "github" | .tracker.host = "github.com"'
  export FAKE_GH="$BATS_TEST_TMPDIR/gh"; mkdir -p "$FAKE_GH/issues"; : > "$FAKE_GH/calls.log"
  echo '[{"number":1,"title":"S1"}]' > "$FAKE_GH/milestones.json"
  for n in 40 42; do
    jq -n --argjson n "$n" --arg b "$([ "$n" = 40 ] && echo '<!-- compasso:followup story=8 -->' || echo z)" \
      '{number: $n, id: (1000 + $n), node_id: "I_\($n)", title: "t\($n)", state: "open", body: $b, labels: [], milestone: null, assignees: []}' > "$FAKE_GH/issues/$n.json"
  done
  run fu --milestone S1 --apply
  [ "$status" -eq 0 ]
  [[ "$output" == *"#40 t40 (from #8)"* ]] || false
  [ "$(jq -r .milestone.title "$FAKE_GH/issues/40.json")" = S1 ]
  [ "$(jq -r .milestone "$FAKE_GH/issues/42.json")" = null ]
}
