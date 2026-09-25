#!/usr/bin/env bash
# Decision records: one Markdown file per plan, feature and story run, committed under
# .compasso/records/S<n>/, so what was found and decided lives in the repository.
#
#   record.sh path   --repo R --kind plan|feature|story --key K [--sprint S<n>]   the record's path
#   record.sh path   --repo R --kind discover|backlog|roadmap                     a product stage's record
#   record.sh write  --data F --out PATH        render the record from its data file
#   record.sh story  --repo R --run DIR         the story's record, from DIR/story.json, DIR/findings.json
#                                               and DIR/record.json (decisions, takeaways, constraints, missing)
#
# Data file (JSON): {title, date, by, approved_by?, ref?, links?: [{text, url}],
#   findings: [{by, text, outcome}], decisions: [{text, by?, date?, assumed?}],
#   takeaways: [text], constraints: [text], missing: [{text, status}]}
# All five lists are required and may be empty: an empty section says "None", so a
# reader knows it was considered.
# Exit: 0 | 1 invalid data or missing input | 2 usage
set -u

BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CMD="${1:-}"; shift || true
REPO="." KIND="" KEY="" SPRINT="" DATA="" OUT="" RUN=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --kind) KIND="$2"; shift 2 ;;
    --key) KEY="$2"; shift 2 ;;
    --sprint) SPRINT="$2"; shift 2 ;;
    --data) DATA="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --run) RUN="$2"; shift 2 ;;
    *) echo "record: unknown argument '$1'" >&2; exit 2 ;;
  esac
done

CHECK='def need(k): if has(k) and (.[k] | type) == "array" then empty else "\(k) must be a list (empty when there is nothing)" end;
  [ (if (.title // "") == "" then "title is required" else empty end),
    (if (.date // "") == "" then "date is required" else empty end),
    need("findings"), need("decisions"), need("takeaways"), need("constraints"), need("missing"),
    (.findings[]? | select((.text // "") == "" or (.by // "") == "") | "every finding needs by and text"),
    (.decisions[]? | select((.text // "") == "") | "every decision needs text"),
    (.missing[]? | select((.text // "") == "") | "every missing point needs text") ] | unique[]'

RENDER='def none: if length == 0 then "- None" else .[] end;
  "# \(.title) · \(.date)",
  ([ (if .approved_by then "Approved by @\(.approved_by)" else empty end),
     (if .by then "Run by @\(.by)" else empty end),
     (if .ref then "plan.yaml @ \(.ref)" else empty end),
     (.links // [] | .[] | "[\(.text)](\(.url))") ] | if length > 0 then join(" · ") else empty end),
  "", "## Findings", (.findings | map("- \(.by): \(.text)" + (if .outcome then " → \(.outcome)" else "" end)) | none),
  "", "## Decisions", (.decisions | map("- " + (if .assumed then "Assumed: " else "" end) + .text
      + (if .by or .date then " (" + ([(if .by then "@\(.by)" else empty end), (.date // empty)] | join(", ")) + ")" else "" end)) | none),
  "", "## Takeaways", (.takeaways | map("- \(.)") | none),
  "", "## Constraints", (.constraints | map("- \(.)") | none),
  "", "## Missing points", (.missing | map("- \(.text)" + (if .status then " (\(.status))" else "" end)) | none)'

write_record() { # data-file out-file
  local problems
  [ -f "$1" ] || { echo "record: no data file $1" >&2; return 1; }
  jq -e . "$1" >/dev/null 2>&1 || { echo "record: $1 is not valid JSON" >&2; return 1; }
  problems="$(jq -r "$CHECK" "$1")"
  [ -z "$problems" ] || { printf 'record: %s\n' "$problems" >&2; return 1; }
  mkdir -p "$(dirname "$2")" && jq -r "$RENDER" "$1" > "$2" || return 1
  echo "record: wrote $2"
}

sprint_of_plan() { yq -r '.epic.sprint.number // ""' "$REPO/.compasso/plan.yaml" 2>/dev/null | sed 's/^\(.\)/S\1/'; }

case "$CMD" in
  path)
    case "$KIND" in discover|backlog|roadmap) echo ".compasso/records/product/$KIND.md"; exit 0 ;; esac
    [ -n "$KIND" ] && [ -n "$KEY" ] || { echo "record: path needs --kind and --key" >&2; exit 2; }
    [ -n "$SPRINT" ] || SPRINT="$(sprint_of_plan)"
    [ -n "$SPRINT" ] || SPRINT=backlog
    case "$KIND" in
      plan) echo ".compasso/records/$SPRINT/plan.md" ;;
      feature) echo ".compasso/records/$SPRINT/$KEY.md" ;;
      story) echo ".compasso/records/$SPRINT/stories/$KEY.md" ;;
      *) echo "record: --kind is plan, feature, story, discover, backlog or roadmap" >&2; exit 2 ;;
    esac ;;
  write)
    [ -n "$DATA" ] && [ -n "$OUT" ] || { echo "record: write needs --data and --out" >&2; exit 2; }
    write_record "$DATA" "$OUT" || exit 1 ;;
  story)
    [ -n "$RUN" ] || { echo "record: story needs --run" >&2; exit 2; }
    for f in story.json findings.json; do [ -f "$RUN/$f" ] || { echo "record: missing $RUN/$f" >&2; exit 1; }; done
    extra='{}'; [ -f "$RUN/record.json" ] && extra="$(cat "$RUN/record.json")"
    jq -e . >/dev/null 2>&1 <<<"$extra" || { echo "record: $RUN/record.json is not valid JSON" >&2; exit 1; }
    iid="$(jq -r .iid "$RUN/story.json")"
    out="$REPO/$("$0" path --repo "$REPO" --kind story --key "$iid" --sprint "$(jq -r '.milestone // "backlog"' "$RUN/story.json")")"
    # review and security findings, with what happened to each
    jq -n --slurpfile s "$RUN/story.json" --slurpfile f "$RUN/findings.json" --argjson x "$extra" --arg date "$(date +%F)" '
      $s[0] as $s | {
        title: "#\($s.iid) \($s.title)", date: $date, by: ($x.by // null),
        findings: [$f[0][] | {by, text: ("[\(.severity)] \(.summary)" + (if .file then " (`\(.file)\(if .line then ":\(.line)" else "" end)`)" else "" end)),
          outcome: ({"fixed": "fixed", "open": "open", "followup": "follow-up #\(.followup_iid // "?")"}[.status] // .status)}],
        decisions: ($x.decisions // []), takeaways: ($x.takeaways // []),
        constraints: ($x.constraints // []), missing: ($x.missing // [])}' > "$RUN/record-data.json" || exit 1
    write_record "$RUN/record-data.json" "$out" || exit 1 ;;
  *) echo "usage: record.sh path|write|story ..." >&2; exit 2 ;;
esac
