#!/usr/bin/env bash
# The texts Compasso writes, in a project's language (templates/locales/<lang>.yaml, over English).
#
#   locale.sh [--repo R | --lang L]   the merged texts as JSON: {lang, md, text, ui}
#   locale.sh --names                 every work-item name in every language: {goal: ["Goal", "Objetivo"], ...}
#   locale.sh --list                  the languages Compasso ships
#
# The project's language is `language` in .compasso/project.yaml (older configs: test_guide.language);
# without a config, English.
# Exit: 0 | 1 unknown language | 2 usage
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOC="$ROOT/templates/locales"
REPO="" LANG_="" MODE=one
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --lang) LANG_="$2"; shift 2 ;;
    --names) MODE=names; shift ;;
    --list) MODE=list; shift ;;
    *) echo "locale: unknown argument '$1'" >&2; exit 2 ;;
  esac
done
case "$MODE" in
  list) for f in "$LOC"/*.yaml; do printf '%s\t%s\n' "$(basename "$f" .yaml)" "$(yq -r .name "$f")"; done; exit 0 ;;
  names)
    for f in "$LOC"/*.yaml; do yq -o=json '.md' "$f"; done |
      jq -s 'reduce .[] as $m ({}; reduce ($m | to_entries[]) as $e (.; .[$e.key] = ((.[$e.key] // []) + [$e.value] | unique)))'
    exit 0 ;;
esac
if [ -z "$LANG_" ]; then
  c="${REPO:-.}/.compasso/project.yaml"
  [ -f "$c" ] && LANG_="$(yq -r '.language // .test_guide.language // ""' "$c")"
  [ -n "$LANG_" ] || LANG_=en
fi
[ -f "$LOC/$LANG_.yaml" ] || { echo "locale: no texts for language '$LANG_' (templates/locales/: $(ls "$LOC" | sed 's/\.yaml$//' | tr '\n' ' '))" >&2; exit 1; }
jq -n --arg lang "$LANG_" --argjson en "$(yq -o=json . "$LOC/en.yaml")" --argjson l "$(yq -o=json . "$LOC/$LANG_.yaml")" \
  '($en * $l) + {lang: $lang}'
