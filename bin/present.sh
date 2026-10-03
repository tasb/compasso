#!/usr/bin/env bash
# The solution presentation: one self-contained HTML page with the functional and technical solution,
# the decisions, the sprints and the next sprint's user stories, built from Compasso's own files.
#
#   present.sh --repo R --out O [--ui F] [--data-out D]
#
# Reads what exists and says what is missing on the page itself:
#   .compasso/product/brief.md          the problem, users, outcomes, MVP, constraints, risks
#   .compasso/product/prototype.json    the prototype's screens and flows
#   .compasso/backlog.yaml              features, the MVP line
#   .compasso/product/architecture.yaml the technical solution
#   .compasso/roadmap.yaml              the sprints
#   .compasso/plan.yaml                 the next sprint's stories and blockers, with tracker links
#   .compasso/records/                  decisions from the product and plan records
# F (JSON) overrides the page's labels: {"key": "text"}; the keys are in templates/presentation.html.
# D writes the assembled data, for checks. Everything is escaped when shown: the page runs no input.
# Exit: 0 written | 1 nothing to present, or an input is invalid | 2 usage
set -u

BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$BIN/.." && pwd)"
REPO="." OUT="" UI="" DOUT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --ui) UI="$2"; shift 2 ;;
    --data-out) DOUT="$2"; shift 2 ;;
    *) echo "present: unknown argument '$1'" >&2; exit 2 ;;
  esac
done
[ -n "$OUT" ] || { echo "present: needs --out" >&2; exit 2; }
C="$REPO/.compasso"
[ -f "$C/product/brief.md" ] || [ -f "$C/backlog.yaml" ] || { echo "present: nothing to present yet - run /compasso:discover and /compasso:backlog first" >&2; exit 1; }
y() { [ -f "$1" ] && { yq -o=json . "$1" || { echo "present: $1 is not valid YAML" >&2; exit 1; }; } || echo null; }

# the brief: its "## " sections, as text (the page renders a small, escaped subset of Markdown)
brief=null
if [ -f "$C/product/brief.md" ]; then
  brief="$(awk '
    /^# / && !t { t = substr($0, 3); next }
    /^## / { if (s != "") printf "%s\x1e%s\x1f", s, b; s = substr($0, 4); b = ""; next }
    /^<!--/ { next }
    { b = b $0 "\n" }
    END { if (s != "") printf "%s\x1e%s\x1f", s, b; printf "\x1d%s", t }' "$C/product/brief.md" |
    jq -Rs '(split("\u001d")) as $p | {title: $p[1], sections: [$p[0] | split("\u001f")[] | select(. != "") | split("\u001e") | {title: .[0], text: (.[1] | sub("\\s+$"; ""))}]}')"
fi

back="$(y "$C/backlog.yaml")"; arch="$(y "$C/product/architecture.yaml")"
road="$(y "$C/roadmap.yaml")"; plan="$(y "$C/plan.yaml")"
inv=null; ip="$(jq -r '.product.prototype.inventory // empty' <<<"$back")"
[ -n "$ip" ] && [ -f "$REPO/$ip" ] && inv="$(jq -c . "$REPO/$ip")"

# decisions recorded by the product stages and the plans
decisions="$( { for f in "$C"/records/product/*.md "$C"/records/S*/plan.md "$C"/records/S*/F-*.md; do
    [ -f "$f" ] || continue
    awk -v src="${f#"$C"/records/}" '/^## /{on = ($0 == "## Decisions"); next} on && /^- / && $0 != "- None" {print src "\t" substr($0, 3)}' "$f"
  done; } | jq -Rs 'split("\n") | map(select(. != "") | split("\t") | {source: .[0], text: .[1]})')"

provider="$("$BIN/config.sh" get --repo "$REPO" .tracker.provider 2>/dev/null)"
host="$("$BIN/config.sh" get --repo "$REPO" .tracker.host 2>/dev/null)"
proj="$("$BIN/config.sh" get --repo "$REPO" .tracker.project 2>/dev/null)"
case "$provider" in
  github) items="https://${host:-github.com}/$proj/issues/" ;;
  gitlab) items="https://${host:-gitlab.com}/$proj/-/issues/" ;;
  *) items="" ;;
esac
ui='{}'; [ -n "$UI" ] && { ui="$(jq -c . "$UI")" || { echo "present: $UI is not valid JSON" >&2; exit 1; }; }

data="$(jq -n --argjson brief "$brief" --argjson back "$back" --argjson arch "$arch" --argjson road "$road" \
  --argjson plan "$plan" --argjson inv "$inv" --argjson dec "$decisions" --argjson ui "$ui" \
  --arg items "$items" --arg date "$(date +%F)" --arg lang "$("$BIN/config.sh" get --repo "$REPO" .test_guide.language 2>/dev/null)" '
  def link($n): if $items != "" and ($n | type) == "number" then $items + ($n | tostring) else null end;
  {date: $date, lang: (if $lang == "" then "en" else $lang end), ui: $ui,
   name: ($back.product.name // $brief.title // "Product"),
   brief: $brief,
   prototype: (if $inv then {source: $inv.source, where: $inv.where, screens: [$inv.screens[] | {id, name, where, forms: ((.forms // []) | length), actions: (.actions // [])}], flows: ($inv.flows // [])} else null end),
   features: (if $back then [$back.features[] | {key, title, goal, mvp, size_h, depends_on, sources, scope, acceptance, sensitive, url: link(.gitlab)}] else null end),
   architecture: $arch,
   roadmap: $road,
   plan: (if $plan then {sprint: $plan.epic.sprint.number, goal: $plan.epic.goal, start: $plan.epic.sprint.start, end: $plan.epic.sprint.end,
     features: [$plan.features[] | {key, title, url: link(.gitlab), stories: [(.stories // [])[] | {key, title, as, want, so_that, acceptance, estimate_h, owner, depends_on, blocked_by, tests, url: link(.gitlab)}]}],
     blockers: [($plan.blockers // [])[] | {key, title, assignee, url: link(.gitlab)}]} else null end),
   decisions: $dec}')" || { echo "present: could not assemble the data" >&2; exit 1; }
[ -n "$DOUT" ] && printf '%s\n' "$data" > "$DOUT"

# every "<" as \u003c: the same JSON, and HTML never sees a tag (no "</script>", no "<!--") in the data block
json="$(jq -c . <<<"$data" | sed 's/</\\u003c/g')"
mkdir -p "$(dirname "$OUT")"
J="$json" awk 'BEGIN { j = ENVIRON["J"] } { i = index($0, "__PRESENTATION_DATA__"); if (i) print substr($0, 1, i - 1) j substr($0, i + 21); else print }' \
  "$ROOT/templates/presentation.html" > "$OUT" || exit 1
echo "present: wrote $OUT"
