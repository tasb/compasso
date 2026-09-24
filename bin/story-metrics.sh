#!/usr/bin/env bash
# Record what happens during a story run, then write the story's metrics file.
#
#   story-metrics.sh agent --run DIR --role R --model M [--tokens N] [--ms N]   one agent run
#   story-metrics.sh event --run DIR --type verify-fail|violation|round|replan  one event
#   story-metrics.sh write --run DIR --repo R                                   .compasso/metrics/<iid>.json
#
# Runs and events are appended to DIR/events.jsonl with a timestamp. `write`
# summarises them with DIR/story.json, DIR/findings.json and DIR/coverage.json;
# the file is committed in the story's merge request so the numbers outlive the
# local run folder. Tokens and time are what the harness reports; when it reports
# none, they are left out rather than guessed.
# Exit: 0 | 2 usage or missing input
set -u

CMD="${1:-}"; shift || true
RUN="" REPO="." ROLE="" MODEL="" TOKENS="" MS="" TYPE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --run) RUN="$2"; shift 2 ;;
    --repo) REPO="$2"; shift 2 ;;
    --role) ROLE="$2"; shift 2 ;;
    --model) MODEL="$2"; shift 2 ;;
    --tokens) TOKENS="$2"; shift 2 ;;
    --ms) MS="$2"; shift 2 ;;
    --type) TYPE="$2"; shift 2 ;;
    *) echo "story-metrics: unknown argument '$1'" >&2; exit 2 ;;
  esac
done
[ -n "$RUN" ] || { echo "story-metrics: --run is required" >&2; exit 2; }
now() { date -u +%Y-%m-%dT%H:%M:%SZ; }
num() { case "$1" in ''|*[!0-9]*) return 1 ;; esac; }

case "$CMD" in
  agent)
    [ -n "$ROLE" ] && [ -n "$MODEL" ] || { echo "story-metrics: agent needs --role and --model" >&2; exit 2; }
    { [ -z "$TOKENS" ] || num "$TOKENS"; } && { [ -z "$MS" ] || num "$MS"; } ||
      { echo "story-metrics: --tokens and --ms are whole numbers" >&2; exit 2; }
    mkdir -p "$RUN"
    jq -cn --arg at "$(now)" --arg role "$ROLE" --arg model "$MODEL" --arg tokens "$TOKENS" --arg ms "$MS" \
      '{at: $at, type: "agent", role: $role, model: $model}
       + (if $tokens == "" then {} else {tokens: ($tokens | tonumber)} end)
       + (if $ms == "" then {} else {ms: ($ms | tonumber)} end)' >> "$RUN/events.jsonl"
    ;;
  event)
    case "$TYPE" in verify-fail|violation|round|replan) ;; *) echo "story-metrics: unknown event '$TYPE'" >&2; exit 2 ;; esac
    mkdir -p "$RUN"
    jq -cn --arg at "$(now)" --arg t "$TYPE" '{at: $at, type: $t}' >> "$RUN/events.jsonl"
    ;;
  write)
    [ -f "$RUN/story.json" ] || { echo "story-metrics: no $RUN/story.json" >&2; exit 2; }
    events="$( [ -f "$RUN/events.jsonl" ] && jq -sc . "$RUN/events.jsonl" || echo '[]')"
    findings="$( [ -f "$RUN/findings.json" ] && cat "$RUN/findings.json" || echo '[]')"
    coverage="$( [ -f "$RUN/coverage.json" ] && cat "$RUN/coverage.json" || echo 'null')"
    iid="$(jq -r .iid "$RUN/story.json")"
    mkdir -p "$REPO/.compasso/metrics"
    jq -n --slurpfile s "$RUN/story.json" --argjson e "$events" --argjson f "$findings" --argjson c "$coverage" '
      $s[0] as $s
      | def sev($by): [$f[] | select(.by == $by)] as $x
          | {blocker: ([$x[] | select(.severity == "blocker")] | length),
             major: ([$x[] | select(.severity == "major")] | length),
             minor: ([$x[] | select(.severity == "minor")] | length)};
      def count($t): [$e[] | select(.type == $t)] | length;
      {
        iid: $s.iid, key: $s.story.key, title: $s.title, kind: $s.kind, estimate_h: $s.estimate_h,
        started: ([$e[].at] | min), finished: ([$e[].at] | max),
        review_rounds: count("round"),
        findings: {reviewer: sev("reviewer"), security: sev("security")},
        security_open: ([$f[] | select(.by == "security" and (.verified_by != "security" or .status == "open"))] | length),
        verify_failures: count("verify-fail"), violations: count("violation"), replanned: (count("replan") > 0),
        coverage: (if $c == null then null else {status: $c.status, percent: $c.percent, min: $c.min} end),
        agents: [$e[] | select(.type == "agent") | {role, model} + (if .tokens then {tokens} else {} end) + (if .ms then {ms} else {} end)]
      }' > "$REPO/.compasso/metrics/$iid.json"
    echo "story-metrics: wrote .compasso/metrics/$iid.json"
    ;;
  *) echo "usage: story-metrics.sh agent|event|write --run DIR ..." >&2; exit 2 ;;
esac
