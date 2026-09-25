#!/usr/bin/env bash
# The tracker adapter for this repository: tracker.provider in .compasso/project.yaml
# picks bin/tracker/gitlab.sh or bin/tracker/github.sh. Both take the same commands
# and options and print the same shapes; see either for the list.
#
#   tracker.sh <command> --repo R [options]
set -u
BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="."
prev=""
for a in "$@"; do [ "$prev" = --repo ] && repo="$a"; prev="$a"; done
provider="$("$BIN/config.sh" get --repo "$repo" .tracker.provider 2>/dev/null)"
case "$provider" in
  gitlab|github) exec "$BIN/tracker/$provider.sh" "$@" ;;
  "") echo "tracker: no .compasso/project.yaml in $repo - run /compasso:setup" >&2; exit 1 ;;
  *) echo "tracker: unknown tracker.provider '$provider'" >&2; exit 1 ;;
esac
