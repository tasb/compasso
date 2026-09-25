#!/usr/bin/env bash
# Run agent-written mutants against the tests, one at a time.
#
#   mutate.sh scope --repo R --commits "SHA..."|--base REF [--sensitive] --out F   what the mutants may change
#   mutate.sh run --repo R --mutants DIR --test CMD [--timeout S] --out F
#   mutate.sh result --results F --verdicts V --out R                 this check's part of the Hardening report
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
REPO="." DIR="" TEST="" TIMEOUT=120 OUT="" COMMITS="" RESULTS="" VERDICTS="" FEATURE="" BASE="" SENSITIVE=0
CMD="${1:-}"; shift || true
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --mutants) DIR="$2"; shift 2 ;;
    --test) TEST="$2"; shift 2 ;;
    --timeout) TIMEOUT="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --commits) COMMITS="$2"; shift 2 ;;
    --base) BASE="$2"; shift 2 ;;
    --sensitive) SENSITIVE=1; shift ;;
    --results) RESULTS="$2"; shift 2 ;;
    --verdicts) VERDICTS="$2"; shift 2 ;;
    --feature) FEATURE="$2"; shift 2 ;;
    *) echo "mutate: unknown argument '$1'" >&2; exit 2 ;;
  esac
done
if [ "$CMD" = scope ]; then
  # the product code the given merge commits (or, with --base, a story in progress) changed, never
  # the tests (test_paths); --sensitive keeps only files under risk.sensitive_paths
  [ -n "$COMMITS$BASE" ] && [ -n "$OUT" ] || { echo "usage: mutate.sh scope --repo R --commits \"SHA...\"|--base REF [--sensitive] --out F" >&2; exit 2; }
  set -f; ex="" only=""
  for g in $("$BIN/config.sh" get --repo "$REPO" '.test_paths[]'); do ex="$ex ':(exclude,glob)$g'"; done
  if [ "$SENSITIVE" = 1 ]; then
    for g in $("$BIN/config.sh" get --repo "$REPO" '.risk.sensitive_paths[]'); do only="$only ':(glob)$g'"; done
    [ -n "$only" ] || { : > "$OUT"; echo "mutate: no risk.sensitive_paths - nothing sensitive to check"; exit 0; }
  fi
  [ -n "$only" ] || only="."
  : > "$OUT"
  if [ -n "$BASE" ]; then
    git -C "$REPO" rev-parse --verify --quiet "$BASE^{commit}" >/dev/null || { echo "mutate: base $BASE does not resolve" >&2; exit 2; }
    eval "git -C \"\$REPO\" diff \"\$BASE\" -- $only $ex" >> "$OUT"
  fi
  for c in $COMMITS; do
    git -C "$REPO" cat-file -e "$c^{commit}" 2>/dev/null || { echo "mutate: $c is not a commit here; fetch first" >&2; exit 2; }
    first="$(git -C "$REPO" rev-parse "$c^1")"          # a merge commit's first parent is the branch it merged into
    eval "git -C \"\$REPO\" diff \"\$first\" \"\$c\" -- $only $ex" >> "$OUT"
  done
  echo "mutate: scope has $(grep -c '^+[^+]' "$OUT") changed lines in $(grep -c '^+++ ' "$OUT") files"
  exit 0
fi
if [ "$CMD" = result ]; then
  # V: the tester's verdict on each survivor: [{id, verdict: gap|equivalent, reason, story?}]
  [ -f "$RESULTS" ] && [ -f "$VERDICTS" ] && [ -n "$OUT" ] || { echo "usage: mutate.sh result --results F --verdicts V --out R" >&2; exit 2; }
  missing="$(jq -r --slurpfile v "$VERDICTS" '.[] | select(.status == "survived") | .id as $i
    | select([$v[0][] | select(.id == $i and (.verdict | IN("gap", "equivalent")))] | length == 0) | .id' "$RESULTS")"
  [ -z "$missing" ] || { echo "mutate: no verdict for survivor(s): $(echo $missing)" >&2; exit 2; }
  jq -n --slurpfile r "$RESULTS" --slurpfile v "$VERDICTS" '
    $r[0] as $r | $v[0] as $v
    | def verdict($i): [$v[] | select(.id == $i)][0];
    ([$r[] | select(.status == "survived") | . + {v: verdict(.id)}]) as $s
    | {check: "mutation", title: "Mutation testing", ran: true,
       counts: [{label: "mutants", n: ($r | map(select(.status != "not-applicable")) | length)},
                {label: "caught", n: ($r | map(select(.status == "killed" or .status == "timeout")) | length)},
                {label: "gaps", n: ($s | map(select(.v.verdict == "gap")) | length)},
                {label: "no observable effect", n: ($s | map(select(.v.verdict == "equivalent")) | length)}],
       gaps: [$s[] | select(.v.verdict == "gap") | {summary: "\(.behaviour) — \(.description)"} + (if .v.story then {story: .v.story} else {} end)]}' > "$OUT"
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
