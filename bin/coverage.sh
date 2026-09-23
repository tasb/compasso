#!/usr/bin/env bash
# The coverage check: line coverage of the lines changed since BASE. A warning,
# never a gate.
#
#   coverage.sh --repo R --base REF --run DIR [--min N]
#
# Runs coverage.command, then diff-cover on coverage.report. A changed file under
# coverage.paths that is missing from the report counts as fully uncovered.
# --min defaults to coverage.min_changed (the story flow passes the resolved one).
# Writes DIR/coverage.json: {status, percent, min, uncovered: ["file:line"...]}.
# Exit: 0 at or above min, or nothing changed | 3 below min, or not measured | 2 usage
set -u
set -f   # coverage.paths are patterns

BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="." BASE="" RUN="" MIN=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --base) BASE="$2"; shift 2 ;;
    --run) RUN="$2"; shift 2 ;;
    --min) MIN="$2"; shift 2 ;;
    *) echo "coverage: unknown argument '$1'" >&2; exit 2 ;;
  esac
done
[ -n "$BASE" ] && [ -n "$RUN" ] || { echo "coverage: --base and --run are required" >&2; exit 2; }
"$BIN/config.sh" validate --repo "$REPO" >/dev/null || exit 2
cfg() { "$BIN/config.sh" get --repo "$REPO" "$1"; }
[ -n "$MIN" ] || MIN="$(cfg .coverage.min_changed)"
mkdir -p "$RUN"

result() { # status percent uncovered-json
  jq -n --arg s "$1" --argjson p "$2" --argjson m "$MIN" --argjson u "$3" \
    '{status: $s, percent: $p, min: $m, uncovered: $u}' > "$RUN/coverage.json"
}
not_measured() { echo "coverage: not measured - $1"; result not-measured null '[]'; exit 3; }

git -C "$REPO" rev-parse --verify --quiet "$BASE^{commit}" >/dev/null || not_measured "base '$BASE' does not resolve"
cmd="$(cfg .coverage.command)"; report="$(cfg .coverage.report)"
[ -n "$cmd" ] || not_measured "no coverage.command in .compasso/project.yaml"
command -v diff-cover >/dev/null || not_measured "diff-cover is not installed"
( cd "$REPO" && bash -c "$cmd" ) > "$RUN/coverage-command.log" 2>&1 || not_measured "coverage.command failed (see coverage-command.log)"
[ -f "$REPO/$report" ] || not_measured "coverage.command did not write $report"

( cd "$REPO" && diff-cover "$report" --compare-branch="$BASE" --include-untracked \
    --json-report "$RUN/diff-cover.json" --quiet ) > "$RUN/diff-cover.log" 2>&1
[ -f "$RUN/diff-cover.json" ] || not_measured "diff-cover produced no result (see diff-cover.log)"

# product files that changed but are absent from the report: every non-blank line is uncovered
absent='[]'
changed="$( (git -C "$REPO" diff --name-only "$BASE"; git -C "$REPO" ls-files -o --exclude-standard) | sort -u)"
while IFS= read -r f; do
  [ -n "$f" ] || continue
  [ -f "$REPO/$f" ] || continue
  jq -e --arg f "$f" '.src_stats | has($f)' "$RUN/diff-cover.json" >/dev/null && continue
  for g in $(cfg '.coverage.paths[]'); do
    case "$f" in $g) ;; *) continue ;; esac
    absent="$(jq -c --arg f "$f" --argjson n "$(grep -n . "$REPO/$f" | cut -d: -f1 | jq -s .)" \
      '. + ($n | map("\($f):\(.)"))' <<<"$absent")"
    break
  done
done <<EOF
$changed
EOF

read -r covered total <<EOF
$(jq -r --argjson absent "$absent" '
  ([.src_stats[] | (.covered_lines | length)] | add // 0) as $c
  | ([.src_stats[] | (.covered_lines | length) + (.violation_lines | length)] | add // 0) as $t
  | "\($c) \($t + ($absent | length))"' "$RUN/diff-cover.json")
EOF
uncovered="$(jq -c --argjson absent "$absent" \
  '[.src_stats | to_entries[] | .key as $f | .value.violation_lines[] | "\($f):\(.)"] + $absent' "$RUN/diff-cover.json")"

if [ "$total" -eq 0 ]; then
  echo "coverage: no changed lines to measure"; result ok 100 '[]'; exit 0
fi
pct=$(( covered * 100 / total ))
if [ "$pct" -ge "$MIN" ]; then
  echo "coverage: $pct% of changed lines (min $MIN%)"; result ok "$pct" "$uncovered"; exit 0
fi
echo "coverage: below min - $pct% of $MIN% (warning); uncovered changed lines:"
jq -r '.[]' <<<"$uncovered" | sed 's/^/  - /'
result below "$pct" "$uncovered"
exit 3
