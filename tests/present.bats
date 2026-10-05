#!/usr/bin/env bats
load helper

setup() {
  setup_repo
  cfg_set '.tracker.provider = "github" | .tracker.host = "github.com"'
  mkdir -p "$REPO/.compasso/product" "$REPO/.compasso/records/product"
  cp "$ROOT/tests/fixtures/backlog.yaml" "$REPO/.compasso/backlog.yaml"
  printf '# Shop\n\n## Problem\nShops lose **orders**.\n\n## Users\n- Customers\n' > "$REPO/.compasso/product/brief.md"
  OUT="$BATS_TEST_TMPDIR/p.html"; D="$BATS_TEST_TMPDIR/d.json"
}
present() { "$ROOT/bin/present.sh" --repo "$REPO" --out "$OUT" --data-out "$D" "$@"; }

@test "with only a brief and a backlog it still builds, and says on the page what is missing" {
  run present
  [ "$status" -eq 0 ]
  [ "$(jq -c '[.name, (.brief.sections | map(.title)), (.features | length), .architecture, .roadmap, .plan]' "$D")" = '["Shop",["Problem","Users"],6,null,null,null]' ]
  grep -q 'missingArchitecture' "$OUT"
  [ "$(grep -c '__PRESENTATION_DATA__' "$OUT")" -eq 0 ]
}

@test "everything Compasso wrote is in it: architecture, sprints, the planned stories with tracker links, decisions" {
  cp "$ROOT/tests/fixtures/architecture.yaml" "$REPO/.compasso/product/architecture.yaml"
  "$ROOT/bin/roadmap.sh" propose --repo "$REPO" --write >/dev/null
  cp "$ROOT/tests/fixtures/plan.yaml" "$REPO/.compasso/plan.yaml"; yq -i '.features[0].stories[0].gitlab = 6' "$REPO/.compasso/plan.yaml"
  printf '# Discover\n\n## Decisions\n- Stripe for payments (@tasb, 2026-10-03)\n\n## Takeaways\n- None\n' > "$REPO/.compasso/records/product/discover.md"
  present >/dev/null
  [ "$(jq -c '[(.architecture.components | length), (.roadmap.sprints | length), .roadmap.mvp_sprint]' "$D")" = '[3,3,2]' ]
  [ "$(jq -r '.plan.features[0].stories[0] | [.key, .url] | join(" ")' "$D")" = "S-1 https://github.com/acme/app/issues/6" ]
  [ "$(jq -r '.plan.features[0].stories[1].url' "$D")" = null ]
  [ "$(jq -c '.decisions' "$D")" = '[{"source":"product/discover.md","text":"Stripe for payments (@tasb, 2026-10-03)"}]' ]
}

@test "text from the documents can never end the data block or run as code" {
  yq -i '.features[0].title = "</script><script>alert(1)</script>"' "$REPO/.compasso/backlog.yaml"
  present >/dev/null
  [ "$(grep -c 'alert(1)' "$OUT")" -eq 1 ] && [ "$(grep -c '<script>alert' "$OUT")" -eq 0 ]
  [ "$(grep -o '<script' "$OUT" | wc -l | tr -d ' ')" = 2 ]
  [ "$(jq -r '.features[0].title' "$D")" = "</script><script>alert(1)</script>" ]
}

@test "labels can be replaced for another language" {
  echo '{"sprints": "Sprints", "stories": "Histórias de utilizador"}' > "$BATS_TEST_TMPDIR/ui.json"
  present --ui "$BATS_TEST_TMPDIR/ui.json" >/dev/null
  [ "$(jq -r '.ui.stories' "$D")" = "Histórias de utilizador" ]
}

@test "nothing to present, an invalid input, or no --out is refused" {
  rm "$REPO/.compasso/backlog.yaml" "$REPO/.compasso/product/brief.md"
  run present
  [ "$status" -eq 1 ]
  [[ "$output" == *"run /compasso:discover and /compasso:backlog first"* ]] || false
  run "$ROOT/bin/present.sh" --repo "$REPO"
  [ "$status" -eq 2 ]
}

@test "a large plan (1.4 MB) builds a complete page, never an empty one" {
  yq -i '.features[].goal = ("x" * 200000)' "$REPO/.compasso/backlog.yaml"
  run present
  [ "$status" -eq 0 ]
  [ "$(wc -c < "$OUT" | tr -d ' ')" -gt 1200000 ]
  [ "$(jq '[.features[].goal | length] | add' "$D")" -eq 1200000 ]
  grep -q '<title>Shop · Solution</title>' "$OUT"
}
