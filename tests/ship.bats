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
  jq -n '[{by: "reviewer", severity: "minor", status: "open", file: "src/a.js", line: 3, summary: "The helper name is vague.", fix: "rename it to invoicesOf"},
          {by: "reviewer", severity: "major", status: "fixed", summary: "off by one"},
          {by: "security", severity: "minor", status: "fixed", verified_by: "security", summary: "verbose error"}]' > "$RUN/findings.json"
  echo "- GET /invoices lists the caller's invoices" > "$RUN/changes.md"
}
ship() { "$ROOT/bin/ship.sh" --repo "$REPO" --run "$RUN"; }

@test "open minor findings become backlog stories under the feature, and are marked as followed up" {
  run ship
  [ "$status" -eq 0 ]
  grep -q "POST projects/acme%2Fapp/issues title=The helper name is vague. issue_type=task labels=owner::either" "$FAKE_GL/calls.log"
  [ "$(grep -c 'milestone_id' "$FAKE_GL/calls.log")" -eq 0 ]
  [ "$(jq -c '[.[] | select(.severity == "minor" and .by == "reviewer") | [.status, (.followup_iid | type)]]' "$RUN/findings.json")" = '[["followup","number"]]' ]
  [ "$(jq -r '.[1].status' "$RUN/findings.json")" = fixed ]
  [ "$(grep -c 'POST projects/acme%2Fapp/issues ' "$FAKE_GL/calls.log")" -eq 1 ]
  [ "$(jq -c '.[2] | [.status, .followup_iid]' "$RUN/findings.json")" = '["fixed",null]' ]
}

@test "the follow-up is a story in the Story format" {
  ship >/dev/null
  f="$(ls "$FAKE_GL/desc/")"
  grep -q '^\*\*As\*\* a maintainer \*\*I want\*\* rename it to invoicesOf \*\*so that\*\* the helper name is vague no longer applies\.' "$FAKE_GL/desc/$f"
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
