#!/usr/bin/env bats
load helper

setup() {
  setup_repo
  B="$REPO/.compasso/backlog.yaml"; cp "$ROOT/tests/fixtures/backlog.yaml" "$B"
}
check() { "$ROOT/bin/backlog-check.sh" --repo "$REPO" "$@"; }
rm_() { "$ROOT/bin/roadmap.sh" "$@" --repo "$REPO"; }

# ---------- backlog-check ----------

@test "backlog-check: a sound backlog passes with the MVP's size" {
  run check
  [ "$status" -eq 0 ]
  [[ "$output" == *"MVP: 4 of 6 features, 112h (about 2 sprint(s) at 80h)"* ]] || false
  [[ "$output" == *"note   F-3 is sensitive"* ]] || false
}

@test "backlog-check: incomplete, oversized, unknown and cyclic features are errors" {
  yq -i '.features[1].acceptance = [] | .features[2].size_h = 41 | .features[4].depends_on = ["F-9"] | .features[0].depends_on = ["F-2"]' "$B"
  run check
  [ "$status" -eq 1 ]
  [[ "$output" == *"F-1: needs at least one acceptance line"* ]] || false
  [[ "$output" == *"F-2: 41h is more than half a sprint (40h) - split it"* ]] || false
  [[ "$output" == *"F-4: depends on F-9, which is not in the backlog"* ]] || false
  [[ "$output" == *"dependency cycle among: F-0, F-1, F-2, F-3"* ]] || false
}

@test "backlog-check: the MVP may not depend on work after the MVP line" {
  yq -i '.features[3].depends_on = ["F-2", "F-4"]' "$B"
  run check
  [ "$status" -eq 1 ]
  [[ "$output" == *"F-3 is in the MVP but depends on F-4, which is not"* ]] || false
}

@test "backlog-check: every prototype screen belongs to a feature" {
  mkdir -p "$REPO/.compasso/product"
  echo '{"source":"url","screens":[{"id":"catalog"},{"id":"cart"},{"id":"help"}]}' > "$REPO/.compasso/product/prototype.json"
  yq -i '.product.prototype = {"kind": "url", "where": "https://proto.example", "inventory": ".compasso/product/prototype.json"}
    | .features[1].sources = ["screen: catalog"] | .features[2].sources = ["screen: cart", "screen: basket"]' "$B"
  run check
  [ "$status" -eq 0 ]
  [[ "$output" == *"prototype screen help is in no feature"* ]] || false
  [[ "$output" == *"a feature cites screen basket, which is not in the prototype inventory"* ]] || false
  [[ "$output" != *"screen catalog is in no feature"* ]] || false
}

# ---------- roadmap ----------

@test "roadmap propose: MVP first by dependency and capacity; the rest only after the MVP line" {
  run rm_ propose
  [ "$status" -eq 0 ]
  run rm_ propose --write
  [ "$(yq -o=json . "$REPO/.compasso/roadmap.yaml" | jq -c '[.sprints[] | {n: .number, f: .features, h: .hours}]')" = \
    '[{"n":1,"f":["F-0","F-1","F-2"],"h":72},{"n":2,"f":["F-3"],"h":40},{"n":3,"f":["F-4","F-5"],"h":40}]' ]
  [ "$(yq .mvp_sprint "$REPO/.compasso/roadmap.yaml")" = 2 ]
}

@test "roadmap propose: a smaller capacity spreads the work; the capacity can come from velocity" {
  rm_ propose --capacity 40 --write >/dev/null
  [ "$(yq -o=json -I0 '[.sprints[].features]' "$REPO/.compasso/roadmap.yaml")" = '[["F-0","F-1"],["F-2"],["F-3"],["F-4","F-5"]]' ]
  [ "$(yq .mvp_sprint "$REPO/.compasso/roadmap.yaml")" = 3 ]
}

@test "roadmap check: goals, capacity, dependency order and the MVP line" {
  rm_ propose --write >/dev/null
  run rm_ check
  [ "$status" -eq 1 ]
  [[ "$output" == *"sprint 1 has no goal"* ]] || false
  yq -i '.sprints[].goal = "g"' "$REPO/.compasso/roadmap.yaml"
  run rm_ check
  [ "$status" -eq 0 ]
  yq -i '.sprints[0].features = ["F-0", "F-1"] | .sprints[0].hours = 40 | .sprints[2].features = ["F-2", "F-4", "F-5"] | .sprints[2].hours = 72' "$REPO/.compasso/roadmap.yaml"
  run rm_ check
  [ "$status" -eq 1 ]
  [[ "$output" == *"F-3 (sprint 2) depends on F-2, planned later (sprint 3)"* ]] || false
  [[ "$output" == *"F-2 is in the MVP but planned after the MVP sprint (2)"* ]] || false
}

@test "roadmap: re-planning keeps the sprints already under way and keeps unchanged goals" {
  rm_ propose --write >/dev/null
  yq -i 'with(.sprints[]; .goal = "goal " + (.number | to_string))' "$REPO/.compasso/roadmap.yaml"
  cp "$ROOT/tests/fixtures/plan.yaml" "$REPO/.compasso/plan.yaml"; yq -i '.epic.sprint.number = 1' "$REPO/.compasso/plan.yaml"
  yq -i '.features += [{"key": "F-6", "title": "Search", "goal": "Find products", "scope": ["search"], "acceptance": ["Given 2, When I search, Then 1"], "size_h": 8, "mvp": true, "depends_on": ["F-1"], "sensitive": false, "sources": [], "gitlab": null}]' "$B"
  rm_ propose --write >/dev/null
  [ "$(yq -o=json . "$REPO/.compasso/roadmap.yaml" | jq -c '[.sprints[] | {n: .number, f: .features, g: .goal}]')" = \
    '[{"n":1,"f":["F-0","F-1","F-2"],"g":"goal 1"},{"n":2,"f":["F-3","F-6"],"g":""},{"n":3,"f":["F-4","F-5"],"g":"goal 3"}]' ]
}

@test "roadmap next: the sprint after the one planned, with its features from the backlog" {
  rm_ propose --write >/dev/null
  run rm_ next
  [ "$status" -eq 0 ]
  [ "$(jq -c '[.number, .mvp, [.features[].title]]' <<<"$output")" = '[1,false,["Walking skeleton","Catalog","Cart"]]' ]
  cp "$ROOT/tests/fixtures/plan.yaml" "$REPO/.compasso/plan.yaml"; yq -i '.epic.sprint.number = 1' "$REPO/.compasso/plan.yaml"
  [ "$(rm_ next | jq -c '[.number, .mvp]')" = '[2,true]' ]
  yq -i '.epic.sprint.number = 3' "$REPO/.compasso/plan.yaml"
  run rm_ next
  [ "$status" -eq 3 ]
}

@test "roadmap: refused while the backlog does not pass its check" {
  yq -i '.features[0].title = ""' "$B"
  run rm_ propose
  [ "$status" -eq 1 ]
  [[ "$output" == *"does not pass backlog-check"* ]] || false
}
