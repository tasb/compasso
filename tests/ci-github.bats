#!/usr/bin/env bats
load helper

setup() {
  setup_repo
  cfg_set '.tracker.provider = "github" | .ci.image = "node:22" | .commands.test = "npm test"'
  OUT="$REPO/.github/workflows/compasso.yml"
}
ci() { "$ROOT/bin/ci.sh" --repo "$REPO" "$@"; }
job() { yq -r "$1" "$OUT"; }

@test "a GitHub project gets a pull request workflow instead of a GitLab pipeline" {
  run ci --scans github
  [ "$status" -eq 0 ]
  [ -f "$OUT" ]
  [ ! -e "$REPO/.gitlab" ]
  [ "$(job '.on | keys | join(",")')" = pull_request ]
  [ "$(job '.permissions.contents')" = read ]
}

@test "verify runs the repo's commands in order in the CI image" {
  cfg_set '.commands.lint = "npm run lint" | .commands.build = "npm run build"'
  ci --scans github >/dev/null
  [ "$(job '.jobs.compasso-verify.container')" = "node:22" ]
  [ "$(job '[.jobs.compasso-verify.steps[] | select(.run) | .run] | join(" | ")')" = "npm test | npm run lint | npm run build" ]
}

@test "e2e and coverage jobs exist only with their commands; coverage only warns" {
  ci --scans github >/dev/null
  [ "$(job '.jobs | keys | join(",")')" = compasso-verify ]
  cfg_set '.commands.e2e = "npx playwright test" | .coverage.command = "npm run cov" | .coverage.report = "coverage/cobertura.xml"'
  ci --scans github >/dev/null
  [ "$(job '.jobs | keys | join(",")')" = "compasso-verify,compasso-e2e,compasso-coverage,compasso-coverage-check" ]
  job '.jobs.compasso-coverage-check.steps[-1].run' | grep -q -- '--fail-under=80 ||'
  job '.jobs.compasso-coverage-check.steps[-1].run' | grep -q '::warning'
}

@test "with GitHub's scans there is no Compasso scan gate; without them there is" {
  ci --scans github >/dev/null
  [ "$(job '.jobs.compasso-scan-gate')" = null ]
  ci --scans compasso >/dev/null
  [ "$(job '.jobs.compasso-scan-gate.steps | length')" = 3 ]
}

@test "without --scans, the choice follows the repository's code scanning" {
  export FAKE_GH="$BATS_TEST_TMPDIR/gh" PATH="$ROOT/tests/fake:$PATH"
  mkdir -p "$FAKE_GH"
  echo '{"id":7,"visibility":"private","permissions":{"push":true}}' > "$FAKE_GH/repo.json"
  cfg_set '.tracker.github.project = 0'
  run ci
  [ "$status" -eq 0 ]
  [[ "$output" == *"scans: compasso"* ]] || false
  echo '{"id":7,"visibility":"public","permissions":{"push":true}}' > "$FAKE_GH/repo.json"
  [[ "$(ci)" == *"scans: github"* ]] || false
}

# the scan gate's steps, run for real against a docker stub that writes the scanner report
gate_step() { # step-name report-file report-json -> runs the step in a temp checkout
  local d="$BATS_TEST_TMPDIR/checkout"; mkdir -p "$d" "$BATS_TEST_TMPDIR/bin"
  printf '#!/usr/bin/env bash\ncat > "%s/%s" <<"J"\n%s\nJ\n' "$d" "$2" "$3" > "$BATS_TEST_TMPDIR/bin/docker"; chmod +x "$BATS_TEST_TMPDIR/bin/docker"
  job ".jobs.compasso-scan-gate.steps[] | select(.name == \"$1\") | .run" | sed 's/\${{[^}]*}}/sha/g' > "$BATS_TEST_TMPDIR/step.sh"
  (cd "$d" && PATH="$BATS_TEST_TMPDIR/bin:$PATH" bash -e "$BATS_TEST_TMPDIR/step.sh")
}

@test "scan gate: any secret blocks, none passes" {
  ci --scans compasso >/dev/null
  run gate_step "Secrets (Gitleaks)" gitleaks.json '[{"RuleID":"aws-key","File":"a.js","StartLine":3}]'
  [ "$status" -eq 1 ]
  [[ "$output" == *"[secret] aws-key (a.js:3)"* ]] || false
  run gate_step "Secrets (Gitleaks)" gitleaks.json '[]'
  [ "$status" -eq 0 ]
}

@test "scan gate: a high Semgrep finding blocks, a warning does not" {
  ci --scans compasso >/dev/null
  run gate_step "Code (Semgrep)" semgrep.json '{"results":[{"check_id":"sqli","path":"db.js","start":{"line":9},"extra":{"severity":"ERROR"}}]}'
  [ "$status" -eq 1 ]
  [[ "$output" == *"[high] sqli (db.js:9)"* ]] || false
  run gate_step "Code (Semgrep)" semgrep.json '{"results":[{"check_id":"style","path":"a.js","start":{"line":1},"extra":{"severity":"WARNING"}}]}'
  [ "$status" -eq 0 ]
}
