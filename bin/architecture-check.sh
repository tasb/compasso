#!/usr/bin/env bash
# Validate .compasso/product/architecture.yaml: every section filled, every MVP feature served by a
# component, components that talk only to components that exist, observability with metrics and
# alerts, a security control for personal data, decisions that say why.
#
#   architecture-check.sh --repo R
#
# Exit: 0 valid | 1 invalid | 3 no architecture
set -u
BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="."
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    *) echo "architecture-check: unknown argument '$1'" >&2; exit 1 ;;
  esac
done
A="$REPO/.compasso/product/architecture.yaml" B="$REPO/.compasso/backlog.yaml"
[ -f "$A" ] || { echo "architecture-check: no .compasso/product/architecture.yaml - run /compasso:architect" >&2; exit 3; }
arch="$(yq -o=json . "$A")" || { echo "architecture-check: architecture.yaml is not valid YAML" >&2; exit 1; }
back=null; [ -f "$B" ] && back="$(yq -o=json . "$B")"
screens=null
inv="$(jq -r '.product.prototype.inventory // empty' <<<"$back" 2>/dev/null)"
[ -n "$inv" ] && [ -f "$REPO/$inv" ] && screens="$(jq -c '[.screens[].id]' "$REPO/$inv")"
res="$(jq -n --argjson a "$arch" --argjson b "$back" --argjson s "$screens" '{a: $a, b: $b, screens: $s}' | jq -f "$BIN/architecture-check.jq")" || exit 1
jq -r '(.errors[] | "ERROR  \(.)"), (.notes[] | "note   \(.)")' <<<"$res"
[ "$(jq '.errors | length' <<<"$res")" -eq 0 ] && echo "architecture-check: valid ($(jq '.components | length' <<<"$arch") components, $(jq '.decisions | length' <<<"$arch") decisions)"
[ "$(jq '.errors | length' <<<"$res")" -eq 0 ]
