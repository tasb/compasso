#!/usr/bin/env bats
load helper

# a product repo on branch "work" with a local bare remote whose default branch is main
setup() {
  setup_repo
  cfg_set '.tracker.provider = "github" | .tracker.host = "github.com"'
  export FAKE_GH="$BATS_TEST_TMPDIR/gh"; mkdir -p "$FAKE_GH/issues"; : > "$FAKE_GH/calls.log"
  export PATH="$ROOT/tests/fake:$PATH"
  ORIGIN="$BATS_TEST_TMPDIR/origin.git"; git init -q --bare -b main "$ORIGIN"
  cd "$REPO" && git init -q -b main && git config user.email t@t && git config user.name t
  echo app > app.js && git add app.js && git commit -qm base && git remote add origin "$ORIGIN" && git push -q origin main
  git checkout -q -b work && echo wip > wip.js
  cp "$ROOT/tests/fixtures/plan.yaml" .compasso/plan.yaml
  mkdir -p .compasso/records/S20 && echo "# S20 plan" > .compasso/records/S20/plan.md
}
pr() { "$ROOT/bin/plan-pr.sh" --repo "$REPO" --title "Plan S20: invoices" "$@"; }
remote_files() { git -C "$ORIGIN" ls-tree -r --name-only "$1" | tr '\n' ' '; }

@test "the plan and the sprint's records go to plan/S<n> on top of the default branch, nothing else" {
  run pr
  [ "$status" -eq 0 ]
  [ "$(remote_files plan/S20)" = ".compasso/plan.yaml .compasso/records/S20/plan.md app.js " ]
  [ "$(git -C "$ORIGIN" log -1 --format=%s plan/S20)" = "Plan S20: invoices" ]
  [ "$(git -C "$ORIGIN" rev-parse plan/S20~1)" = "$(git -C "$ORIGIN" rev-parse main)" ]
  grep -q "POST repos/acme/app/pulls head=plan/S20 base=main title=Plan S20: invoices" "$FAKE_GH/calls.log"
}

@test "the current branch and working tree are left as they were" {
  pr >/dev/null
  [ "$(git -C "$REPO" branch --show-current)" = work ]
  [ "$(git -C "$REPO" status --porcelain | sort | tr '\n' ' ')" = "?? .compasso/ ?? wip.js " ]
  [ "$(git -C "$REPO" worktree list | wc -l | tr -d ' ')" = 1 ]
}

@test "a re-plan adds a commit on the open plan branch and updates its pull request" {
  pr >/dev/null
  echo '[{"number":40}]' > "$FAKE_GH/pr-query.json"
  echo "- a new decision" >> "$REPO/.compasso/records/S20/plan.md"
  run pr
  [ "$status" -eq 0 ]
  [ "$(git -C "$ORIGIN" rev-list --count main..plan/S20)" = 2 ]
  [ "$(grep -c 'POST repos/acme/app/pulls' "$FAKE_GH/calls.log")" = 1 ]
  grep -q "PATCH repos/acme/app/pulls/40" "$FAKE_GH/calls.log"
}

@test "a feature plan uses its own branch; without a title it refuses" {
  run pr --branch plan/S20-F-2
  [ "$status" -eq 0 ]
  [ -n "$(remote_files plan/S20-F-2)" ]
  run "$ROOT/bin/plan-pr.sh" --repo "$REPO"
  [ "$status" -eq 2 ]
}

@test "--include sends the product files on their own branch; paths outside the repository are refused" {
  mkdir -p .compasso/product .compasso/records/product
  echo "# Shop" > .compasso/product/brief.md; cp "$ROOT/tests/fixtures/backlog.yaml" .compasso/backlog.yaml
  echo "# discover" > .compasso/records/product/discover.md
  run "$ROOT/bin/plan-pr.sh" --repo "$REPO" --title "Product brief and backlog" --branch product/backlog \
    --include .compasso/product --include .compasso/backlog.yaml --include .compasso/records/product
  [ "$status" -eq 0 ]
  [ "$(remote_files product/backlog)" = ".compasso/backlog.yaml .compasso/product/brief.md .compasso/records/product/discover.md app.js " ]
  grep -q "head=product/backlog base=main title=Product brief and backlog" "$FAKE_GH/calls.log"
  run "$ROOT/bin/plan-pr.sh" --repo "$REPO" --title t --branch b --include ../secrets
  [ "$status" -eq 2 ]
  run "$ROOT/bin/plan-pr.sh" --repo "$REPO" --title t --include .compasso/backlog.yaml
  [ "$status" -eq 2 ]
}
