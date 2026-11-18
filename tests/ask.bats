#!/usr/bin/env bats
load helper

# bin/human.sh ask: the one way an agent reaches a person - a needs::human issue with what is
# needed, why, numbered steps and what the agent does meanwhile; the story it holds back gets
# needs::human too, so no job picks the story up until the person closes the issue.
setup() {
  setup_repo
  cfg_set '.people.ask = ["ana"]'
  export FAKE_GL="$BATS_TEST_TMPDIR/gl"; mkdir -p "$FAKE_GL"; : > "$FAKE_GL/calls.log"
  export PATH="$ROOT/tests/fake:$PATH"
  Q="$BATS_TEST_TMPDIR/q.json"
  cat > "$Q" <<'EOF'
{"need": "The AWS region for staging.",
 "why": ["Story #12 deploys to staging, and no region is set in infra/staging.tfvars."],
 "steps": ["Pick a region, e.g. eu-west-1.", "Write it in a comment on this issue."],
 "meanwhile": "I build the other stories assigned to me."}
EOF
}
ask() { "$ROOT/bin/human.sh" ask --repo "$REPO" --key region --story 12 --title "Which AWS region for staging?" --from "$Q" "$@"; }

@test "the issue says what, why, the steps and what the agent does meanwhile; closing it is the last step" {
  run ask
  [ "$status" -eq 0 ]
  [ "$(jq -c '{iid, created}' <<<"$output")" = '{"iid":1,"created":true}' ]
  body="$(cat "$FAKE_GL/desc/1.md")"
  [[ "$body" == "<!-- compasso:ask story=12 key=region -->"* ]] || false
  [[ "$body" == *$'**What I need:** The AWS region for staging.'* ]] || false
  [[ "$body" == *$'**Story:** #12'* ]] || false
  [[ "$body" == *$'**Why**\n- Story #12 deploys to staging, and no region is set in infra/staging.tfvars.'* ]] || false
  [[ "$body" == *$'**Steps**\n1. Pick a region, e.g. eu-west-1.\n2. Write it in a comment on this issue.\n3. Close this issue: that is how the agent knows you are done.'* ]] || false
  [[ "$body" == *$'**Meanwhile:** I build the other stories assigned to me.'* ]] || false
}

@test "the issue is labelled needs::human and assigned to people.ask; the story gets needs::human" {
  ask >/dev/null
  grep -q 'POST projects/acme%2Fapp/issues title=Which AWS region for staging? issue_type=issue labels=needs::human assignee_ids\[\]=77' "$FAKE_GL/calls.log"
  [ "$(cat "$FAKE_GL/labels/12")" = needs::human ]
}

@test "asking again with the same key updates the open issue instead of opening another" {
  ask >/dev/null
  jq -n --rawfile d "$FAKE_GL/desc/1.md" '[{iid: 1, web_url: "u", labels: ["needs::human"], description: $d}]' > "$FAKE_GL/issue-query.json"
  jq '.need = "The AWS region, again."' "$Q" > "$Q.2" && mv "$Q.2" "$Q"
  run ask
  [ "$status" -eq 0 ]
  [ "$(jq -c '{iid, created}' <<<"$output")" = '{"iid":1,"created":false}' ]
  [ "$(grep -c 'POST projects/acme%2Fapp/issues ' "$FAKE_GL/calls.log")" -eq 1 ]
  grep -q 'The AWS region, again.' "$FAKE_GL/desc/1.md"
}

@test "a question for no story holds nothing back; no one in people.ask leaves it unassigned" {
  cfg_set '.people.ask = []'
  "$ROOT/bin/human.sh" ask --repo "$REPO" --key budget --title "Monthly budget?" --from "$Q" >/dev/null
  head -1 "$FAKE_GL/desc/1.md" | grep -qx '<!-- compasso:ask story= key=budget -->'
  ! grep -q 'assignee_ids' "$FAKE_GL/calls.log" || false
  ! grep -q 'Story:' "$FAKE_GL/desc/1.md" || false
  [ ! -e "$FAKE_GL/labels/12" ]
}

@test "a question without what, why, steps or meanwhile is refused before anything is posted" {
  for k in need why steps meanwhile; do
    jq --arg k "$k" 'if (.[$k] | type) == "array" then .[$k] = [] else .[$k] = "" end' "$Q" > "$BATS_TEST_TMPDIR/bad.json"
    run "$ROOT/bin/human.sh" ask --repo "$REPO" --key k --title t --from "$BATS_TEST_TMPDIR/bad.json"
    [ "$status" -eq 1 ]
    [[ "$output" == *"human: the question needs $k"* ]] || false
  done
  [ ! -s "$FAKE_GL/calls.log" ]
}

@test "the issue is written in the project's language" {
  cfg_set '.language = "pt-BR"'
  ask >/dev/null
  grep -q '^\*\*O que preciso:\*\* ' "$FAKE_GL/desc/1.md"
  grep -q 'Feche esta issue' "$FAKE_GL/desc/1.md"
}

@test "github: the same issue, labelled and assigned; the story gets needs::human" {
  cfg_set '.tracker.provider = "github" | .tracker.host = "github.com"'
  export FAKE_GH="$BATS_TEST_TMPDIR/gh"; mkdir -p "$FAKE_GH/issues"; : > "$FAKE_GH/calls.log"; echo 20 > "$FAKE_GH/next_number"
  echo '{"number":12,"title":"Search","state":"open","labels":[],"body":""}' > "$FAKE_GH/issues/12.json"
  run ask
  [ "$status" -eq 0 ]
  [ "$(jq -c '{iid, created}' <<<"$output")" = '{"iid":20,"created":true}' ]
  [ "$(jq -r '.labels | map(.name) | join(",")' "$FAKE_GH/issues/20.json")" = needs::human ]
  grep -q 'POST repos/acme/app/issues .*assignees\[\]=ana' "$FAKE_GH/calls.log"
  [ "$(jq -r '.labels | map(.name) | join(",")' "$FAKE_GH/issues/12.json")" = needs::human ]
  run ask
  [ "$(jq -c '{iid, created}' <<<"$output")" = '{"iid":20,"created":false}' ]
}

@test "human-done: an answered question frees its story, on both trackers" {
  "$ROOT/bin/tracker.sh" human-done --repo "$REPO" --iid 12
  grep -q 'PUT projects/acme%2Fapp/issues/12 remove_labels=needs::human' "$FAKE_GL/calls.log"
  cfg_set '.tracker.provider = "github" | .tracker.host = "github.com"'
  export FAKE_GH="$BATS_TEST_TMPDIR/gh"; mkdir -p "$FAKE_GH/issues"; : > "$FAKE_GH/calls.log"
  echo '{"number":12,"title":"Search","state":"open","labels":[{"name":"needs::human"},{"name":"type::story"}],"body":""}' > "$FAKE_GH/issues/12.json"
  "$ROOT/bin/tracker.sh" human-done --repo "$REPO" --iid 12
  [ "$(jq -r '.labels | map(.name) | join(",")' "$FAKE_GH/issues/12.json")" = type::story ]
}
