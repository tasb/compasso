ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

setup_repo() {
  REPO="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$REPO"
  "$ROOT/bin/config.sh" init --repo "$REPO" --project acme/app >/dev/null
  CFG="$REPO/.compasso/project.yaml"
}

# set a config value: cfg_set '.sprint.weeks = 3'
cfg_set() { yq -i "$1" "$CFG"; }

setup_glab_stub() {
  export GLAB_STUB_DIR="$BATS_TEST_TMPDIR/glab"
  mkdir -p "$GLAB_STUB_DIR"
  : > "$GLAB_STUB_DIR/calls.log"
  export PATH="$ROOT/tests/stubs:$PATH"
}

# fixture <glab args...> -- answer the call with stdin
fixture() {
  local key
  key="$(printf '%s ' "$@" | sed -E 's/[^A-Za-z0-9]+/_/g; s/_$//')"
  cat > "$GLAB_STUB_DIR/$key"
}

# a logged-in user with <level> on acme/app in a namespace on <plan>
gitlab_world() {
  local level="$1" plan="$2"
  echo '{"username":"dev"}' | fixture api --hostname gitlab.com user
  printf '{"id":7,"namespace":{"id":9},"permissions":{"project_access":{"access_level":%s},"group_access":null}}' "$level" |
    fixture api --hostname gitlab.com projects/acme%2Fapp
  printf '{"plan":"%s"}' "$plan" | fixture api --hostname gitlab.com namespaces/9
}
