#!/usr/bin/env bash
# Targeted learnings: one lesson per file in the product repo's docs/learnings/,
# with frontmatter naming the paths and roles it applies to.
#
#   learnings.sh recall --repo R --role ROLE [--story F]   lessons for ROLE that overlap the story's Touches
#   learnings.sh check  --repo R                           every lesson is well formed; flag stale ones
#   learnings.sh list   --repo R                           one line per lesson
#
# A lesson file:
#   ---
#   title: <one line>
#   paths: ["src/billing/**"]        # globs it applies to; [] means everywhere
#   roles: [security, builder]       # planner tester builder reviewer security approver shipper
#   date: 2026-09-24
#   source: "#8"                     # where it was learnt
#   ---
#   <at most 5 lines: what happened, the rule, how to apply it>
#
# recall without --story returns every lesson for the role (the planner's case).
# Exit: 0 | 1 a malformed lesson (check) | 2 usage
set -u
set -f   # paths are patterns

CMD="${1:-}"; shift || true
REPO="." ROLE="" STORY=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --role) ROLE="$2"; shift 2 ;;
    --story) STORY="$2"; shift 2 ;;
    *) echo "learnings: unknown argument '$1'" >&2; exit 2 ;;
  esac
done
DIR="$REPO/docs/learnings"
ROLES="planner tester builder reviewer security approver shipper mutator"

lessons() { [ -d "$DIR" ] && find "$DIR" -maxdepth 1 -name '*.md' | sort; }
front() { yq --front-matter=extract -o=json '.' "$1" 2>/dev/null; }
body() { awk 'BEGIN{n=0} /^---[[:space:]]*$/{n++; next} n>=2' "$1"; }

case "$CMD" in
  recall)
    [ -n "$ROLE" ] || { echo "learnings: recall needs --role" >&2; exit 2; }
    touches='[]'
    if [ -n "$STORY" ]; then
      [ -f "$STORY" ] || { echo "learnings: no story file $STORY" >&2; exit 2; }
      touches="$(jq -c '.story.touches // []' "$STORY")"
    fi
    for f in $(lessons); do
      fm="$(front "$f")" || continue
      jq -e --arg r "$ROLE" --argjson t "$touches" --argjson all "$([ -z "$STORY" ] && echo true || echo false)" '
        def p: sub("[*?\\[].*$"; "");
        (.roles // [] | index($r)) and
        ($all or (.paths // []) == [] or any((.paths // [])[] | p; . as $x | any($t[] | p; . as $y
          | ($y | startswith($x)) or ($x | startswith($y)))))' <<<"$fm" >/dev/null || continue
      printf '## %s\n%s\n\n' "$(jq -r .title <<<"$fm")" "$(body "$f" | sed '/^[[:space:]]*$/d')"
    done
    ;;
  check)
    bad=0
    for f in $(lessons); do
      name="${f#"$REPO"/}"
      fm="$(front "$f")"
      problems="$(jq -r --arg roles "$ROLES" '
        ($roles | split(" ")) as $known
        | (if (.title // "") == "" then "title is required" else empty end),
          (if (.roles // []) | length == 0 then "roles is required" else empty end),
          ((.roles // [])[] | select(. as $r | $known | index($r) | not) | "unknown role \(.)"),
          (if (.paths | type) != "array" then "paths must be a list ([] for everywhere)" else empty end),
          (if (.date // "") == "" then "date is required" else empty end)' <<<"${fm:-null}" 2>/dev/null)" ||
        problems="no frontmatter"
      lines="$(body "$f" | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' ')"
      [ "$lines" -ge 1 ] || problems="$problems"$'\n'"the lesson is empty"
      [ "$lines" -le 5 ] || problems="$problems"$'\n'"the lesson has $lines lines; keep it to 5"
      problems="$(printf '%s\n' "$problems" | sed '/^$/d')"
      if [ -n "$problems" ]; then
        printf '%s\n' "$problems" | sed "s#^#learnings: $name: #"; bad=1; continue
      fi
      # stale: every path it names matches nothing in the repo any more
      paths="$(jq -r '.paths[]' <<<"$fm")"
      if [ -n "$paths" ]; then
        alive=0
        while IFS= read -r g; do
          while IFS= read -r t; do case "$t" in $g) alive=1; break ;; esac; done <<EOF
$(git -C "$REPO" ls-files)
EOF
          [ "$alive" -eq 1 ] && break
        done <<EOF
$paths
EOF
        [ "$alive" -eq 1 ] || echo "learnings: $name: stale - none of its paths matches a file any more; remove it or update its paths"
      fi
    done
    [ "$bad" -eq 0 ] && echo "learnings: $(lessons | wc -l | tr -d ' ') lessons checked"
    exit "$bad"
    ;;
  list)
    for f in $(lessons); do
      fm="$(front "$f")" || continue
      jq -r --arg f "${f#"$REPO"/}" '"\(.date)  \(.roles | join(","))  \(.title)  (\($f))"' <<<"$fm"
    done
    ;;
  *) echo "usage: learnings.sh recall|check|list --repo R ..." >&2; exit 2 ;;
esac
