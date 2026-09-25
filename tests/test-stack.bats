#!/usr/bin/env bats
load helper

setup() {
  setup_repo
  cd "$REPO" && git init -q -b main
}
ts() { "$ROOT/bin/test-stack.sh" "$@" --repo "$REPO"; }
area() { ts detect --json | jq -r --arg l "$1" --arg a "$2" '.[] | select(.lang == $l) | .areas[$a] | "\(.use)|\(.source)"'; }
add() { mkdir -p "$(dirname "$1")"; printf '%s\n' "$2" > "$1"; git add "$1"; }

@test "what the project already uses always wins over the default" {
  add package.json '{"devDependencies": {"jest": "^29", "cypress": "^13"}, "scripts": {"cov": "jest --coverage"}}'
  [ "$(area js unit)" = "jest|existing" ]
  [ "$(area js api)" = "jest|existing" ]
  [ "$(area js e2e)" = "cypress|existing" ]
  [ "$(area js coverage)" = "jest-coverage|existing" ]
  [ "$(area js property)" = "fast-check|default" ]
}

@test "an area with nothing gets the language's default, with the coverage command and report" {
  add pyproject.toml '[project]
dependencies = ["fastapi"]
[project.optional-dependencies]
test = ["pytest", "hypothesis"]'
  [ "$(area python unit)" = "pytest|existing" ]
  [ "$(area python property)" = "hypothesis|existing" ]
  [ "$(area python e2e)" = "playwright (pytest-playwright)|default" ]
  [ "$(ts detect --json | jq -r '.[0].areas.coverage | [.command, .report] | join("|")')" = "pytest --cov --cov-report=xml|coverage.xml" ]
}

@test "signs are read from test files too, and API tests follow the unit framework unless something specific is found" {
  add go.mod 'module example.com/shop'
  add internal/cart/cart_test.go 'package cart
import ("testing"; "net/http/httptest")
func TestAdd(t *testing.T) { _ = httptest.NewRecorder() }'
  [ "$(area go unit)" = "go-test|existing" ]
  [ "$(area go api)" = "httptest|existing" ]
  [ "$(area go property)" = "rapid|default" ]
  [ "$(area go e2e)" = "playwright (TypeScript, e2e/)|default" ]
}

@test "the project's configured commands count as what it uses" {
  add package.json '{"name": "api"}'
  cfg_set '.commands.test = "node --test" | .commands.e2e = "npm run test:e2e" | .coverage.command = "npm run cov"'
  [ "$(area js unit)" = "the project's command: node --test|existing" ]
  [ "$(area js e2e)" = "the project's command: npm run test:e2e|existing" ]
  [ "$(area js coverage)" = "the project's command: npm run cov|existing" ]
}

@test "several languages are each reported; dependencies' own manifests are not the project" {
  add package.json '{"devDependencies": {"vitest": "1"}}'
  add go.mod 'module x'
  add node_modules/jest/package.json '{"name": "jest", "devDependencies": {"mocha": "1"}}'
  [ "$(ts detect --json | jq -c '[.[].lang]')" = '["js","go"]' ]
  [ "$(area js unit)" = "vitest|existing" ]
}

@test "shell scripts are a Bash project only when nothing else is found" {
  add bin/run.sh 'echo hi'
  [ "$(ts detect --json | jq -c '[.[].lang]')" = '["bash"]' ]
  [ "$(area bash unit)" = "bats-core|default" ]
  add package.json '{}'
  [ "$(ts detect --json | jq -c '[.[].lang]')" = '["js"]' ]
}

@test "a repository with no code yet says the walking skeleton picks the stack; defaults per language" {
  run ts detect
  [[ "$output" == *"No language found yet"* ]] || false
  run "$ROOT/bin/test-stack.sh" defaults --lang dotnet --json
  [ "$(jq -r '[.areas.unit.use, .areas.e2e.use, .areas.property.use] | join("|")' <<<"$output")" = "xunit|playwright (.NET)|fscheck" ]
  run "$ROOT/bin/test-stack.sh" defaults --lang cobol
  [ "$status" -eq 2 ]
}

@test "write records each area's framework and whether it is the project's or a default" {
  add package.json '{"devDependencies": {"mocha": "1"}}'
  run ts write
  [ "$status" -eq 0 ]
  [ "$(yq -o=json '.testing.js' "$CFG" | jq -c '[.unit, .property]')" = '[{"use":"mocha","source":"existing"},{"use":"fast-check","source":"default"}]' ]
  "$ROOT/bin/config.sh" validate --repo "$REPO" >/dev/null
}

@test "every language in the catalog has a default for every area" {
  run yq -o=json '[.languages[] | .areas | (.unit, .api, .e2e, .coverage, .property) | .default] | map(select(. == null or . == "")) | length' "$ROOT/templates/test-defaults.yaml"
  [ "$output" = 0 ]
  [ "$(yq '[.languages[].areas.coverage | select(.command == null or .report == null)] | length' "$ROOT/templates/test-defaults.yaml")" = 0 ]
}
