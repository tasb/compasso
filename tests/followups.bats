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

# ---------- legacy: follow-ups whose acceptance no test could check ----------
# Before 3.2.0 a follow-up's acceptance was "Given <where>, When it is reviewed again, Then the finding
# no longer applies", and its Verify "the repo tests". #50 (in S1) and #51 (Portuguese) are such; #52 is a
# follow-up with real acceptance; #53 is not a follow-up.
legacy_world() {
  jq -n '[{iid: 50, title: "Vague name", state: "opened", labels: [], milestone: {title: "S1"},
           description: "## Acceptance\n- [ ] Given the code from #8, When it is reviewed again, Then the finding \"vague name\" no longer applies\n\n<!-- compasso:followup story=8 -->"},
          {iid: 51, title: "Sem SCP", state: "opened", labels: [],
           description: "- [ ] Dado `infra/iam.tf`, Quando for revisto de novo, Então a finding \"x\" deixa de se aplicar\n\n<!-- compasso:followup story=9 -->"},
          {iid: 52, title: "Rename", state: "opened", labels: [],
           description: "- [ ] Given a client, When GET /x, Then 404\n\n<!-- compasso:followup story=9 -->"},
          {iid: 53, title: "An idea", state: "opened", labels: [], description: "When it is reviewed again"}]' > "$FAKE_GL/issue-query.json"
}

@test "legacy: lists the open follow-ups whose acceptance no test could check, in any sprint, and changes nothing without --close" {
  legacy_world
  run fu legacy
  [ "$status" -eq 0 ]
  [[ "$output" == *"#50 Vague name (from #8)"* ]] || false
  [[ "$output" == *"#51 Sem SCP (from #9)"* ]] || false
  [[ "$output" != *"#52"* ]] || false
  [[ "$output" != *"#53"* ]] || false
  [[ "$output" == *"--close"* ]] || false
  grep -q 'GET projects/acme%2Fapp/issues?state=opened&per_page=100' "$FAKE_GL/calls.log"
  ! grep -q '^PUT\|^POST' "$FAKE_GL/calls.log"
}

@test "legacy --close: each gets a comment naming its story, then is closed" {
  legacy_world
  run fu legacy --close
  [ "$status" -eq 0 ]
  for i in 50 51; do grep -q "PUT projects/acme%2Fapp/issues/$i state_event=close" "$FAKE_GL/calls.log"; done
  ! grep -q 'issues/52 \|issues/53 ' "$FAKE_GL/calls.log"
  [[ "$(jq -r '.[0].body' "$FAKE_GL/notes/50.json")" == *"#8"* ]] || false
  [[ "$(jq -r '.[0].body' "$FAKE_GL/notes/51.json")" == *"#9"* ]] || false
}

@test "legacy --close: in a team project only the tech lead closes them" {
  legacy_world
  cfg_set '.team.enabled = true'
  "$ROOT/bin/persona.sh" set --repo "$REPO" --persona developer --name ana >/dev/null
  run fu legacy --close
  [ "$status" -eq 6 ]
  ! grep -q '^PUT\|^POST' "$FAKE_GL/calls.log"
}

@test "GitHub: legacy --close, the same" {
  cfg_set '.tracker.provider = "github" | .tracker.host = "github.com"'
  export FAKE_GH="$BATS_TEST_TMPDIR/gh"; mkdir -p "$FAKE_GH/issues"; : > "$FAKE_GH/calls.log"
  echo '[{"number":1,"title":"S1"}]' > "$FAKE_GH/milestones.json"
  jq -n '{number: 50, id: 1050, node_id: "I_50", title: "t50", state: "open", labels: [], milestone: {number: 1, title: "S1"}, assignees: [],
          body: "- [ ] Given x, When it is reviewed again, Then the finding \"y\" no longer applies\n\n<!-- compasso:followup story=8 -->"}' > "$FAKE_GH/issues/50.json"
  jq -n '{number: 52, id: 1052, node_id: "I_52", title: "t52", state: "open", labels: [], milestone: null, assignees: [],
          body: "- [ ] Given a client, When GET /x, Then 404\n\n<!-- compasso:followup story=9 -->"}' > "$FAKE_GH/issues/52.json"
  run fu legacy --close
  [ "$status" -eq 0 ]
  [[ "$output" == *"#50 t50 (from #8)"* ]] || false
  [ "$(jq -r .state "$FAKE_GH/issues/50.json")" = closed ]
  [ "$(jq -r .state "$FAKE_GH/issues/52.json")" = open ]
  [[ "$(jq -r '.[0].body' "$FAKE_GH/comments/50.json")" == *"#8"* ]] || false
}
