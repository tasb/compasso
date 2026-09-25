#!/usr/bin/env bash
# Decide whether a story's change is low risk (may merge without a person, with
# approvals.merge: risk) or high risk (a person approves).
#
#   risk.sh --repo R --run DIR --base REF [--out F]
#
# High risk when any of these hold, each named as a reason:
#   - a changed file matches risk.sensitive_paths
#   - more changed lines than risk.max_changed_lines
#   - it changes the build, the pipeline, the Compasso config or dependencies
#   - security found a blocker or major issue in this story (even if fixed)
#   - changed-line coverage is below its minimum, or was not measured
# DIR is the story run (findings.json, coverage.json). The decision goes to F
# (default DIR/risk.json): {level: low|high, changed_lines, files, reasons: []}.
# Exit: 0 low | 3 high | 2 usage
set -u
set -f   # the paths are patterns

BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="." RUN="" BASE="" OUT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --run) RUN="$2"; shift 2 ;;
    --base) BASE="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    *) echo "risk: unknown argument '$1'" >&2; exit 2 ;;
  esac
done
[ -n "$RUN" ] && [ -n "$BASE" ] || { echo "usage: risk.sh --repo R --run DIR --base REF [--out F]" >&2; exit 2; }
"$BIN/config.sh" validate --repo "$REPO" >/dev/null || exit 2
cfg() { "$BIN/config.sh" get --repo "$REPO" "$1"; }
[ -n "$OUT" ] || OUT="$RUN/risk.json"

files="$(git -C "$REPO" diff --name-only "$BASE" -- . ':(exclude).compasso/runs')"
lines="$(git -C "$REPO" diff --numstat "$BASE" -- . ':(exclude).compasso/runs' | awk '{a += $1 + $2} END {print a + 0}')"
max="$(cfg .risk.max_changed_lines)"; [ -n "$max" ] || max=200
reasons=""
add() { reasons="$reasons$1"$'\n'; }

sensitive="$(cfg '.risk.sensitive_paths[]')"
while IFS= read -r f; do
  [ -n "$f" ] || continue
  for g in $sensitive; do case "$f" in $g) add "$f is a sensitive path ($g)"; break ;; esac; done
  case "$f" in
    .compasso/project.yaml|.gitlab-ci.yml|.gitlab/*|*/.gitlab-ci.yml|Dockerfile|*/Dockerfile|Makefile|\
    package.json|*/package.json|package-lock.json|*/package-lock.json|yarn.lock|pnpm-lock.yaml|\
    requirements*.txt|pyproject.toml|poetry.lock|go.mod|go.sum|Gemfile|Gemfile.lock|pom.xml|build.gradle*|Cargo.toml|Cargo.lock)
      add "$f changes the build, the pipeline, the Compasso config or dependencies" ;;
  esac
done <<EOF
$files
EOF
[ "$lines" -le "$max" ] || add "$lines changed lines, over the $max-line limit"
if [ -f "$RUN/findings.json" ]; then
  n="$(jq '[.[] | select(.by == "security" and (.severity == "blocker" or .severity == "major"))] | length' "$RUN/findings.json")"
  [ "$n" -eq 0 ] || add "security found $n blocker or major issue(s) in this story"
fi
if [ -f "$RUN/coverage.json" ]; then
  case "$(jq -r .status "$RUN/coverage.json")" in
    ok) ;; below) add "changed-line coverage is below its minimum" ;; *) add "changed-line coverage was not measured" ;;
  esac
else
  add "changed-line coverage was not measured"
fi

level=low; [ -z "$reasons" ] || level=high
jq -n --arg level "$level" --argjson lines "$lines" --arg files "$files" --arg reasons "$reasons" \
  '{level: $level, changed_lines: $lines, files: ($files | split("\n") | map(select(. != "")) | length),
    reasons: ($reasons | split("\n") | map(select(. != "")))}' > "$OUT"
if [ "$level" = low ]; then
  echo "risk: low - $lines changed lines in $(jq .files "$OUT") files, nothing sensitive"; exit 0
fi
echo "risk: high - a person approves:"; jq -r '.reasons[] | "  - " + .' "$OUT"; exit 3
