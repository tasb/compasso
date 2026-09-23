#!/usr/bin/env bash
# Test immutability: record the test files after the tester's turn, verify after
# the builder's. Test files are the repo's files (tracked and untracked, not
# ignored) matching `test_paths` in .compasso/project.yaml.
#
#   test-hashes.sh record --repo R --run DIR
#   test-hashes.sh verify --repo R --run DIR
#
# Exit: 0 ok | 1 a test file was added, removed or changed since record | 2 usage or no record
set -u
set -f   # test_paths are patterns, never expanded against the working directory

BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CMD="${1:-}"; shift || true
REPO="." RUN=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --run) RUN="$2"; shift 2 ;;
    *) echo "test-hashes: unknown argument '$1'" >&2; exit 2 ;;
  esac
done
[ -n "$RUN" ] || { echo "test-hashes: --run is required" >&2; exit 2; }

snapshot() { # -> "hash  path" lines, sorted by path
  local globs f g
  globs="$("$BIN/config.sh" get --repo "$REPO" '.test_paths[]')" || exit 2
  git -C "$REPO" ls-files -co --exclude-standard | sort | while IFS= read -r f; do
    for g in $globs; do
      # `case` globs let * cross "/"; also try with a leading "/" so "**/x" matches at the root
      case "$f" in $g) ;; *) case "/$f" in $g) ;; *) continue ;; esac ;; esac
      printf '%s  %s\n' "$(shasum -a 256 < "$REPO/$f" | cut -d' ' -f1)" "$f"
      break
    done
  done
}

case "$CMD" in
  record)
    mkdir -p "$RUN"
    snapshot > "$RUN/test-hashes" || exit 2
    echo "test-hashes: recorded $(wc -l < "$RUN/test-hashes" | tr -d ' ') test files"
    ;;
  verify)
    [ -f "$RUN/test-hashes" ] || { echo "test-hashes: nothing recorded in $RUN" >&2; exit 2; }
    now="$(snapshot)" || exit 2
    changes="$(diff <(cat "$RUN/test-hashes") <(printf '%s\n' "$now" | sed '/^$/d') | sed -n 's/^[<>] [0-9a-f]*  //p' | sort -u)"
    if [ -n "$changes" ]; then
      printf 'test-hashes: VIOLATION - test files changed after the tester handed over:\n%s\n' "$(printf '%s\n' "$changes" | sed 's/^/  - /')"
      exit 1
    fi
    echo "test-hashes: test files unchanged"
    ;;
  *) echo "usage: test-hashes.sh record|verify --repo R --run DIR" >&2; exit 2 ;;
esac
