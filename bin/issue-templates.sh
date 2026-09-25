#!/usr/bin/env bash
# Install Compasso's work-item formats as issue templates.
#
#   issue-templates.sh --repo R   copy templates/issue_templates/*.md to R/.gitlab/issue_templates/,
#                                 or on GitHub (tracker.provider: github) to R/.github/ISSUE_TEMPLATE/
#                                 with each type's labels in the frontmatter and no "Depends on" line
#                                 (GitHub records dependencies as native "blocked by").
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

provider="$("$ROOT/bin/config.sh" get --repo "$REPO" .tracker.provider 2>/dev/null)"
if [ "$provider" = github ]; then DEST="$REPO/.github/ISSUE_TEMPLATE"; else DEST="$REPO/.gitlab/issue_templates"; fi
mkdir -p "$DEST" || exit 1
added=0 same=0 kept=""
TMP="$(mktemp)"; trap 'rm -f "$TMP"' EXIT

github_template() { # type -> the template with GitHub frontmatter
  local labels title=""
  case "$1" in
    Epic) labels="type::epic"; title="S<sprint>: " ;;
    Feature) labels="type::feature" ;;
    Story) labels="owner::either" ;;
    Bug) labels="type::bug" ;;
    Blocker) labels="type::blocker, priority::urgent" ;;
  esac
  printf -- '---\nname: %s\nabout: Compasso %s format\ntitle: "%s"\nlabels: %s\n---\n\n' "$1" "$(echo "$1" | tr 'A-Z' 'a-z')" "$title" "$labels"
  grep -v '^\*\*Depends on:\*\*' "$ROOT/templates/issue_templates/$1.md" |
    sed 's/<!-- #iid of the blocker task; delete the line if none -->/<!-- #number of the blocker issue, also set as "Blocked by" under Relationships; delete the line if none -->/' | cat -s
}

for src in "$ROOT"/templates/issue_templates/*.md; do
  name="$(basename "$src")"
  if [ "$provider" = github ]; then
    github_template "${name%.md}" > "$TMP"; src="$TMP"; name="$(echo "$name" | tr 'A-Z' 'a-z')"
  fi
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
