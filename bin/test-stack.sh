#!/usr/bin/env bash
# What a project tests with, per language and area, and Compasso's default where it has nothing.
# The defaults live in templates/test-defaults.yaml; they apply only to an area with nothing yet.
#
#   test-stack.sh detect   --repo R [--json]    languages found, and per area: what the project uses
#                                               (existing) or the default Compasso would use (default)
#   test-stack.sh write    --repo R             record the result as `testing` in .compasso/project.yaml
#   test-stack.sh defaults --lang ID [--json]   the defaults of one language (for a new repository)
#
# Areas: unit, api (API and integration), e2e (browser), coverage, property (property-based).
# An area is also existing when the project's config already has its command: commands.test (unit),
# commands.e2e (e2e), coverage.command (coverage).
# Exit: 0 | 1 failure | 2 usage
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CAT="$ROOT/templates/test-defaults.yaml"
CMD="${1:-}"; shift || true
REPO="." JSON=0 LANG_ID=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --json) JSON=1; shift ;;
    --lang) LANG_ID="$2"; shift 2 ;;
    *) echo "test-stack: unknown argument '$1'" >&2; exit 2 ;;
  esac
done
AREAS="unit api e2e coverage property"
catalog="$(yq -o=json . "$CAT")" || { echo "test-stack: cannot read $CAT" >&2; exit 1; }

glob_re() { # globs, one per line -> one extended regex matching repository paths
  sed -e 's/[.+^$(){}|]/\\&/g' -e 's#\*\*/#<ANY>#g' -e 's#\*#[^/]*#g' -e 's#<ANY>#(.*/)?#g' -e 's/^/^/' -e 's/$/$/' | paste -sd'|' -
}
tracked() { # the repository's files, relative, without dependencies and Compasso's runs
  { git -C "$REPO" ls-files 2>/dev/null || ( cd "$REPO" && find . -type f | sed 's#^\./##' ); } |
    grep -vE '(^|/)(node_modules|vendor|target|dist|build|\.venv|venv)/|^\.compasso/runs/'
}
cfg() { [ -f "$REPO/.compasso/project.yaml" ] && yq -r "$1 // \"\"" "$REPO/.compasso/project.yaml" 2>/dev/null; }

detect() {
  local files langs='[]' id re corpus area out found name rx inh cmdv
  files="$(tracked)"
  for id in $(jq -r '.languages | keys_unsorted[]' <<<"$catalog"); do
    re="$(jq -r --arg l "$id" '.languages[$l].manifests[]' <<<"$catalog" | glob_re)"
    printf '%s\n' "$files" | grep -qE "$re" && langs="$(jq -c --arg l "$id" '. + [$l]' <<<"$langs")"
  done
  if [ "$(jq length <<<"$langs")" -eq 0 ]; then
    for id in $(jq -r '.languages | to_entries[] | select(.value.manifests_if_alone) | .key' <<<"$catalog"); do
      re="$(jq -r --arg l "$id" '.languages[$l].manifests_if_alone[]' <<<"$catalog" | glob_re)"
      printf '%s\n' "$files" | grep -qE "$re" && langs="$(jq -c --arg l "$id" '. + [$l]' <<<"$langs")"
    done
  fi
  out='[]'
  for id in $(jq -r '.[]' <<<"$langs"); do
    re="$(jq -r --arg l "$id" '.languages[$l].files[]' <<<"$catalog" | glob_re)"
    corpus="$(printf '%s\n' "$files" | grep -E "$re" | head -2000)"
    res='{}'
    for area in $AREAS; do
      found=""
      if [ -n "$corpus" ]; then
        while IFS=$'\t' read -r name rx; do
          [ -n "$name" ] || continue
          if (cd "$REPO" && printf '%s\n' "$corpus" | tr '\n' '\0' | xargs -0 grep -E -l -m1 -e "$rx" 2>/dev/null | head -1 | grep -q .); then found="$name"; break; fi
        done <<EOF
$(jq -r --arg l "$id" --arg a "$area" '.languages[$l].areas[$a].found // {} | to_entries[] | "\(.key)\t\(.value)"' <<<"$catalog")
EOF
      fi
      how=""
      [ -n "$found" ] && how=found
      if [ -z "$found" ]; then
        inh="$(jq -r --arg l "$id" --arg a "$area" '.languages[$l].areas[$a].inherits // empty' <<<"$catalog")"
        if [ -n "$inh" ] && [ "$(jq -r --arg a "$inh" '.[$a].source // ""' <<<"$res")" = existing ]; then
          found="$(jq -r --arg a "$inh" '.[$a].use' <<<"$res")"; how="same as $inh"
        fi
      fi
      if [ -z "$found" ]; then
        case "$area" in unit) cmdv="$(cfg .commands.test)" ;; e2e) cmdv="$(cfg .commands.e2e)" ;; coverage) cmdv="$(cfg .coverage.command)" ;; *) cmdv="" ;; esac
        [ -n "$cmdv" ] && found="the project's command: $cmdv" && how=config
      fi
      res="$(jq -c --arg a "$area" --arg f "$found" --arg how "$how" --argjson d "$(jq -c --arg l "$id" --arg a "$area" '.languages[$l].areas[$a]' <<<"$catalog")" '
        .[$a] = (if $f != "" then {use: $f, source: "existing", how: $how}
                 else {use: $d.default, source: "default"} + (if $d.command then {command: $d.command, report: $d.report} else {} end) end)' <<<"$res")"
    done
    out="$(jq -c --arg l "$id" --arg n "$(jq -r --arg l "$id" '.languages[$l].name' <<<"$catalog")" --argjson r "$res" '. + [{lang: $l, name: $n, areas: $r}]' <<<"$out")"
  done
  printf '%s\n' "$out"
}

show() { # detect JSON -> table
  jq -r '
    if length == 0 then "No language found yet: the walking skeleton picks the stack, and its tests use that language'"'"'s defaults (test-stack.sh defaults --lang <id>)."
    else .[] | "\(.name)", (.areas | to_entries[] | "  \(.key | . + " " * (9 - length))\(.value.use)\(if .value.source == "default" then "   (default: nothing found)" else "" end)") end' <<<"$1"
}

case "$CMD" in
  detect)
    r="$(detect)" || exit 1
    if [ "$JSON" -eq 1 ]; then printf '%s\n' "$r"; else show "$r"; fi ;;
  write)
    [ -f "$REPO/.compasso/project.yaml" ] || { echo "test-stack: no .compasso/project.yaml - run /compasso:setup" >&2; exit 1; }
    r="$(detect)" || exit 1
    T="$(jq -c 'map({key: .lang, value: (.areas | map_values({use, source}))}) | from_entries' <<<"$r")" \
      yq -i '.testing = (strenv(T) | from_json)' "$REPO/.compasso/project.yaml" || exit 1
    echo "test-stack: recorded $(jq length <<<"$r") language(s) as testing in .compasso/project.yaml" ;;
  defaults)
    [ -n "$LANG_ID" ] || { echo "test-stack: defaults needs --lang ($(jq -r '.languages | keys_unsorted | join(", ")' <<<"$catalog"))" >&2; exit 2; }
    d="$(jq -c --arg l "$LANG_ID" '.languages[$l] // empty | {lang: $l, name, areas: (.areas | map_values({use: .default, source: "default"} + (if .command then {command, report} else {} end)))}' <<<"$catalog")"
    [ -n "$d" ] || { echo "test-stack: unknown language '$LANG_ID'" >&2; exit 2; }
    if [ "$JSON" -eq 1 ]; then printf '%s\n' "$d"; else show "[$d]"; fi ;;
  *) echo "usage: test-stack.sh detect|write|defaults ..." >&2; exit 2 ;;
esac
