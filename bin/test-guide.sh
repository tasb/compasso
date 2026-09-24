#!/usr/bin/env bash
# Render a sprint's test guide for business testers as one self-contained HTML file.
#
#   test-guide.sh --data F --out O
#
# F (JSON): {id, language, title, goal, dates: {start, end}, where?, features: [{key, iid,
#   title, whats_new, why?, before?: [], scenarios: [{id, title, steps: [], expected}],
#   not_included?: [], known_issues?: []}], verified_automatically?: [], ui?: {}}
# The page shows no work items, merge requests or code; `iid` is kept only so
# results can be filed as bugs on the right feature.
# Exit: 0 written | 1 invalid data
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DATA="" OUT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --data) DATA="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    *) echo "test-guide: unknown argument '$1'" >&2; exit 1 ;;
  esac
done
[ -f "$DATA" ] && [ -n "$OUT" ] || { echo "test-guide: needs --data and --out" >&2; exit 1; }

problems="$(jq -r '
  def need($p; $v): if ($v // "") == "" or $v == [] then "\($p) is required" else empty end;
  need("id"; .id), need("title"; .title), need("goal"; .goal), need("dates.start"; .dates.start),
  need("dates.end"; .dates.end), need("features"; .features),
  (.features // [] | to_entries[] | .key as $i | .value as $f
    | need("features[\($i)].key"; $f.key), need("features[\($i)].title"; $f.title),
      need("features[\($i)].whats_new"; $f.whats_new), need("features[\($i)].scenarios"; $f.scenarios),
      ($f.scenarios // [] | to_entries[] | .key as $j | .value as $s
        | need("features[\($i)].scenarios[\($j)].id"; $s.id), need("features[\($i)].scenarios[\($j)].title"; $s.title),
          need("features[\($i)].scenarios[\($j)].steps"; $s.steps), need("features[\($i)].scenarios[\($j)].expected"; $s.expected))),
  ([.features[]?.scenarios[]?.id] | group_by(.)[] | select(length > 1) | "scenario id \(.[0]) is used more than once")
' "$DATA" 2>/dev/null)" || { echo "test-guide: $DATA is not valid JSON" >&2; exit 1; }
[ -z "$problems" ] || { printf 'test-guide: %s\n' "$problems" >&2; exit 1; }

# "</" would end the script element early; "<\/" means the same inside JSON
json="$(jq -c . "$DATA" | sed 's#</#<\\/#g')"
mkdir -p "$(dirname "$OUT")"
# ENVIRON, not awk -v: -v would turn the JSON's \" escapes into bare quotes
JSON="$json" awk '{ i = index($0, "__GUIDE_DATA__"); if (i) { print substr($0, 1, i - 1) ENVIRON["JSON"] substr($0, i + 14) } else print }' \
  "$ROOT/templates/test-guide.html" > "$OUT"
echo "test-guide: wrote $OUT"
