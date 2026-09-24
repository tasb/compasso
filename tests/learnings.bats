#!/usr/bin/env bats
load helper

setup() {
  REPO="$BATS_TEST_TMPDIR/repo"; mkdir -p "$REPO/docs/learnings" "$REPO/src/billing" "$REPO/src/ui"
  cd "$REPO" && git init -q && touch src/billing/a.js src/ui/b.js && git add . && git -c user.email=t@t -c user.name=t commit -qm base
}
lesson() { # file title paths roles [body]
  printf -- '---\ntitle: %s\npaths: %s\nroles: %s\ndate: 2026-09-24\nsource: "#8"\n---\n%s\n' "$2" "$3" "$4" "${5:-Do the right thing.}" > "$REPO/docs/learnings/$1.md"
}
story() { echo "{\"story\":{\"touches\":$1}}" > "$BATS_TEST_TMPDIR/s.json"; }
recall() { "$ROOT/bin/learnings.sh" recall --repo "$REPO" "$@"; }

@test "recall gives a role the lessons whose paths overlap the story's" {
  lesson billing "Billing lesson" '["src/billing/**"]' '[security]'
  lesson ui "UI lesson" '["src/ui/**"]' '[security]'
  story '["src/billing/filter/**"]'
  run recall --role security --story "$BATS_TEST_TMPDIR/s.json"
  [[ "$output" == *"## Billing lesson"* ]] || false
  [[ "$output" != *"UI lesson"* ]] || false
}

@test "overlap works in both directions" {
  lesson narrow "Narrow lesson" '["src/billing/filter/**"]' '[builder]'
  story '["src/billing/**"]'
  run recall --role builder --story "$BATS_TEST_TMPDIR/s.json"
  [[ "$output" == *"## Narrow lesson"* ]] || false
}

@test "recall leaves out lessons for other roles" {
  lesson billing "Billing lesson" '["src/billing/**"]' '[security]'
  story '["src/billing/**"]'
  run recall --role tester --story "$BATS_TEST_TMPDIR/s.json"
  [ -z "$output" ]
}

@test "a lesson with no paths applies everywhere" {
  lesson any "Everywhere lesson" '[]' '[reviewer]'
  story '["docs/**"]'
  run recall --role reviewer --story "$BATS_TEST_TMPDIR/s.json"
  [[ "$output" == *"## Everywhere lesson"* ]] || false
}

@test "without a story, every lesson for the role (the planner's case)" {
  lesson billing "Billing lesson" '["src/billing/**"]' '[planner]'
  lesson ui "UI lesson" '["src/ui/**"]' '[planner]'
  run recall --role planner
  [[ "$output" == *"Billing lesson"* ]] || false
  [[ "$output" == *"UI lesson"* ]] || false
}

@test "no learnings folder is simply no lessons" {
  rm -rf "$REPO/docs/learnings"
  run recall --role security
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "check passes well-formed lessons" {
  lesson billing "Billing lesson" '["src/billing/**"]' '[security, builder]'
  run "$ROOT/bin/learnings.sh" check --repo "$REPO"
  [ "$status" -eq 0 ]
  [[ "$output" == *"1 lessons checked"* ]] || false
}

@test "check names every problem in a malformed lesson" {
  lesson bad "" '"src"' '[hacker]'
  run "$ROOT/bin/learnings.sh" check --repo "$REPO"
  [ "$status" -eq 1 ]
  [[ "$output" == *"docs/learnings/bad.md: title is required"* ]] || false
  [[ "$output" == *"unknown role hacker"* ]] || false
  [[ "$output" == *"paths must be a list"* ]] || false
}

@test "check keeps lessons short" {
  lesson long "Long lesson" '[]' '[builder]' "$(printf 'line %s\n' 1 2 3 4 5 6)"
  run "$ROOT/bin/learnings.sh" check --repo "$REPO"
  [ "$status" -eq 1 ]
  [[ "$output" == *"the lesson has 6 lines; keep it to 5"* ]] || false
}

@test "check flags a lesson whose paths no longer match any file" {
  lesson gone "Gone lesson" '["src/payments/**"]' '[builder]'
  lesson live "Live lesson" '["src/ui/**"]' '[builder]'
  run "$ROOT/bin/learnings.sh" check --repo "$REPO"
  [ "$status" -eq 0 ]
  [[ "$output" == *"gone.md: stale"* ]] || false
  [[ "$output" != *"live.md: stale"* ]] || false
}
