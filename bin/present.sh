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
# The labels are in the project's language (templates/locales/); F (JSON) changes any of them: {"key": "text"}.
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

# decisions recorded by the product stages and the plans, under their heading in any language
heads="$(for f in "$ROOT"/templates/locales/*.yaml; do yq -r .text.rec_decisions "$f"; done)"
nones="$(for f in "$ROOT"/templates/locales/*.yaml; do yq -r .text.rec_none "$f"; done)"
decisions="$( { for f in "$C"/records/product/*.md "$C"/records/S*/plan.md "$C"/records/S*/F-*.md; do
    [ -f "$f" ] || continue
    HEADS="$heads" NONES="$nones" awk -v src="${f#"$C"/records/}" 'BEGIN { split(ENVIRON["HEADS"], h, "\n"); for (i in h) hd["## " h[i]] = 1; split(ENVIRON["NONES"], n, "\n"); for (i in n) no["- " n[i]] = 1 }
      /^## / { on = ($0 in hd); next } on && /^- / && !($0 in no) { print src "\t" substr($0, 3) }' "$f"
  done; } | jq -Rs 'split("\n") | map(select(. != "") | split("\t") | {source: .[0], text: .[1]})')"

provider="$("$BIN/config.sh" get --repo "$REPO" .tracker.provider 2>/dev/null)"
host="$("$BIN/config.sh" get --repo "$REPO" .tracker.host 2>/dev/null)"
proj="$("$BIN/config.sh" get --repo "$REPO" .tracker.project 2>/dev/null)"
case "$provider" in
  github) items="https://${host:-github.com}/$proj/issues/" ;;
  gitlab) items="https://${host:-gitlab.com}/$proj/-/issues/" ;;
  *) items="" ;;
esac
L="$("$BIN/locale.sh" --repo "$REPO")" || exit 1
ui="$(jq -c '.ui.presentation' <<<"$L")"   # the project's language; --ui changes any label
[ -n "$UI" ] && { ui="$(jq -c --argjson base "$ui" '$base + .' "$UI")" || { echo "present: $UI is not valid JSON" >&2; exit 1; }; }

# every part through a file, never an argument: a large plan passes the 128 KB Linux allows one argument
f() { printf '%s' "$1"; }
data="$(jq -n --slurpfile brief <(f "$brief") --slurpfile back <(f "$back") --slurpfile arch <(f "$arch") --slurpfile road <(f "$road") \
  --slurpfile plan <(f "$plan") --slurpfile inv <(f "$inv") --slurpfile dec <(f "$decisions") --argjson ui "$ui" \
  --arg items "$items" --arg date "$(date +%F)" --arg lang "$("$BIN/locale.sh" --repo "$REPO" | jq -r .lang)" '
  $brief[0] as $brief | $back[0] as $back | $arch[0] as $arch | $road[0] as $road | $plan[0] as $plan | $inv[0] as $inv | $dec[0] as $dec
  | def link($n): if $items != "" and ($n | type) == "number" then $items + ($n | tostring) else null end;
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

# the page: data, language and title written by html-inject.sh, through files and checked before it is kept
tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
printf '%s' "$data" > "$tmp"
"$BIN/html-inject.sh" --template "$ROOT/templates/presentation.html" --marker __PRESENTATION_DATA__ --data "$tmp" \
  --lang "$(jq -r .lang <<<"$data")" --title "$(jq -r '"\(.name) · \(.ui.solution)"' <<<"$data")" --out "$OUT" || exit 1
echo "present: wrote $OUT"
