#!/usr/bin/env bash
# Validate .compasso/plan.yaml against the sprint rules in .compasso/project.yaml.
#
#   plan-check.sh --repo R [--plan FILE] [--json]
#
# Prints errors, notes, totals, the parallel waves, the critical path and
# stories whose touched paths overlap. --json prints the raw result.
# Exit: 0 valid | 1 invalid | 3 no plan or config
set -u

BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="." JSON=0 PLAN=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --json) JSON=1; shift ;;
    --plan) PLAN="$2"; shift 2 ;;
    *) echo "plan-check: unknown argument '$1'" >&2; exit 1 ;;
  esac
done
[ -n "$PLAN" ] || PLAN="$REPO/.compasso/plan.yaml"

"$BIN/config.sh" validate --repo "$REPO" >/dev/null || exit $?
[ -f "$PLAN" ] || { echo "plan-check: no $PLAN - run /compasso:plan" >&2; exit 3; }
plan_json="$(yq -o=json '.' "$PLAN" 2>/dev/null)" || { echo "plan-check: $PLAN is not valid YAML" >&2; exit 1; }

cfg() { "$BIN/config.sh" get --repo "$REPO" "$1"; }
result="$(jq -n --argjson plan "$plan_json" \
  --argjson max "$(cfg .limits.story_max_hours)" --argjson target "$(cfg .limits.story_target_hours)" \
  --argjson hpd "$(cfg .sprint.hours_per_day)" --argjson weeks "$(cfg .sprint.weeks)" \
  --argjson cap "$(cfg .sprint.capacity_hours)" \
  '{plan: $plan, cfg: {max: $max, target: $target, hpd: $hpd, weeks: $weeks, cap: $cap}}' |
  jq -f "$BIN/plan-check.jq")" || { echo "plan-check: could not evaluate $PLAN" >&2; exit 1; }

if [ "$JSON" -eq 1 ]; then
  printf '%s\n' "$result"
else
  printf '%s' "$result" | jq -r '
    (if (.errors | length) > 0 then "Errors:", (.errors[] | "  - \(.)") else empty end),
    (if (.notes | length) > 0 then "Notes:", (.notes[] | "  - \(.)") else empty end),
    "Total: \(.totals.epic)h of \(.totals.capacity)h capacity",
    (.totals.features[] | "  \(.key): \(.hours)h (max \($ARGS.named.fmax))"),
    (if (.waves | length) > 0 then "Waves:", (.waves | to_entries[] | "  \(.key + 1). \(.value | join(", "))") else empty end),
    "Critical path: \(.critical.hours)h (\(.critical.path | join(" → ")))",
    (if (.overlaps | length) > 0 then "Overlapping paths (run serially):", (.overlaps[] | "  - \(join(" / "))") else empty end)
  ' --arg fmax "$(printf '%s' "$result" | jq -r .totals.feature_max)"
fi
[ "$(printf '%s' "$result" | jq '.errors | length')" -eq 0 ]
