#!/usr/bin/env bash
# Validate .compasso/backlog.yaml: every feature complete, at most half a sprint, dependencies
# that exist and form no cycle, and an MVP that depends only on MVP features. With a
# prototype inventory, it also notes every screen no feature covers.
#
#   backlog-check.sh --repo R [--json]
#
# Exit: 0 valid | 1 invalid | 3 no backlog or config
set -u

BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="." JSON=0
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --json) JSON=1; shift ;;
    *) echo "backlog-check: unknown argument '$1'" >&2; exit 1 ;;
  esac
done
B="$REPO/.compasso/backlog.yaml"
[ -f "$B" ] || { echo "backlog-check: no .compasso/backlog.yaml - run /compasso:backlog" >&2; exit 3; }
"$BIN/config.sh" validate --repo "$REPO" >/dev/null 2>&1 || { echo "backlog-check: .compasso/project.yaml is missing or invalid" >&2; exit 3; }
cfg() { "$BIN/config.sh" get --repo "$REPO" "$1"; }
backlog="$(yq -o=json . "$B")" || { echo "backlog-check: .compasso/backlog.yaml is not valid YAML" >&2; exit 1; }
screens=null
inv="$(jq -r '.product.prototype.inventory // empty' <<<"$backlog")"
if [ -n "$inv" ] && [ -f "$REPO/$inv" ]; then screens="$(jq -c '[.screens[].id]' "$REPO/$inv")"; fi
result="$(jq -n --argjson b "$backlog" --argjson screens "$screens" \
  --argjson c "$(jq -n --argjson w "$(cfg .sprint.weeks)" --argjson h "$(cfg .sprint.hours_per_day)" --argjson cap "$(cfg .sprint.capacity_hours)" '{weeks: $w, hpd: $h, cap: $cap}')" \
  '{b: $b, c: $c, screens: $screens}' | jq -f "$BIN/backlog-check.jq")" || exit 1
if [ "$JSON" -eq 1 ]; then printf '%s\n' "$result"
else
  jq -r '
    (.errors[] | "ERROR  \(.)"), (.notes[] | "note   \(.)"),
    "MVP: \(.totals.mvp_features) of \(.totals.features) features, \(.totals.mvp_hours)h (about \(.totals.mvp_sprints) sprint(s) at \(.totals.capacity)h)",
    "Everything: \(.totals.all_hours)h"' <<<"$result"
fi
[ "$(jq '.errors | length' <<<"$result")" -eq 0 ]
