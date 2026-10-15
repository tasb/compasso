#!/usr/bin/env bash
# Decide whether a story's change is low risk (may merge without a person, with
# approvals.merge: risk) or high risk (a person approves).
#
#   risk.sh --repo R --run DIR --base REF [--head REF] [--out F]
#   risk.sh --repo R --run DIR --base REF --infra     only list the changed files in risk.infra_paths
#
# High risk when any of these hold, each named as a reason. In every stage:
#   - it changes a file in risk.infra_paths and DIR/cost.json (the finops report) is missing,
#     or says increase or unknown
# In production (stage: production, or no stage) also:
#   - a changed file matches risk.sensitive_paths, risk.infra_paths or risk.production_paths
#   - more product lines (files in risk.product_paths) than risk.max_changed_lines
#   - it changes the build, the pipeline, the Compasso config or dependencies
#   - security marked the change sensitive by its content (DIR/sensitive.json)
#   - changed-line coverage is below its minimum, or was not measured
# A security finding needs no person: an unresolved one blocks the merge (review-gate.sh).
# DIR is the story run (cost.json, sensitive.json, coverage.json). The decision goes to F
# (default DIR/risk.json): {level: low|high, changed_lines (product lines), files, reasons: []}.
# Exit: 0 low | 3 high | 2 usage
set -u
set -f   # the paths are patterns

BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="." RUN="" BASE="" HEAD="" OUT="" INFRA=0
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --run) RUN="$2"; shift 2 ;;
    --base) BASE="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --infra) INFRA=1; shift ;;
    --head) HEAD="$2"; shift 2 ;;   # a branch's change (the tech lead's view), instead of the working tree
    *) echo "risk: unknown argument '$1'" >&2; exit 2 ;;
  esac
done
[ -n "$RUN" ] && [ -n "$BASE" ] || { echo "usage: risk.sh --repo R --run DIR --base REF [--out F]" >&2; exit 2; }
"$BIN/config.sh" validate --repo "$REPO" >/dev/null || exit 2
cfg() { "$BIN/config.sh" get --repo "$REPO" "$1"; }
[ -n "$OUT" ] || OUT="$RUN/risk.json"

RANGE="$BASE"; [ -z "$HEAD" ] || RANGE="$BASE...$HEAD"
files="$(git -C "$REPO" diff --name-only "$RANGE" -- . ':(exclude).compasso/runs')"
stage="$(cfg .stage)"; [ -n "$stage" ] || stage=production
max="$(cfg .risk.max_changed_lines)"; [ -n "$max" ] || max=200
reasons=""
add() { reasons="$reasons$1"$'\n'; }
LOC="$("$BIN/locale.sh" --repo "$REPO")" || exit 2
say() { jq -nr -L "$BIN" --argjson L "$LOC" --arg k "$1" --argjson v "$2" 'include "i18n"; tf($k; $v)'; }   # a reason, in the project's language
match() { # file globs...: the first glob the file matches; "**/" also matches at the top
  local f="$1" g; shift
  for g in "$@"; do
    case "$f" in $g) echo "$g"; return 0 ;; esac
    case "$g" in '**/'*) case "$f" in ${g#\*\*/}) echo "$g"; return 0 ;; esac ;; esac
  done
  return 1
}
globs() { cfg ".risk.$1[]"; }
sensitive="$(globs sensitive_paths)"; product="$(globs product_paths)"; infra="$(globs infra_paths)"; critical="$(globs production_paths)"

if [ "$INFRA" -eq 1 ]; then
  while IFS= read -r f; do [ -n "$f" ] && match "$f" $infra >/dev/null && echo "$f"; done <<EOF
$files
EOF
  exit 0
fi
infra_file="" lines=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  [ -n "$infra_file" ] || ! match "$f" $infra >/dev/null || infra_file="$f"
  [ "$stage" = production ] || continue
  g="$(match "$f" $sensitive)" && add "$(say risk_sensitive "$(jq -nc --arg f "$f" --arg g "$g" '{file: $f, glob: $g}')")"
  match "$f" $infra >/dev/null && add "$(say risk_infra "$(jq -nc --arg f "$f" '{file: $f}')")"
  g="$(match "$f" $critical)" && add "$(say risk_production_path "$(jq -nc --arg f "$f" --arg g "$g" '{file: $f, glob: $g}')")"
  case "$f" in
    .compasso/project.yaml|.gitlab-ci.yml|.gitlab/*|*/.gitlab-ci.yml|Dockerfile|*/Dockerfile|Makefile|\
    package.json|*/package.json|package-lock.json|*/package-lock.json|yarn.lock|pnpm-lock.yaml|\
    requirements*.txt|pyproject.toml|poetry.lock|go.mod|go.sum|Gemfile|Gemfile.lock|pom.xml|build.gradle*|Cargo.toml|Cargo.lock)
      add "$(say risk_build "$(jq -nc --arg f "$f" '{file: $f}')")" ;;
  esac
done <<EOF
$files
EOF
# product lines: tests, configuration, docs and every other folder do not count
while IFS="$(printf '\t')" read -r a d f; do
  [ -n "$f" ] && match "$f" $product >/dev/null || continue
  case "$a$d" in *-*) continue ;; esac   # a binary file has no lines
  lines=$((lines + a + d))
done <<EOF
$(git -C "$REPO" diff --numstat "$RANGE" -- . ':(exclude).compasso/runs')
EOF

if [ -n "$infra_file" ]; then
  cost="$(jq -r '.result // ""' "$RUN/cost.json" 2>/dev/null)"
  case "$cost" in
    none|decrease) ;;
    increase|unknown) add "$(say risk_cost "$(jq -nc --arg r "$cost" '{result: $r}')")" ;;
    *) add "$(say risk_cost_none "$(jq -nc --arg f "$infra_file" '{file: $f}')")" ;;
  esac
fi
if [ "$stage" = production ]; then
  [ "$lines" -le "$max" ] || add "$(say risk_lines "$(jq -nc --argjson l "$lines" --argjson m "$max" '{lines: $l, max: $m}')")"
  what="$(jq -r '.sensitive // empty' "$RUN/sensitive.json" 2>/dev/null)"
  [ -z "$what" ] || add "$(say risk_sensitive_content "$(jq -nc --arg w "$what" '{what: $w}')")"
  if [ -f "$RUN/coverage.json" ]; then
    case "$(jq -r .status "$RUN/coverage.json")" in
      ok) ;; below) add "$(say risk_cov_below '{}')" ;; *) add "$(say risk_cov_none '{}')" ;;
    esac
  else
    add "$(say risk_cov_none '{}')"
  fi
fi

level=low; [ -z "$reasons" ] || level=high
jq -n --arg level "$level" --argjson lines "$lines" --arg files "$files" --arg reasons "$reasons" \
  '{level: $level, changed_lines: $lines, files: ($files | split("\n") | map(select(. != "")) | length),
    reasons: ($reasons | split("\n") | map(select(. != "")))}' > "$OUT"
if [ "$level" = low ]; then
  echo "risk: low - $lines changed lines in $(jq .files "$OUT") files, nothing sensitive"; exit 0
fi
echo "risk: high - a person approves:"; jq -r '.reasons[] | "  - " + .' "$OUT"; exit 3
