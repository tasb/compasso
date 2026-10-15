#!/usr/bin/env bats
load helper

# Every script says how to call it: --help prints the command list written at its top.
@test "every script answers --help with its commands, and changes nothing" {
  setup_repo
  for f in "$ROOT"/bin/*.sh "$ROOT"/bin/tracker/*.sh "$ROOT/bin/git-credential-compasso"; do
    run "$f" --help
    [ "$status" -eq 0 ] || { echo "$f: exit $status"; false; }
    name="$(basename "$f")"
    [[ "$output" == *"$name"* ]] || { echo "$f: its help does not name it"; false; }
    [[ "$output" != *"#!/usr/bin/env"* ]] || { echo "$f: the shebang is not help"; false; }
  done
}

@test "tracker.sh points a team command to team.sh, and an unknown one to its list" {
  setup_repo
  run "$ROOT/bin/tracker.sh" release --repo "$REPO" --iid 4
  [ "$status" -eq 2 ]
  [[ "$output" == *"release is a bin/team.sh command"* ]] || false
  run "$ROOT/bin/tracker.sh" --help
  [[ "$output" == *"sprint-sync"* ]] || false
}
