#!/usr/bin/env bats
load helper

# tracker.sh snapshot: the few reads bin/run.sh makes before it starts a model.
# Fixtures: stories #10 and #11 are ana's (#11 depends on the open #10); #12 is rui's,
# waiting for a person on #20; bug #13 has merge request !7 with a green pipeline;
# !8 is sent back for rework; !9 is a draft; main's last finished pipeline failed.
F="$BATS_TEST_DIRNAME/fixtures/snapshot"

setup() {
  setup_repo
  cfg_set '.team.enabled = true'
  setup_glab_stub
  echo '{"default_branch":"main"}' | fixture api --hostname gitlab.com projects/acme%2Fapp
  fixture api --hostname gitlab.com --paginate 'projects/acme%2Fapp/issues?state=opened&per_page=100' < "$F/gl-issues.json"
  fixture api --hostname gitlab.com --paginate 'projects/acme%2Fapp/merge_requests?state=opened&per_page=100' < "$F/gl-mrs.json"
  fixture api --hostname gitlab.com 'projects/acme%2Fapp/pipelines?per_page=100' < "$F/gl-pipelines.json"
}

snap() { "$ROOT/bin/tracker.sh" snapshot --repo "$REPO"; }

@test "gitlab snapshot: each open work item with its kind, state, developer and what still blocks it; a task is a story without a label saying so" {
  run snap
  [ "$status" -eq 0 ]
  [ "$(jq -c '.issues | map({iid, kind, state, dev, needs_human, blocked_by})' <<<"$output")" = \
    '[{"iid":10,"kind":"story","state":"backlog","dev":"ana","needs_human":false,"blocked_by":[]},{"iid":11,"kind":"story","state":"backlog","dev":"ana","needs_human":false,"blocked_by":[10]},{"iid":12,"kind":"story","state":"building","dev":"rui","needs_human":true,"blocked_by":[]},{"iid":13,"kind":"bug","state":"in-review","dev":"rui","needs_human":false,"blocked_by":[]},{"iid":5,"kind":"feature","state":"delivering","dev":null,"needs_human":false,"blocked_by":[]},{"iid":20,"kind":"ask","state":null,"dev":null,"needs_human":true,"blocked_by":[]},{"iid":30,"kind":"later","state":"after-mvp","dev":null,"needs_human":false,"blocked_by":[]},{"iid":31,"kind":"story","state":null,"dev":null,"needs_human":false,"blocked_by":[]}]' ]
  [ "$(jq -c '.issues[] | select(.iid == 20) | .ask_for' <<<"$output")" = 12 ]
  [ "$(jq -c '.issues | map(.ask_key)' <<<"$output")" = '[null,null,null,null,null,"region",null,null]' ]
  [ "$(jq -c '.issues | map(.sprint)' <<<"$output")" = '[{"title":"S2","due":"2026-11-27"},null,null,null,null,null,null,null]' ]
  [ "$(jq -c '.issues | map(.feature)' <<<"$output")" = '[5,null,null,null,null,null,null,null]' ]
  [ "$(jq -r '.issues[0].title, .issues[0].web_url' <<<"$output")" = $'Export CSV\nhttps://gitlab.com/acme/app/-/issues/10' ]
}

@test "gitlab snapshot: each open merge request with its story and the pipeline of its current head" {
  run snap
  [ "$status" -eq 0 ]
  [ "$(jq -c '.mrs | map({iid, story, draft, rework, pipeline})' <<<"$output")" = \
    '[{"iid":7,"story":13,"draft":false,"rework":false,"pipeline":"success"},{"iid":8,"story":12,"draft":false,"rework":true,"pipeline":"running"},{"iid":9,"story":null,"draft":true,"rework":false,"pipeline":"none"}]' ]
}

@test "gitlab snapshot: main's last finished pipeline, never a running one" {
  run snap
  [ "$(jq -c .main <<<"$output")" = '{"pipeline":"failed","sha":"m2"}' ]
  jq 'map(select(.ref != "main" or .id != 104))' "$F/gl-pipelines.json" | fixture api --hostname gitlab.com 'projects/acme%2Fapp/pipelines?per_page=100'
  run snap
  [ "$(jq -c .main <<<"$output")" = '{"pipeline":"success","sha":"m1"}' ]
  echo '[{"id":1,"ref":"main","sha":"m3","status":"running"}]' | fixture api --hostname gitlab.com 'projects/acme%2Fapp/pipelines?per_page=100'
  run snap
  [ "$(jq -c .main <<<"$output")" = '{"pipeline":"none","sha":null}' ]
}

@test "gitlab snapshot: four reads, and a failed read fails the snapshot" {
  run snap
  [ "$status" -eq 0 ]
  [ "$(grep -c . "$GLAB_STUB_DIR/calls.log")" -eq 4 ]
  rm "$GLAB_STUB_DIR/api_hostname_gitlab_com_paginate_projects_acme_2Fapp_merge_requests_state_opened_per_page_100"
  run snap
  [ "$status" -ne 0 ]
  [[ "$output" == *"gitlab: cannot read the open merge requests"* ]] || false
}


github_world() {
  cfg_set '.tracker.provider = "github" | .tracker.host = "github.com"'
  export GH_STUB_DIR="$BATS_TEST_TMPDIR/gh"; mkdir -p "$GH_STUB_DIR"; : > "$GH_STUB_DIR/calls.log"
  ghfix() { local key; key="$(printf '%s ' "$@" | sed -E 's/[^A-Za-z0-9]+/_/g; s/_$//')"; cat > "$GH_STUB_DIR/$key"; }
  echo '{"default_branch":"main"}' | ghfix api --hostname github.com repos/acme/app
  ghfix api --hostname github.com --paginate 'repos/acme/app/issues?state=open&per_page=100' < "$F/gh-issues.json"
  ghfix api --hostname github.com --paginate 'repos/acme/app/pulls?state=open&per_page=100' < "$F/gh-pulls.json"
  ghfix api --hostname github.com 'repos/acme/app/actions/runs?per_page=100' < "$F/gh-runs.json"
}

@test "github snapshot: the same shape - pull requests are not work items, and runs are the pipeline" {
  github_world
  run snap
  [ "$status" -eq 0 ]
  [ "$(jq -c '.issues | map({iid, kind, state, dev, needs_human, blocked_by, ask_for})' <<<"$output")" = \
    '[{"iid":10,"kind":"story","state":"backlog","dev":"ana","needs_human":false,"blocked_by":[],"ask_for":null},{"iid":11,"kind":"story","state":"backlog","dev":"ana","needs_human":false,"blocked_by":[10],"ask_for":null},{"iid":12,"kind":"story","state":"building","dev":"rui","needs_human":true,"blocked_by":[],"ask_for":null},{"iid":20,"kind":"ask","state":null,"dev":null,"needs_human":true,"blocked_by":[],"ask_for":12},{"iid":30,"kind":"later","state":"after-mvp","dev":null,"needs_human":false,"blocked_by":[],"ask_for":null}]' ]
  [ "$(jq -c '.issues | map(.sprint)' <<<"$output")" = '[{"title":"S2","due":"2026-11-27"},null,null,null,null]' ]
  [ "$(jq -c '.mrs | map({iid, story, branch, draft, rework, pipeline, author})' <<<"$output")" = \
    '[{"iid":7,"story":13,"branch":"fix/login","draft":false,"rework":false,"pipeline":"success","author":"agent-rui"},{"iid":8,"story":12,"branch":"story/12-search","draft":false,"rework":true,"pipeline":"running","author":"agent-rui"}]' ]
  [ "$(jq -c .main <<<"$output")" = '{"pipeline":"failed","sha":"m2"}' ]
  [ "$(grep -c . "$GH_STUB_DIR/calls.log")" -eq 4 ]
}

@test "github snapshot: main is the newest commit whose push runs all finished" {
  github_world
  jq '.workflow_runs = [{"head_sha":"m3","head_branch":"main","event":"push","status":"queued","conclusion":null}] + .workflow_runs[1:]' "$F/gh-runs.json" |
    ghfix api --hostname github.com 'repos/acme/app/actions/runs?per_page=100'
  [ "$(snap | jq -c .main)" = '{"pipeline":"failed","sha":"m2"}' ]
  jq '.workflow_runs |= map(select(.head_sha != "m2"))' "$F/gh-runs.json" | ghfix api --hostname github.com 'repos/acme/app/actions/runs?per_page=100'
  [ "$(snap | jq -c .main)" = '{"pipeline":"success","sha":"m1"}' ]
  rm "$GH_STUB_DIR/api_hostname_github_com_paginate_repos_acme_app_pulls_state_open_per_page_100"
  run snap
  [ "$status" -ne 0 ]
  [[ "$output" == *"github: cannot read the open pull requests"* ]] || false
}
