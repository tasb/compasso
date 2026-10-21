#!/usr/bin/env bash
# The tracker adapter for this repository: tracker.provider in .compasso/project.yaml
# picks bin/tracker/gitlab.sh or bin/tracker/github.sh. Both take the same commands
# and options and print the same shapes; see either for the list.
#
#   tracker.sh <command> --repo R [options]
set -u
BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
case "${1:-}" in -h|--help) for f in "$0" "$BIN/tracker/gitlab.sh"; do sed -n '2,/^set -u/s/^# \{0,1\}//p' "$f"; done; exit 0 ;; esac   # its header, and the adapters' commands
case "${1:-}" in   # bin/team.sh's commands, which reach the tracker through its own checks
  add|list|assign|claim|release|msg|messages|inbox|working|mark-backlog|review|ask|update|return)
    echo "tracker: $1 is a bin/team.sh command: bash bin/team.sh $1 --repo R ... (bin/team.sh --help lists them)" >&2; exit 2 ;;
esac
repo="."
prev=""
for a in "$@"; do [ "$prev" = --repo ] && repo="$a"; prev="$a"; done
provider="$("$BIN/config.sh" get --repo "$repo" .tracker.provider 2>/dev/null)"
# the persona gate: what this checkout's persona may do on the tracker (bin/persona.sh)
case "$provider" in gitlab|github)
  ro=""; for a in "$@"; do [ "$a" = --read-only ] && ro=--read-only; done
  "$BIN/persona.sh" gate --repo "$repo" --tracker "${1:-}" $ro || exit $? ;;
esac
case "$provider" in
  gitlab|github) exec "$BIN/tracker/$provider.sh" "$@" ;;
  "") echo "tracker: no .compasso/project.yaml in $repo - run /compasso:setup" >&2; exit 1 ;;
  *) echo "tracker: unknown tracker.provider '$provider'" >&2; exit 1 ;;
esac
