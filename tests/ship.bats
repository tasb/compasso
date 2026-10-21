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
  jq -n '{iid: 8, title: "List API", kind: "story", feature: 6, estimate_h: 4, story: {key: "S-1"}}' > "$RUN/story.json"
  jq -n '[{by: "reviewer", severity: "minor", status: "open", needs: "the AWS organisation admin", file: "src/a.js", line: 3, summary: "The helper name is vague.", fix: "rename it to invoicesOf"},
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
  jq '. + [{by: "security", severity: "minor", status: "followup", verified_by: "security", needs: "a person", summary: "Errors show the stack trace.", fix: "log it instead"},
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
  grep -q '^- \[ \] Given `src/a.js:3`, When it is reviewed again, Then the finding "The helper name is vague." no longer applies' "$FAKE_GL/desc/$f"
  grep -qx -- '- `npm test`' "$FAKE_GL/desc/$f"
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
