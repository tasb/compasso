#!/usr/bin/env bats
load helper

setup() { setup_repo; setup_glab_stub; }
gl() { "$ROOT/bin/tracker/gitlab.sh" "$@" --repo "$REPO"; }

@test "check on a free namespace reports the free tier and its limits" {
  gitlab_world 30 free
  run gl check
  [ "$status" -eq 0 ]
  [ "$(jq -r .tier <<<"$output")" = free ]
  [ "$(jq -r .capabilities.blocking_links <<<"$output")" = false ]
  [ "$(jq -r .capabilities.child_tasks <<<"$output")" = true ]
}

@test "check on a premium or ultimate namespace reports premium" {
  gitlab_world 40 ultimate
  run gl check
  [ "$status" -eq 0 ]
  [ "$(jq -r .tier <<<"$output")" = premium ]
  [ "$(jq -r .capabilities.epics <<<"$output")" = true ]
}

@test "an explicit tier overrides detection" {
  gitlab_world 30 ""
  cfg_set '.tracker.tier = "premium"'
  run gl check
  [ "$status" -eq 0 ]
  [ "$(jq -r .tier <<<"$output")" = premium ]
}

@test "an undetectable tier exits 5 and says what to set" {
  gitlab_world 30 ""
  run gl check
  [ "$status" -eq 5 ]
  [[ "$output" == *"tracker.tier"* ]] || false
}

@test "not logged in exits 2 with the login command" {
  run gl check
  [ "$status" -eq 2 ]
  [[ "$output" == *"glab auth login --hostname gitlab.com --web"* ]] || false
}

@test "an unknown or inaccessible project exits 3" {
  echo '{"username":"dev"}' | fixture api --hostname gitlab.com user
  run gl check
  [ "$status" -eq 3 ]
  [[ "$output" == *"acme/app"* ]] || false
}

@test "a Reporter is refused: Compasso needs Developer" {
  gitlab_world 20 free
  run gl check
  [ "$status" -eq 4 ]
  [[ "$output" == *"Developer"* ]] || false
}

@test "group access counts when it is higher than project access" {
  gitlab_world 0 free
  echo '{"id":7,"namespace":{"id":9},"permissions":{"project_access":null,"group_access":{"access_level":40}}}' |
    fixture api --hostname gitlab.com projects/acme%2Fapp
  run gl check
  [ "$status" -eq 0 ]
  [ "$(jq -r .access_level <<<"$output")" = 40 ]
}

@test "an invalid config stops the adapter before any GitLab call" {
  cfg_set '.approvals.plan = "x"'
  run gl check
  [ "$status" -eq 1 ]
  [ ! -s "$GLAB_STUB_DIR/calls.log" ]
}

@test "ensure-labels creates only the missing labels" {
  gitlab_world 30 free
  echo '[{"name":"compasso::new"},{"name":"unblocked"}]' |
    fixture api --hostname gitlab.com --paginate 'projects/acme%2Fapp/labels?per_page=100'
  export GLAB_STUB_POST_OK=1
  run gl ensure-labels
  [ "$status" -eq 0 ]
  [[ "$output" == *"18 created, 1 already present"* ]] || false
  [ "$(grep -c -- '-X POST' "$GLAB_STUB_DIR/calls.log")" -eq 18 ]
  [ "$(grep -c 'name=compasso::new ' "$GLAB_STUB_DIR/calls.log")" -eq 0 ]
  grep -q 'name=blocked ' "$GLAB_STUB_DIR/calls.log"
}

@test "ensure-labels stops when a label cannot be created" {
  gitlab_world 30 free
  echo '[]' | fixture api --hostname gitlab.com --paginate 'projects/acme%2Fapp/labels?per_page=100'
  run gl ensure-labels
  [ "$status" -eq 1 ]
  [[ "$output" == *"could not create label"* ]] || false
}

@test "a self-managed host is passed to every glab call" {
  cfg_set '.tracker.host = "git.example.com"'
  run gl check
  [ "$status" -eq 2 ]
  [[ "$output" == *"--hostname git.example.com"* ]] || false
  grep -q -- '--hostname git.example.com' "$GLAB_STUB_DIR/calls.log"
}
