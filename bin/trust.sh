#!/usr/bin/env bash
# Approval of the Verify commands a story asks verify.sh to run.
#
# A story's Verify commands come from its description on the tracker, so anyone who can
# edit the story could choose what runs on the machine building it. verify.sh runs a
# Verify command only once a person has approved that exact command for this checkout.
# Approvals live outside the repository, in ${COMPASSO_HOME:-$HOME/.compasso}/trust/,
# one file per checkout (keyed by its physical path), one line per command:
# "<sha256 of the command>  <command>". A cloned repository brings no approvals, and an
# edited command no longer matches.
#
#   trust.sh check   --repo R (--story F | --plan)   the Verify commands not yet approved
#   trust.sh approve --repo R (--story F | --plan)   approve them (after a person said yes)
#   trust.sh list    --repo R                        every approved command
#
# F is the JSON from `tracker.sh story`; --plan takes every story in .compasso/plan.yaml.
# Exit: 0 all approved | 3 some not approved (check; listed on stdout) | 1 failure | 2 usage
set -u

CMD="${1:-}"; shift || true
REPO="." STORY="" PLAN=0
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --story) STORY="$2"; shift 2 ;;
    --plan) PLAN=1; shift ;;
    *) echo "trust: unknown argument '$1'" >&2; exit 2 ;;
  esac
done
REPO="$(cd "$REPO" 2>/dev/null && pwd -P)" || { echo "trust: no repository" >&2; exit 2; }
HOME_DIR="${COMPASSO_HOME:-$HOME/.compasso}"
mkdir -p "$HOME_DIR/trust" || exit 1
HOME_DIR="$(cd "$HOME_DIR" && pwd -P)"
case "$HOME_DIR/" in "$REPO/"*) echo "trust: approvals cannot live inside the repository they approve ($HOME_DIR)" >&2; exit 1 ;; esac
sha() { printf '%s' "$1" | shasum -a 256 | cut -d' ' -f1; }
FILE="$HOME_DIR/trust/$(sha "$REPO")"

commands() { # the Verify commands asked for, one per line
  if [ -n "$STORY" ]; then
    [ -f "$STORY" ] || { echo "trust: no story file $STORY" >&2; return 1; }
    jq -r '.story.verify // [] | .[]' "$STORY"
  elif [ "$PLAN" -eq 1 ]; then
    [ -f "$REPO/.compasso/plan.yaml" ] || { echo "trust: no .compasso/plan.yaml" >&2; return 1; }
    yq -o=json '[.features[].stories[].verify // [] | .[]]' "$REPO/.compasso/plan.yaml" | jq -r '.[]'
  else
    echo "trust: $CMD needs --story or --plan" >&2; return 2
  fi
}
approved() { [ -f "$FILE" ] && cut -d' ' -f1 "$FILE" | grep -qxF "$(sha "$1")"; }

case "$CMD" in
  check)
    list="$(commands)" || exit $?
    missing=0
    while IFS= read -r c; do
      [ -n "$c" ] || continue
      approved "$c" || { printf '%s\n' "$c"; missing=1; }
    done <<EOF
$(printf '%s\n' "$list" | awk '!seen[$0]++')
EOF
    [ "$missing" -eq 0 ] || exit 3 ;;
  approve)
    list="$(commands)" || exit $?
    n=0
    while IFS= read -r c; do
      [ -n "$c" ] || continue
      approved "$c" && continue
      printf '%s  %s\n' "$(sha "$c")" "$c" >> "$FILE" || exit 1
      n=$((n + 1))
    done <<EOF
$(printf '%s\n' "$list" | awk '!seen[$0]++')
EOF
    echo "trust: $n command(s) approved for $REPO" ;;
  list)
    [ -f "$FILE" ] && cut -d' ' -f3- "$FILE" ;;
  *) echo "usage: trust.sh check|approve|list --repo R [--story F | --plan]" >&2; exit 2 ;;
esac
