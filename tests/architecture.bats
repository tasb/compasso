#!/usr/bin/env bats
load helper

setup() {
  setup_repo
  mkdir -p "$REPO/.compasso/product"
  cp "$ROOT/tests/fixtures/backlog.yaml" "$REPO/.compasso/backlog.yaml"
  A="$REPO/.compasso/product/architecture.yaml"; cp "$ROOT/tests/fixtures/architecture.yaml" "$A"
}
check() { "$ROOT/bin/architecture-check.sh" --repo "$REPO"; }

@test "a complete architecture passes; a decision without alternatives is a note" {
  run check
  [ "$status" -eq 0 ]
  [[ "$output" == *"valid (3 components, 1 decisions)"* ]] || false
  yq -i '.decisions[0].alternatives = []' "$A"
  run check
  [[ "$output" == *"note   decision \"One deployable app\" names no alternative"* ]] || false
}

@test "every MVP feature needs a component that serves it" {
  yq -i '.components[1].features = ["F-0", "F-1", "F-2"] | .components[2].features = []' "$A"
  run check
  [ "$status" -eq 1 ]
  [[ "$output" == *"MVP feature F-3 is served by no component"* ]] || false
}

@test "components talk only to components, and serve only backlog features" {
  yq -i '.components[0].talks_to = ["API", "Cache"] | .components[0].features += ["F-9"]' "$A"
  run check
  [[ "$output" == *"Web talks to Cache, which is not a component"* ]] || false
  [[ "$output" == *"Web serves F-9, which is not in the backlog"* ]] || false
}

@test "observability needs metrics and alerts; personal data needs a security control" {
  yq -i '.observability.alerts = [] | .security = [{"concern": "Card data", "control": "tokenised"}]' "$A"
  run check
  [ "$status" -eq 1 ]
  [[ "$output" == *"observability.alerts is empty"* ]] || false
  [[ "$output" == *"personal data is stored but no security control covers it"* ]] || false
}

@test "a dashboard may cite only screens of the prototype inventory" {
  echo '{"source": "code", "screens": [{"id": "obs-overview", "name": "Overview"}]}' > "$REPO/.compasso/product/prototype.json"
  yq -i '.product.prototype = {"kind": "code", "where": "docs/inputs", "inventory": ".compasso/product/prototype.json"}' "$REPO/.compasso/backlog.yaml"
  yq -i '.observability.dashboards[0].screen = "obs-latency"' "$A"
  run check
  [[ "$output" == *"cites screen obs-latency, which is not in the prototype inventory"* ]] || false
}

@test "decisions and the stack must say why" {
  yq -i '.decisions[0].why = "" | .stack[0].why = ""' "$A"
  run check
  [[ "$output" == *"every decision needs a title, a choice and why"* ]] || false
  [[ "$output" == *"stack: every layer needs a choice and why"* ]] || false
}
