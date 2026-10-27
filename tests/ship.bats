#!/usr/bin/env bats
load helper

setup() {
  setup_repo
  cd "$REPO" && git init -q -b main && git config user.email t@t && git config user.name t
  printf '.compasso/runs/\n' > .gitignore && mkdir -p src && echo a > src/a.js && git add . && git commit -qm base
  cfg_set '.commands.test = "npm test"'; git commit -qam config
  export FAKE_GL="$BATS_TEST_TMPDIR/gl"; mkdir -p "$FAKE_GL/issues" "$FAKE_GL/parent"; : > "$FAKE_GL/calls.log"
  export PATH="$ROOT/tests/fake:$PATH"
  echo '{"iid":6,"id":1006,"milestone":{"id":501}}' > "$FAKE_GL/issues/6.json"
  RUN="$REPO/.compasso/runs/8"; mkdir -p "$RUN"
  jq -n '{iid: 8, title: "List API", kind: "story", feature: 6, estimate_h: 4, story: {key: "S-1", verify: ["npm test -- invoices"]}}' > "$RUN/story.json"
  jq -n '[{by: "reviewer", severity: "minor", status: "open", needs: "the AWS organisation admin", file: "src/a.js", line: 3, summary: "The helper name is vague.", fix: "rename it to invoicesOf",
           acceptance: "Given src/a.js, When the helper is called, Then it is named invoicesOf"},
          {by: "reviewer", severity: "major", status: "fixed", summary: "off by one"},
          {by: "security", severity: "minor", status: "fixed", verified_by: "security", summary: "verbose error"}]' > "$RUN/findings.json"
  echo "- GET /invoices lists the caller's invoices" > "$RUN/changes.md"
}
ship() { "$ROOT/bin/ship.sh" --repo "$REPO" --run "$RUN"; }

@test "a minor finding whose fix needs someone else becomes a story for a person in the sprint, marked as followed up" {
  run ship
  [ "$status" -eq 0 ]
  grep -q "POST projects/acme%2Fapp/issues title=The helper name is vague. milestone_id=501 issue_type=task labels=owner::human" "$FAKE_GL/calls.log"
  [ "$(jq -c '[.[] | select(.severity == "minor" and .by == "reviewer") | [.status, (.followup_iid | type)]]' "$RUN/findings.json")" = '[["followup","number"]]' ]
  [ "$(jq -r '.[1].status' "$RUN/findings.json")" = fixed ]
  [ "$(grep -c 'POST projects/acme%2Fapp/issues ' "$FAKE_GL/calls.log")" -eq 1 ]
  [ "$(jq -c '.[2] | [.status, .followup_iid]' "$RUN/findings.json")" = '["fixed",null]' ]
}

@test "only findings whose fix needs someone else are filed" {
  jq '.[0] |= del(.needs)' "$RUN/findings.json" > "$RUN/f" && mv "$RUN/f" "$RUN/findings.json"
  run ship
  [ "$status" -eq 0 ]
  [ "$(grep -c 'POST projects/acme%2Fapp/issues ' "$FAKE_GL/calls.log")" -eq 0 ]
  [ "$(jq -r '.[0].status' "$RUN/findings.json")" = open ]
}

@test "a team project files it for a person too" {
  cfg_set '.team.enabled = true'
  "$ROOT/bin/persona.sh" set --repo "$REPO" --persona developer --name rui >/dev/null
  run ship
  [ "$status" -eq 0 ]
  grep -q "POST projects/acme%2Fapp/issues title=The helper name is vague. milestone_id=501 issue_type=task labels=owner::human" "$FAKE_GL/calls.log"
}

@test "a minor security finding that security deferred becomes a follow-up too; one already filed does not" {
  jq '. + [{by: "security", severity: "minor", status: "followup", verified_by: "security", needs: "a person", summary: "Errors show the stack trace.", fix: "log it instead", acceptance: "Given an error, When GET /x fails, Then no stack trace is shown"},
           {by: "security", severity: "minor", status: "followup", verified_by: "security", followup_iid: 40, summary: "filed before"}]' "$RUN/findings.json" > "$RUN/f" && mv "$RUN/f" "$RUN/findings.json"
  run ship
  [ "$status" -eq 0 ]
  grep -q "POST projects/acme%2Fapp/issues title=Errors show the stack trace. milestone_id=501 issue_type=task labels=owner::human" "$FAKE_GL/calls.log"
  [ "$(grep -c 'POST projects/acme%2Fapp/issues ' "$FAKE_GL/calls.log")" -eq 2 ]
  [ "$(jq -c '.[3] | [.status, .verified_by, (.followup_iid | type)]' "$RUN/findings.json")" = '["followup","security","number"]' ]
  [ "$(jq -c '.[4].followup_iid' "$RUN/findings.json")" = 40 ]
}

@test "the follow-up is a story in the Story format" {
  ship >/dev/null
  f="$(ls "$FAKE_GL/desc/")"
  grep -q '^\*\*As\*\* the AWS organisation admin \*\*I want\*\* rename it to invoicesOf \*\*so that\*\* the helper name is vague no longer applies\.' "$FAKE_GL/desc/$f"
  grep -qx -- '- \[ \] Given src/a.js, When the helper is called, Then it is named invoicesOf' "$FAKE_GL/desc/$f"
  ! grep -q "reviewed again" "$FAKE_GL/desc/$f"
  # Verify: the repo's tests and the story's own, each a command that runs
  [ "$(sed -n '/^## Verify/,/^$/p' "$FAKE_GL/desc/$f" | grep -c '^- `')" -eq 2 ]
  grep -qx -- '- `npm test`' "$FAKE_GL/desc/$f"
  grep -qx -- '- `npm test -- invoices`' "$FAKE_GL/desc/$f"
}

@test "a follow-up never gets a Verify that is not a command: with no test command it carries the story's" {
  cfg_set '.commands.test = ""'; git commit -qam "no test command"
  ship >/dev/null
  f="$(ls "$FAKE_GL/desc/")"
  [ "$(sed -n '/^## Verify/,/^$/p' "$FAKE_GL/desc/$f" | grep '^- `')" = '- `npm test -- invoices`' ]
}

@test "in mvp the story's open minors become one issue for after the MVP, in no sprint; production files none" {
  cfg_set '.stage = "mvp"'; git commit -qam mvp
  jq '. + [{by: "reviewer", severity: "minor", status: "open", file: "src/a.js", line: 9, summary: "Docstring says 200 but it is 204.", acceptance: "Given DELETE /x, When it succeeds, Then the docstring says 204"},
           {by: "security", severity: "minor", status: "open", summary: "The id is echoed in the error.", acceptance: "Given an unknown id, When GET /x/9, Then the error does not echo the id"},
           {by: "reviewer", severity: "minor", status: "fixed", summary: "already fixed"}]' "$RUN/findings.json" > "$RUN/f" && mv "$RUN/f" "$RUN/findings.json"
  run ship
  [ "$status" -eq 0 ]
  # the one whose fix needs a person, as before, and one issue for the two left for later
  [ "$(grep -c 'POST projects/acme%2Fapp/issues ' "$FAKE_GL/calls.log")" -eq 2 ]
  grep -q "POST projects/acme%2Fapp/issues title=Minor findings of #8: List API issue_type=task labels=compasso::after-mvp" "$FAKE_GL/calls.log"
  ! grep "title=Minor findings" "$FAKE_GL/calls.log" | grep -q milestone_id
  n="$(jq -r '.[3].followup_iid' "$RUN/findings.json")"
  [ "$(jq -c '[.[3], .[4]] | map([.status, .followup_iid])' "$RUN/findings.json")" = "[[\"followup\",$n],[\"followup\",$n]]" ]
  [ "$(jq -c '.[5] | [.status, .followup_iid]' "$RUN/findings.json")" = '["fixed",null]' ]
  [ "$(grep -c '^- \[ \] ' "$FAKE_GL/desc/$n.md")" -eq 2 ]
  grep -qx -- '- \[ \] Given an unknown id, When GET /x/9, Then the error does not echo the id' "$FAKE_GL/desc/$n.md"
  grep -qx -- '- `npm test -- invoices`' "$FAKE_GL/desc/$n.md"
  [[ "$output" == *"ship: 2 minor findings filed for after the MVP as #$n"* ]] || false
}

@test "in mvp a story with no open minor files no issue for after the MVP" {
  cfg_set '.stage = "mvp"'; git commit -qam mvp
  jq '.[0] |= (.status = "fixed")' "$RUN/findings.json" > "$RUN/f" && mv "$RUN/f" "$RUN/findings.json"
  run ship
  [ "$status" -eq 0 ]
  [ "$(grep -c 'POST projects/acme%2Fapp/issues ' "$FAKE_GL/calls.log")" -eq 0 ]
}

@test "the story's metrics, record and lessons are committed, and nothing else" {
  mkdir -p docs/learnings && printf -- '---\ntitle: t\npaths: []\nroles: [builder]\ndate: 2026-09-25\n---\nLesson.\n' > docs/learnings/l.md
  echo stray > stray.txt
  run ship
  [ "$status" -eq 0 ]
  [ "$(git log -1 --format=%s)" = "Record the metrics, decisions and lessons of #8" ]
  [ "$(git show --name-only --format= HEAD | sort | tr '\n' ' ')" = ".compasso/metrics/8.json .compasso/records/backlog/stories/8.md docs/learnings/l.md " ]
  [ "$(git status --porcelain stray.txt)" = "?? stray.txt" ]
}

@test "without the builder's Changes list it refuses" {
  : > "$RUN/changes.md"
  run ship
  [ "$status" -eq 2 ]
  [[ "$output" == *"changes.md is empty"* ]] || false
}
