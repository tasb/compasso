#!/usr/bin/env bats
load helper

setup() { setup_repo; }
p() { "$ROOT/bin/persona.sh" "$@" --repo "$REPO"; }
team_on() { cfg_set '.team.enabled = true'; }

@test "a checkout with no persona is default" {
  [ "$(p show)" = default ]
  [ "$(p show --json | jq -c '[.persona, .name, .team]')" = '["default",null,false]' ]
}

@test "set records the persona outside the repository; a home inside it is refused" {
  run p set --persona developer --name ana
  [ "$status" -eq 0 ]
  [ "$(p show)" = "developer ana" ]
  [ -z "$(grep -rl 'persona=developer' "$REPO" 2>/dev/null)" ]
  COMPASSO_HOME="$REPO/.compasso/home" run p show
  [ "$status" -eq 1 ]
  [[ "$output" == *"cannot live inside the repository"* ]] || false
}

@test "the persona is per checkout: another clone is still default" {
  p set --persona tech-lead >/dev/null
  mkdir -p "$BATS_TEST_TMPDIR/clone"
  [ "$("$ROOT/bin/persona.sh" show --repo "$BATS_TEST_TMPDIR/clone")" = default ]
}

@test "a developer needs a well-formed name; reserved words and other personas with a name are refused" {
  for n in "" Ana 1ana ana_b lead none default aaaaaaaaaaaaaaaaaaaaa; do
    run p set --persona developer --name "$n"
    [ "$status" -eq 2 ]
  done
  run p set --persona developer --name ana-2
  [ "$status" -eq 0 ]
  run p set --persona tech-lead --name ana
  [ "$status" -eq 2 ]
  run p set --persona boss
  [ "$status" -eq 2 ]
}

@test "join prints the developer's JSON, with no secret; only a developer joins" {
  run p join
  [ "$status" -eq 1 ]
  p set --persona developer --name ana >/dev/null
  run p join
  [ "$status" -eq 0 ]
  [ "$(jq -c '[.compasso, .name, .project, .harness]' <<<"$output")" = '["join","ana","acme/app","claude"]' ]
  [ "$(jq -r '.checkout | length' <<<"$output")" = 12 ]
  [ "$(jq -c 'keys' <<<"$output")" = '["checkout","compasso","harness","name","project"]' ]
}

@test "gate: without a team, default does everything except the poll" {
  for s in setup plan story sprint review harden; do p gate --skill "$s"; done
  for c in push-plan set-state open-mr sprint-sync followup; do p gate --tracker "$c"; done
  run p gate --skill work
  [ "$status" -eq 6 ]
}

@test "gate: a persona in a project with no team is refused, and told why" {
  p set --persona developer --name ana >/dev/null
  run p gate --skill story
  [ "$status" -eq 6 ]
  [[ "$output" == *"team.enabled is false"* ]] || false
}

@test "gate: in a team project the default persona only reads" {
  team_on
  for s in setup start status report present; do p gate --skill "$s"; done
  for s in plan story sprint review work harden; do run p gate --skill "$s"; [ "$status" -eq 6 ]; done
  for c in check story sprint-items labels comments mr-checks main-pipeline; do p gate --tracker "$c"; done
  p gate --tracker sprint-sync --read-only
  for c in sprint-sync push-plan set-state open-mr followup comment merge; do run p gate --tracker "$c"; [ "$status" -eq 6 ]; done
}

@test "gate: the tech lead plans and closes, and never builds a story" {
  team_on; p set --persona tech-lead >/dev/null
  for s in setup discover backlog architect roadmap plan feature review status report present harden sprint work; do p gate --skill "$s"; done
  run p gate --skill story
  [ "$status" -eq 6 ]
  [[ "$output" == *"never builds"* ]] || false
  for c in push-plan push-backlog ensure-labels protect set-state open-mr followup comment sprint-sync; do p gate --tracker "$c"; done
}

@test "gate: a developer builds and reviews, and never changes the scope" {
  team_on; p set --persona developer --name ana >/dev/null
  for s in setup start status story sprint review work; do p gate --skill "$s"; done
  for s in discover backlog architect roadmap plan feature harden report present; do run p gate --skill "$s"; [ "$status" -eq 6 ]; done
  for c in set-state open-mr followup comment sprint-sync story; do p gate --tracker "$c"; done
  for c in push-plan push-backlog ensure-labels protect; do run p gate --tracker "$c"; [ "$status" -eq 6 ]; done
}

@test "gate: the label and comment-delete primitives are never run through tracker.sh, by any persona" {
  for c in label label-create comment-delete comment-edit; do run p gate --tracker "$c"; [ "$status" -eq 6 ]; done
  team_on; p set --persona tech-lead >/dev/null
  for c in label label-create comment-delete comment-edit; do run p gate --tracker "$c"; [ "$status" -eq 6 ]; done
}

@test "gate: in a team project nobody merges through tracker.sh: the tech lead merges through team.sh; elsewhere merge is open" {
  run p gate --tracker merge
  [ "$status" -eq 0 ]
  team_on
  for who in "tech-lead" "developer --name ana"; do
    p set --persona $who >/dev/null
    run p gate --tracker merge
    [ "$status" -eq 6 ]
    [[ "$output" == *"team.sh merge"* ]] || false
    run p gate --tracker mr-update
    [ "$status" -eq 6 ]
    run p gate --tracker disarm
    [ "$status" -eq 6 ]
    [[ "$output" == *"team.sh main"* ]] || false
  done
  for c in mr-of mr-events; do run p gate --tracker "$c"; [ "$status" -eq 0 ]; done
}

@test "tracker.sh applies the gate before it reaches the tracker" {
  team_on; p set --persona developer --name ana >/dev/null
  export FAKE_GL="$BATS_TEST_TMPDIR/gl"; mkdir -p "$FAKE_GL"; : > "$FAKE_GL/calls.log"
  export PATH="$ROOT/tests/fake:$PATH"
  run "$ROOT/bin/tracker.sh" push-plan --repo "$REPO"
  [ "$status" -eq 6 ]
  [ ! -s "$FAKE_GL/calls.log" ]
  run "$ROOT/bin/tracker.sh" check --repo "$REPO"
  [ "$status" -eq 0 ]
}

@test "config: team.enabled and team.poll_minutes are validated" {
  "$ROOT/bin/config.sh" validate --repo "$REPO"
  cfg_set '.team.enabled = "yes"'
  run "$ROOT/bin/config.sh" validate --repo "$REPO"
  [ "$status" -eq 1 ]
  [[ "$output" == *"team.enabled"* ]] || false
  cfg_set '.team.enabled = true | .team.poll_minutes = 0'
  run "$ROOT/bin/config.sh" validate --repo "$REPO"
  [[ "$output" == *"team.poll_minutes"* ]] || false
}

@test "config upgrade adds the team keys to an older configuration" {
  cfg_set 'del(.team)'
  run "$ROOT/bin/config.sh" validate --repo "$REPO"
  [ "$status" -eq 1 ]
  "$ROOT/bin/config.sh" upgrade --repo "$REPO" >/dev/null
  [ "$(yq -r '.team.enabled' "$CFG")" = false ]
  "$ROOT/bin/config.sh" validate --repo "$REPO"
}

@test "every skill but setup runs the persona gate with its own name, and the gate knows it" {
  team_on
  for f in "$ROOT"/skills/*/SKILL.md; do
    n="$(basename "$(dirname "$f")")"
    [ "$n" = setup ] && continue
    grep -qF "persona.sh gate --repo . --skill $n\`" "$f" || { echo "$n has no persona gate"; false; }
    p set --persona tech-lead >/dev/null; lead=0; p gate --skill "$n" >/dev/null 2>&1 || lead=$?
    p set --persona developer --name ana >/dev/null; dev=0; p gate --skill "$n" >/dev/null 2>&1 || dev=$?
    [ "$lead" -eq 0 ] || [ "$dev" -eq 0 ] || { echo "$n: no persona may run it"; false; }
  done
}
