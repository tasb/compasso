#!/usr/bin/env bash
# The verify gate: the repo's own commands, then the story's Verify commands,
# then e2e when the story asks for it. Every command must pass.
#
#   verify.sh --repo R --run DIR [--story F]
#
# F is the JSON from `gitlab.sh story`. Each command runs with bash from the
# repo root; its output goes to DIR/verify-<n>.log and a summary to DIR/verify.json.
# The story's Verify commands come from the tracker, so each must first be approved for
# this checkout by a person (bin/trust.sh); an unapproved one stops verify before anything runs.
# Exit: 0 all passed | 1 a command failed, or the story needs e2e and there is no e2e command | 2 usage
#       4 a Verify command is not approved (listed)
set -u

BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="." RUN="" STORY=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --run) RUN="$2"; shift 2 ;;
    --story) STORY="$2"; shift 2 ;;
    *) echo "verify: unknown argument '$1'" >&2; exit 2 ;;
  esac
done
[ -n "$RUN" ] || { echo "verify: --run is required" >&2; exit 2; }
"$BIN/config.sh" validate --repo "$REPO" >/dev/null || exit 2
cfg() { "$BIN/config.sh" get --repo "$REPO" "$1"; }
mkdir -p "$RUN"

# "label<TAB>command" lines, in the order they run
plan="$(for k in test lint typecheck build; do c="$(cfg ".commands.$k")"; [ -n "$c" ] && printf '%s\t%s\n' "$k" "$c"; done)"
e2e_needed=0
if [ -n "$STORY" ]; then
  [ -f "$STORY" ] || { echo "verify: no story file $STORY" >&2; exit 2; }
  unapproved="$("$BIN/trust.sh" check --repo "$REPO" --story "$STORY")"; rc=$?
  case "$rc" in
    0) ;;
    3) echo "verify: STOP - the story's Verify commands below are not approved to run on this machine."
       printf '%s\n' "$unapproved" | sed 's/^/      /'
       echo "      Read them; if they are safe, a person approves them: bin/trust.sh approve --repo $REPO --story $STORY"
       exit 4 ;;
    *) exit 2 ;;
  esac
  plan="$plan"$'\n'"$(jq -r '.story.verify[] | "story\t\(.)"' "$STORY")"
  jq -e '.story.tests | index("e2e")' "$STORY" >/dev/null && e2e_needed=1
fi
if [ "$e2e_needed" -eq 1 ]; then
  c="$(cfg .commands.e2e)"
  [ -n "$c" ] || { echo "verify: FAIL - the story needs e2e tests but commands.e2e is empty in .compasso/project.yaml"; exit 1; }
  plan="$plan"$'\n'"$(printf 'e2e\t%s' "$c")"
fi

n=0 failed=0 results='[]'
while IFS=$'\t' read -r label cmd; do
  [ -n "$cmd" ] || continue
  n=$((n + 1))
  if ( cd "$REPO" && bash -c "$cmd" ) > "$RUN/verify-$n.log" 2>&1; then
    status=pass; echo "PASS  [$label] $cmd"
  else
    status=fail; failed=$((failed + 1)); echo "FAIL  [$label] $cmd"
    tail -n 20 "$RUN/verify-$n.log" | sed 's/^/      /'
  fi
  results="$(jq -c --arg l "$label" --arg c "$cmd" --arg s "$status" --arg log "verify-$n.log" \
    '. + [{label: $l, command: $c, status: $s, log: $log}]' <<<"$results")"
done <<EOF
$plan
EOF

printf '%s\n' "$results" > "$RUN/verify.json"
[ "$n" -gt 0 ] || { echo "verify: FAIL - nothing to run: no commands in .compasso/project.yaml and no Verify in the story"; exit 1; }
if [ "$failed" -gt 0 ]; then echo "verify: FAIL - $failed of $n commands failed"; exit 1; fi
echo "verify: all $n commands passed"
