#!/usr/bin/env bash
# Run agent-written mutants against the tests, one at a time.
#
#   mutate.sh scope --repo R --commits "SHA..." --out F                what the mutants may change
#   mutate.sh run --repo R --mutants DIR --test CMD [--timeout S] --out F
#   mutate.sh report --results F --verdicts V [--feature N]           the Hardening comment
#
# DIR holds one JSON file per mutant: {id, file, behaviour, description, patch}, where
# patch is a unified diff against the current tree. For each mutant: prove it applies
# (git apply --check, and the tree really changed), run CMD from the repo root with a
# time limit, record the result, revert, and prove the tree is back to where it was.
# Results: killed (the tests failed), survived (they passed), timeout (counted as
# killed: the tests did not pass), not-applicable (the patch did not apply; never
# counted). The working tree must be clean before the run.
# scope: the diff of the given merge commits against their first parent, test files
# (test_paths) left out, for the mutator to work from.
# Exit: 0 done | 1 the tree could not be restored (stop everything) | 2 usage
set -u

BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="." DIR="" TEST="" TIMEOUT=120 OUT="" COMMITS="" RESULTS="" VERDICTS="" FEATURE=""
CMD="${1:-}"; shift || true
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --mutants) DIR="$2"; shift 2 ;;
    --test) TEST="$2"; shift 2 ;;
    --timeout) TIMEOUT="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --commits) COMMITS="$2"; shift 2 ;;
    --results) RESULTS="$2"; shift 2 ;;
    --verdicts) VERDICTS="$2"; shift 2 ;;
    --feature) FEATURE="$2"; shift 2 ;;
    *) echo "mutate: unknown argument '$1'" >&2; exit 2 ;;
  esac
done
if [ "$CMD" = scope ]; then
  # the product code the given merge commits changed, never the tests (test_paths)
  [ -n "$COMMITS" ] && [ -n "$OUT" ] || { echo "usage: mutate.sh scope --repo R --commits \"SHA...\" --out F" >&2; exit 2; }
  set -f; ex=""
  for g in $("$BIN/config.sh" get --repo "$REPO" '.test_paths[]'); do ex="$ex ':(exclude,glob)$g'"; done
  : > "$OUT"
  for c in $COMMITS; do
    git -C "$REPO" cat-file -e "$c^{commit}" 2>/dev/null || { echo "mutate: $c is not a commit here; fetch first" >&2; exit 2; }
    first="$(git -C "$REPO" rev-parse "$c^1")"          # a merge commit's first parent is the branch it merged into
    eval "git -C \"\$REPO\" diff \"\$first\" \"\$c\" -- . $ex" >> "$OUT"
  done
  echo "mutate: scope has $(grep -c '^+[^+]' "$OUT") changed lines in $(grep -c '^+++ ' "$OUT") files"
  exit 0
fi
if [ "$CMD" = report ]; then
  # V: the tester's verdict on each survivor: [{id, verdict: gap|equivalent, reason, story?}]
  [ -f "$RESULTS" ] && [ -f "$VERDICTS" ] || { echo "usage: mutate.sh report --results F --verdicts V [--feature N]" >&2; exit 2; }
  missing="$(jq -r --slurpfile v "$VERDICTS" '.[] | select(.status == "survived") | .id as $i
    | select([$v[0][] | select(.id == $i and (.verdict | IN("gap", "equivalent")))] | length == 0) | .id' "$RESULTS")"
  [ -z "$missing" ] || { echo "mutate: no verdict for survivor(s): $(echo $missing)" >&2; exit 2; }
  jq -rn --slurpfile r "$RESULTS" --slurpfile v "$VERDICTS" --arg feature "$FEATURE" '
    $r[0] as $r | $v[0] as $v
    | def verdict($i): [$v[] | select(.id == $i)][0];
    ([$r[] | select(.status == "survived") | . + {v: verdict(.id)}]) as $s
    | "**Hardening** · mutation testing · \($r | map(select(.status != "not-applicable")) | length) mutants", "",
      "- Caught by the tests: \($r | map(select(.status == "killed" or .status == "timeout")) | length) · Gaps: \($s | map(select(.v.verdict == "gap")) | length) · No observable effect: \($s | map(select(.v.verdict == "equivalent")) | length) · Not applicable: \($r | map(select(.status == "not-applicable")) | length)",
      ($s[] | select(.v.verdict == "gap") | "- Gap: \(.behaviour) — \(.description)" + (if .v.story then " → #\(.v.story)" else "" end)),
      "", "<!-- compasso:harden" + (if $feature != "" then " feature=\($feature)" else "" end) + " -->"'
  exit 0
fi
[ "$CMD" = run ] && [ -d "$DIR" ] && [ -n "$TEST" ] && [ -n "$OUT" ] ||
  { echo "usage: mutate.sh run --repo R --mutants DIR --test CMD [--timeout S] --out F" >&2; exit 2; }
case "$TIMEOUT" in ''|*[!0-9]*) echo "mutate: --timeout is a number of seconds" >&2; exit 2 ;; esac
[ -z "$(git -C "$REPO" status --porcelain --untracked-files=no)" ] ||
  { echo "mutate: the working tree has uncommitted changes; commit or stash them first" >&2; exit 2; }

before="$(git -C "$REPO" diff HEAD | shasum | cut -d' ' -f1)"
results='[]'
for m in "$DIR"/*.json; do
  [ -f "$m" ] || continue
  id="$(jq -r '.id // empty' "$m")"; patch="$(mktemp)"
  jq -r '.patch // empty' "$m" > "$patch"
  status=""
  if [ -z "$id" ] || [ ! -s "$patch" ] || ! git -C "$REPO" apply --check "$patch" 2>/dev/null; then
    status=not-applicable
  else
    git -C "$REPO" apply "$patch" || status=not-applicable
    if [ -z "$status" ]; then
      # the time limit kills the tests' whole process group, servers included
      ( cd "$REPO" && "$BIN/with-timeout.pl" "$TIMEOUT" bash -c "$TEST" ) > "$DIR/$id.log" 2>&1
      rc=$?
      if [ "$rc" -eq 0 ]; then status=survived
      elif [ "$rc" -eq 142 ]; then status=timeout
      else status=killed; fi
      git -C "$REPO" apply -R "$patch" 2>/dev/null
    fi
  fi
  rm -f "$patch"
  if [ "$(git -C "$REPO" diff HEAD | shasum | cut -d' ' -f1)" != "$before" ]; then
    echo "mutate: STOP - the tree was not restored after mutant ${id:-$m}; fix it with git checkout before anything else" >&2
    exit 1
  fi
  results="$(jq -c --slurpfile x "$m" --arg s "$status" '. + [($x[0] | {id, file, behaviour, description}) + {status: $s}]' <<<"$results")"
  echo "mutate: ${id:-$(basename "$m")} $status"
done

printf '%s\n' "$results" > "$OUT"
jq -r '"mutate: \(length) mutants - \(map(select(.status == "killed" or .status == "timeout")) | length) killed, \(map(select(.status == "survived")) | length) survived, \(map(select(.status == "not-applicable")) | length) not applicable"' "$OUT"
