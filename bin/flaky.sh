#!/usr/bin/env bash
# Find flaky tests: run the unchanged test suite several times.
#
#   flaky.sh --repo R --test CMD [--runs N] [--timeout S] --out DIR
#
# Each run's output goes to DIR/run-<n>.log and the outcomes to DIR/runs.json.
# A suite that both passes and fails on the same code is flaky; the tester then
# reads the failing logs to name the tests. The working tree must be clean, so
# every run sees the same code.
# Exit: 0 all runs agree | 3 the runs disagree (flaky) | 4 every run failed | 2 usage
set -u

BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="." TEST="" RUNS=5 TIMEOUT=600 OUT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --test) TEST="$2"; shift 2 ;;
    --runs) RUNS="$2"; shift 2 ;;
    --timeout) TIMEOUT="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    *) echo "flaky: unknown argument '$1'" >&2; exit 2 ;;
  esac
done
[ -n "$TEST" ] && [ -n "$OUT" ] || { echo "usage: flaky.sh --repo R --test CMD [--runs N] --out DIR" >&2; exit 2; }
case "$RUNS" in ''|*[!0-9]*|0|1) echo "flaky: --runs is a number of at least 2" >&2; exit 2 ;; esac
[ -z "$(git -C "$REPO" status --porcelain --untracked-files=no)" ] ||
  { echo "flaky: the working tree has uncommitted changes; commit or stash them first" >&2; exit 2; }
mkdir -p "$OUT"

runs='[]'
for n in $(seq 1 "$RUNS"); do
  ( cd "$REPO" && "$BIN/with-timeout.pl" "$TIMEOUT" bash -c "$TEST" ) > "$OUT/run-$n.log" 2>&1
  rc=$?
  s=passed; [ "$rc" -eq 0 ] || s=failed; [ "$rc" -eq 142 ] && s=timeout
  runs="$(jq -c --argjson n "$n" --arg s "$s" '. + [{run: $n, status: $s, log: "run-\($n).log"}]' <<<"$runs")"
  echo "flaky: run $n $s"
done
printf '%s\n' "$runs" > "$OUT/runs.json"

passed="$(jq '[.[] | select(.status == "passed")] | length' <<<"$runs")"
if [ "$passed" -eq "$RUNS" ]; then echo "flaky: all $RUNS runs passed - stable"; exit 0; fi
if [ "$passed" -eq 0 ]; then echo "flaky: every run failed - a real failure, not flakiness"; exit 4; fi
echo "flaky: $passed of $RUNS runs passed - the suite is flaky; read the failing logs to name the tests"
exit 3
