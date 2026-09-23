#!/usr/bin/env bash
# Install Compasso's work-item formats as GitLab issue templates.
#
#   issue-templates.sh --repo R   copy templates/issue_templates/*.md to R/.gitlab/issue_templates/
#
# A file that already exists with different content is left alone and reported.
# Exit: 0 ok (including skips) | 1 usage or copy failure
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO="."
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    *) echo "issue-templates: unknown argument '$1'" >&2; exit 1 ;;
  esac
done

DEST="$REPO/.gitlab/issue_templates"
mkdir -p "$DEST" || exit 1
added=0 same=0 kept=""
for src in "$ROOT"/templates/issue_templates/*.md; do
  name="$(basename "$src")"
  if [ ! -e "$DEST/$name" ]; then
    cp "$src" "$DEST/$name" || exit 1
    added=$((added + 1))
  elif cmp -s "$src" "$DEST/$name"; then
    same=$((same + 1))
  else
    kept="$kept $name"
  fi
done
echo "issue-templates: $added added, $same unchanged"
[ -z "$kept" ] || echo "issue-templates: kept the repo's own version of:$kept"
