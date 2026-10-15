#!/usr/bin/env bats
load helper

# One tracker account per agent: its token reaches every tracker call and git, and its commits carry the
# agent's name and email. The tokens live in the Compasso home ($COMPASSO_HOME, outside the repository).
setup() {
  setup_repo
  cd "$REPO" && git init -q -b main && git remote add origin https://gitlab.com/acme/app.git
  export GIT_CONFIG_GLOBAL="$BATS_TEST_TMPDIR/gitconfig" GIT_TERMINAL_PROMPT=0
  printf '[credential]\n\thelper = "!f() { echo username=someone; echo password=the-persons-token; }; f"\n' > "$GIT_CONFIG_GLOBAL"
  export FAKE_GL="$BATS_TEST_TMPDIR/gl" FAKE_GH="$BATS_TEST_TMPDIR/gh"; mkdir -p "$FAKE_GL" "$FAKE_GH"; : > "$FAKE_GL/calls.log"
  export PATH="$ROOT/tests/fake:$PATH"
  p set --persona developer --name ana >/dev/null || true
}
p() { "$ROOT/bin/persona.sh" "$1" --repo "$REPO" "${@:2}"; }
token_file() { # login mode
  mkdir -p "$COMPASSO_HOME/accounts/gitlab.com"; printf 'glpat-%s' "$1" > "$COMPASSO_HOME/accounts/gitlab.com/$1"; chmod "$2" "$COMPASSO_HOME/accounts/gitlab.com/$1"
}
fill() { printf 'protocol=https\nhost=%s\n\n' "$1" | git -C "$REPO" credential fill 2>/dev/null; }

@test "GitLab: the account needs its token file, readable by its owner only" {
  cfg_set '.team.enabled = true'
  run p account --set svc-ana --email ana@agents.example
  [ "$status" -eq 1 ]
  [[ "$output" == *"$COMPASSO_HOME/accounts/gitlab.com/svc-ana"* ]] || false
  token_file svc-ana 644
  run p account --set svc-ana --email ana@agents.example
  [ "$status" -eq 1 ]
  [[ "$output" == *"chmod 600"* ]] || false
  chmod 600 "$COMPASSO_HOME/accounts/gitlab.com/svc-ana"
  run p account --set svc-ana --email ana@agents.example
  [ "$status" -eq 0 ]
  [ "$(p show --json | jq -c '[.account, .email]')" = '["svc-ana","ana@agents.example"]' ]
}

@test "an account needs a well-formed login and an email" {
  cfg_set '.team.enabled = true'; token_file svc-ana 600
  run p account --set svc-ana
  [ "$status" -eq 2 ]
  run p account --set svc-ana --email not-an-email
  [ "$status" -eq 2 ]
  run p account --set 'svc ana' --email ana@agents.example
  [ "$status" -eq 2 ]
}

@test "git uses the account's token for the tracker's host, not the person's, and its commits carry the agent's name and email" {
  cfg_set '.team.enabled = true'; token_file svc-ana 600
  p account --set svc-ana --email ana@agents.example >/dev/null
  [ "$(fill gitlab.com | sed -n 's/^password=//p')" = glpat-svc-ana ]
  [ "$(fill gitlab.com | sed -n 's/^username=//p')" = svc-ana ]
  [ "$(git -C "$REPO" config --local user.name)" = ana ]
  [ "$(git -C "$REPO" config --local user.email)" = ana@agents.example ]
  # another host keeps whatever the machine has
  [ "$(fill example.org | sed -n 's/^password=//p')" = the-persons-token ]
}

@test "the helper lives in the Compasso home, so a plugin update does not move it" {
  cfg_set '.team.enabled = true'; token_file svc-ana 600
  p account --set svc-ana --email ana@agents.example >/dev/null
  h="$(git -C "$REPO" config --local --get-all credential.https://gitlab.com.helper | tail -1)"
  [[ "$h" == *"$COMPASSO_HOME/bin/git-credential-compasso"* ]] || false
  [ -x "$COMPASSO_HOME/bin/git-credential-compasso" ]
}

@test "every tracker call uses the account's token; changing the account changes it at the next call" {
  cfg_set '.team.enabled = true'; token_file svc-ana 600; token_file svc-ana2 600
  "$ROOT/bin/tracker.sh" check --repo "$REPO" >/dev/null 2>&1 || true
  [ "$(cat "$FAKE_GL/token")" = "" ]
  p account --set svc-ana --email ana@agents.example >/dev/null
  "$ROOT/bin/tracker.sh" check --repo "$REPO" >/dev/null 2>&1 || true
  [ "$(cat "$FAKE_GL/token")" = glpat-svc-ana ]
  p account --set svc-ana2 --email ana@agents.example >/dev/null
  "$ROOT/bin/team.sh" list --repo "$REPO" >/dev/null 2>&1 || true
  [ "$(cat "$FAKE_GL/token")" = glpat-svc-ana2 ]
}

@test "GitHub: the account is one gh holds; its token reaches gh and git" {
  cfg_set '.tracker.provider = "github" | .tracker.host = "github.com" | .team.enabled = true'
  git -C "$REPO" remote set-url origin https://github.com/acme/app.git
  run env FAKE_GH_NO_USER=svc-bot "$ROOT/bin/persona.sh" account --repo "$REPO" --set svc-bot --email bot@agents.example
  [ "$status" -eq 1 ]
  [[ "$output" == *"gh auth login --hostname github.com"* ]] || false
  p account --set svc-bot --email bot@agents.example >/dev/null
  [ "$(fill github.com | sed -n 's/^password=//p')" = gho_svc-bot ]
  "$ROOT/bin/tracker.sh" check --repo "$REPO" >/dev/null 2>&1 || true
  [ "$(cat "$FAKE_GH/token")" = gho_svc-bot ]
}

@test "the tech lead's and the default persona's commits carry their own names" {
  token_file svc-lead 600
  cfg_set '.team.enabled = true'; p set --persona tech-lead >/dev/null
  p account --set svc-lead --email lead@agents.example >/dev/null
  [ "$(git -C "$REPO" config --local user.name)" = tech-lead ]
  cfg_set '.team.enabled = false'; p set --persona default >/dev/null
  p account --set svc-lead --email lead@agents.example >/dev/null
  [ "$(git -C "$REPO" config --local user.name)" = svc-lead ]
}

@test "a developer's join block carries its account, and the tech lead adds it to team.agents" {
  cfg_set '.tracker.provider = "github" | .tracker.host = "github.com" | .team.enabled = true'
  p account --set svc-ana --email ana@agents.example >/dev/null
  p join > "$BATS_TEST_TMPDIR/join.json"
  [ "$(jq -r .account "$BATS_TEST_TMPDIR/join.json")" = svc-ana ]
  [ "$(jq -r '.token // "none"' "$BATS_TEST_TMPDIR/join.json")" = none ]
  LEAD="$BATS_TEST_TMPDIR/lead"; mkdir -p "$LEAD"; cp -R "$REPO/.compasso" "$LEAD/"
  "$ROOT/bin/persona.sh" set --repo "$LEAD" --persona tech-lead >/dev/null
  touch "$FAKE_GH/labels.txt"
  "$ROOT/bin/team.sh" add --repo "$LEAD" --join "$BATS_TEST_TMPDIR/join.json" >/dev/null
  [ "$(yq -o=json -I0 .team.agents "$LEAD/.compasso/project.yaml")" = '["svc-ana"]' ]
  "$ROOT/bin/team.sh" add --repo "$LEAD" --join "$BATS_TEST_TMPDIR/join.json" >/dev/null 2>&1 || true
  [ "$(yq -o=json -I0 .team.agents "$LEAD/.compasso/project.yaml")" = '["svc-ana"]' ]
}

@test "a checkout with no account works as before: no token is set, git is left alone" {
  run "$ROOT/bin/persona.sh" env --repo "$REPO"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -z "$(git -C "$REPO" config --local --get-all credential.https://gitlab.com.helper)" ]
}
