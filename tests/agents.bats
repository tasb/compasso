#!/usr/bin/env bats
load helper

fm() { yq --front-matter=extract -r "$2" "$ROOT/agents/$1.md"; }

@test "agents/ is generated from roles/ and up to date" {
  run "$ROOT/bin/gen-agents.sh" --check
  [ "$status" -eq 0 ]
}

@test "every dispatched role is an agent; the planner runs in the conversation" {
  [ "$(ls "$ROOT/agents" | sort | tr '\n' ' ')" = "approver.md builder.md mutator.md reviewer.md security.md shipper.md tester.md " ]
}

@test "no agent can start another agent, and every agent has a turn limit" {
  for f in "$ROOT"/agents/*.md; do
    r="$(basename "$f" .md)"
    [[ ",$(fm "$r" .tools | tr -d ' ')," != *,Agent,* ]] || false
    [[ ",$(fm "$r" .tools | tr -d ' ')," != *,Task,* ]] || false
    [ "$(fm "$r" .maxTurns)" -gt 0 ]
  done
}

@test "security and the approver can only read; the reviewer can write lessons but not edit code or run commands" {
  [ "$(fm security .tools)" = "Read, Grep, Glob" ]
  [ "$(fm approver .tools)" = "Read, Grep, Glob" ]
  [ "$(fm reviewer .tools)" = "Read, Write, Grep, Glob" ]
}

@test "the default model is the template's; the role text is the agent's instructions" {
  for r in security tester shipper; do
    [ "$(fm "$r" .model)" = "$(yq -r ".models.claude.$r.model" "$ROOT/templates/project.yaml")" ]
  done
  grep -q "^# Security" "$ROOT/agents/security.md"
  grep -q "Security review is mandatory" "$ROOT/agents/security.md"
}

@test "the generator refuses a role that lists the Agent tool" {
  cp -R "$ROOT" "$BATS_TEST_TMPDIR/c"; rm -rf "$BATS_TEST_TMPDIR/c/.git"
  sed -i.bak 's/^tools: Read, Grep, Glob$/tools: Read, Grep, Glob, Agent/' "$BATS_TEST_TMPDIR/c/roles/security.md"
  run "$BATS_TEST_TMPDIR/c/bin/gen-agents.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"security may not have the Agent tool"* ]] || false
}

@test "--check notices a role edited without regenerating" {
  cp -R "$ROOT" "$BATS_TEST_TMPDIR/c"; rm -rf "$BATS_TEST_TMPDIR/c/.git"
  echo "- A new rule." >> "$BATS_TEST_TMPDIR/c/roles/tester.md"
  run "$BATS_TEST_TMPDIR/c/bin/gen-agents.sh" --check
  [ "$status" -eq 1 ]
  [[ "$output" == *"tester.md"* ]] || false
}
