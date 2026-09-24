#!/usr/bin/env bats
load helper

setup() {
  setup_repo
  cfg_set '.ci.image = "node:22" | .commands.test = "npm test"'
  OUT="$REPO/.gitlab/compasso.gitlab-ci.yml"
}
ci() { "$ROOT/bin/ci.sh" --repo "$REPO"; }
job() { yq -r "$1" "$OUT"; }

@test "without an image it refuses and says what to set" {
  cfg_set '.ci.image = ""'
  run ci
  [ "$status" -eq 1 ]
  [[ "$output" == *"set ci.image"* ]] || false
}

@test "without any verify command it refuses" {
  cfg_set '.commands.test = ""'
  run ci
  [ "$status" -eq 1 ]
}

@test "verify runs the repo's commands in order, on merge requests only, with the security scans" {
  cfg_set '.commands.lint = "npm run lint" | .commands.build = "npm run build"'
  ci >/dev/null
  [ "$(job '.compasso-verify.script | join(" | ")')" = "npm test | npm run lint | npm run build" ]
  [ "$(job '.compasso-verify.image')" = "node:22" ]
  [ "$(job '.compasso-verify.extends')" = ".compasso-mr" ]
  [ "$(job '.".compasso-mr".rules[0].if')" = '$CI_PIPELINE_SOURCE == "merge_request_event"' ]
  [ "$(job '.include | map(.template) | join(" ")')" = "Jobs/SAST.gitlab-ci.yml Jobs/Secret-Detection.gitlab-ci.yml" ]
  [ "$(job '.variables.AST_ENABLE_MR_PIPELINES')" = "true" ]
}

@test "the e2e job exists only with an e2e command, and is a gate" {
  ci >/dev/null
  [ "$(job '.compasso-e2e')" = null ]
  cfg_set '.commands.e2e = "npx playwright test"'
  ci >/dev/null
  [ "$(job '.compasso-e2e.script[0]')" = "npx playwright test" ]
  [ "$(job '.compasso-e2e.allow_failure')" = null ]
}

@test "coverage is a warning: its check may fail only with exit 3, at the project threshold" {
  cfg_set '.coverage.command = "npm test -- --coverage" | .coverage.report = "coverage/cobertura.xml" | .coverage.min_changed = 75'
  ci >/dev/null
  [ "$(job '.compasso-coverage-check.allow_failure.exit_codes[0]')" = 3 ]
  [[ "$(job '.compasso-coverage-check.script[2]')" == *"--fail-under=75 || exit 3" ]] || false
  [ "$(job '.compasso-coverage.artifacts.reports.coverage_report.coverage_format')" = cobertura ]
}

@test "an LCOV report gets no coverage visualisation (GitLab reads Cobertura)" {
  cfg_set '.coverage.command = "npm test -- --coverage" | .coverage.report = "coverage/lcov.info"'
  ci >/dev/null
  [ "$(job '.compasso-coverage.artifacts.reports')" = null ]
  [ "$(job '.compasso-coverage.artifacts.paths[0]')" = "coverage/lcov.info" ]
}

@test "no coverage command, no coverage jobs" {
  ci >/dev/null
  [ "$(job '.compasso-coverage')" = null ]
  [ "$(job '.compasso-coverage-check')" = null ]
}

@test "commands with YAML-special characters survive exactly" {
  cfg_set '.commands.test = "pytest -k \"not slow\" --cov: x # y"'
  ci >/dev/null
  [ "$(job '.compasso-verify.script[0]')" = 'pytest -k "not slow" --cov: x # y' ]
}

# ---------- scan gate ----------

gate() { # run the generated gate script in a directory holding the given reports
  ci >/dev/null
  mkdir -p "$BATS_TEST_TMPDIR/job" && cd "$BATS_TEST_TMPDIR/job"
  yq -r '.compasso-scan-gate.script[1]' "$OUT" > gate.sh
  bash gate.sh
}
report() { # file severity...
  local f="$1"; shift
  jq -n --args '{vulnerabilities: ($ARGS.positional | to_entries | map({id: "v\(.key)", name: "finding \(.key)", severity: .value, location: {file: "src/a.js", start_line: (.key + 1)}}))}' "$@" \
    > "$BATS_TEST_TMPDIR/job/$f"
}

@test "the scan gate is a blocking last-stage job, and the scans keep their reports readable" {
  ci >/dev/null
  [ "$(job '.compasso-scan-gate.stage')" = ".post" ]
  [ "$(job '.compasso-scan-gate.allow_failure')" = null ]
  [ "$(job '.compasso-scan-gate.extends')" = ".compasso-mr" ]
  [ "$(job '.semgrep-sast.artifacts.paths[0]')" = "gl-sast-report.json" ]
  [ "$(job '.secret_detection.artifacts.paths[0]')" = "gl-secret-detection-report.json" ]
}

@test "the scan gate passes when the scans found nothing high or critical" {
  mkdir -p "$BATS_TEST_TMPDIR/job"
  report gl-sast-report.json Low Medium Info
  report gl-secret-detection-report.json
  run gate
  [ "$status" -eq 0 ]
  [[ "$output" == *"no high or critical findings"* ]] || false
}

@test "the scan gate fails on a high SAST finding and names it" {
  mkdir -p "$BATS_TEST_TMPDIR/job"
  report gl-sast-report.json Low High
  report gl-secret-detection-report.json
  run gate
  [ "$status" -eq 1 ]
  [[ "$output" == *"[High] finding 1 (src/a.js:2)"* ]] || false
  [[ "$output" != *"[Low]"* ]] || false
}

@test "the scan gate fails on a leaked secret" {
  mkdir -p "$BATS_TEST_TMPDIR/job"
  report gl-secret-detection-report.json Critical
  run gate
  [ "$status" -eq 1 ]
  [[ "$output" == *"[Critical]"* ]] || false
}

@test "the scan gate fails closed when secret detection did not run" {
  mkdir -p "$BATS_TEST_TMPDIR/job"
  report gl-sast-report.json Low
  run gate
  [ "$status" -eq 1 ]
  [[ "$output" == *"no secret detection report"* ]] || false
}

@test "the scan gate tolerates no SAST report when no analyzer applies" {
  mkdir -p "$BATS_TEST_TMPDIR/job"
  report gl-secret-detection-report.json
  run gate
  [ "$status" -eq 0 ]
  [[ "$output" == *"no SAST report"* ]] || false
}
