#!/usr/bin/env bash
# A read-only readout of where the sprint, or one story, stands. It writes nothing:
# no tracker change (sprint-sync --read-only), no file, no approval.
#
#   status.sh --repo R [--milestone S<n>] [--json]   the sprint: what can be built, what waits and on whom,
#                                                    the plan on the default branch, approvals, local runs
#   status.sh --repo R --iid N [--json]              one story: tracker state, open dependencies, how far
#                                                    its local run got and the step to resume from
#
# A story run's stage is read from the files the story flow leaves in .compasso/runs/<iid>/
# (skills/story/SKILL.md steps): story.json (2), test-hashes (4), verify.json (5),
# coverage.json (6), findings.json and review rounds in events.jsonl (7), the story's
# committed metrics and changes.md (8), mr.md (9). The default branch is read from local
# git refs, as of the last fetch.
# Exit: 0 | 1 the tracker could not be read (the local part is still shown) | 2 usage
set -u

BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="." IID="" MS="" JSON=0
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --iid) IID="$2"; shift 2 ;;
    --milestone) MS="$2"; shift 2 ;;
    --json) JSON=1; shift ;;
    *) echo "status: unknown argument '$1'" >&2; exit 2 ;;
  esac
done
PLAN="$REPO/.compasso/plan.yaml"
RUNS="$REPO/.compasso/runs"

stage() { # iid [tracker labels json] -> {iid, step, stage, next}
  local d="$RUNS/$1" rounds vf viol gate total failed labels="${2:-[]}"
  [ -d "$d" ] || { jq -nc --argjson i "$1" '{iid: $i, step: 0, stage: "not started here", next: "/compasso:story \($i)"}'; return; }
  rounds=0 vf=0 viol=0
  if [ -f "$d/events.jsonl" ]; then
    rounds="$(jq -s '[.[] | select(.type == "round")] | length' "$d/events.jsonl")"
    vf="$(jq -s '[.[] | select(.type == "verify-fail")] | length' "$d/events.jsonl")"
    viol="$(jq -s '[.[] | select(.type == "violation")] | length' "$d/events.jsonl")"
  fi
  extra="$(jq -nc --argjson vf "$vf" --argjson viol "$viol" '{verify_failures: $vf, test_violations: $viol}')"
  out() { jq -nc --argjson i "$1" --argjson s "$2" --arg st "$3" --arg nx "$4" --argjson x "$extra" '{iid: $i, step: $s, stage: $st, next: $nx} + $x'; }
  if jq -e 'index("compasso::in-review")' <<<"$labels" >/dev/null; then
    out "$1" 10 "merge request open, in review" "a person reviews and merges (or the approver, with approvals.merge agent or risk)"
  elif [ -f "$d/mr.md" ]; then
    out "$1" 9 "merge request body written" "step 9: open the merge request and set the story in review"
  elif [ -f "$d/changes.md" ] && [ -f "$REPO/.compasso/metrics/$1.json" ]; then
    out "$1" 8 "shipped: follow-ups filed, metrics and record committed" "step 9: push the branch and open the merge request"
  elif [ -f "$d/findings.json" ]; then
    [ "$rounds" -gt 0 ] || rounds=1
    "$BIN/review-gate.sh" --findings "$d/findings.json" --for review >/dev/null 2>&1; gate=$?
    open="$(jq '[.[] | select(.status == "open" and (.severity == "blocker" or .severity == "major"))] | length' "$d/findings.json" 2>/dev/null || echo "?")"
    case "$gate" in
      0) out "$1" 7 "review clear after $rounds round(s)" "step 8: ship" ;;
      1) if [ "$rounds" -ge 3 ]; then out "$1" 7 "review still blocked after 3 rounds: $open open blocker or major" "hand back: a person decides (review-gate.sh --comment lists the findings)"
         else out "$1" 7 "review round $rounds: $open open blocker or major" "step 7: fix tests-first, then review round $((rounds + 1))"; fi ;;
      *) out "$1" 7 "review findings are malformed" "rewrite findings.json from the reviewers' output" ;;
    esac
  elif [ -f "$d/coverage.json" ]; then
    out "$1" 6 "coverage measured" "step 7: review and security review"
  elif [ -f "$d/verify.json" ]; then
    total="$(jq length "$d/verify.json")"; failed="$(jq '[.[] | select(.status == "fail")] | length' "$d/verify.json")"
    if [ "$failed" -eq 0 ]; then out "$1" 5 "verify passed ($total commands)" "step 6: coverage"
    elif [ "$vf" -ge 3 ]; then out "$1" 5 "verify failing after $vf attempts ($failed of $total commands)" "hand back: a person decides"
    else out "$1" 5 "verify failing ($failed of $total commands)" "step 5: the builder fixes the failures"; fi
  elif [ -f "$d/test-hashes" ]; then
    out "$1" 4 "failing tests written and committed" "step 5: build"
  elif [ -f "$d/story.json" ]; then
    out "$1" 2 "story read" "step 3: branch, then step 4: failing tests first"
  else
    out "$1" 0 "run folder is empty" "/compasso:story $1"
  fi
}

plan_on_default() { # -> {branch, state}
  local def
  def="$(git -C "$REPO" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')"
  [ -n "$def" ] || def=main
  if [ ! -f "$PLAN" ]; then jq -nc --arg b "$def" '{branch: $b, state: "no plan"}'
  elif ! git -C "$REPO" cat-file -e "origin/$def:.compasso/plan.yaml" 2>/dev/null; then jq -nc --arg b "$def" '{branch: $b, state: "not on the default branch"}'
  elif git -C "$REPO" show "origin/$def:.compasso/plan.yaml" 2>/dev/null | cmp -s - "$PLAN"; then jq -nc --arg b "$def" '{branch: $b, state: "on the default branch"}'
  else jq -nc --arg b "$def" '{branch: $b, state: "changed since the default branch"}'; fi
}

names() { jq -r '[.[] | "#\(.iid) \(.title)"] | join(", ")'; }

if [ -n "$IID" ]; then
  story="$("$BIN/tracker.sh" story --repo "$REPO" --iid "$IID" 2>&1)"; rc=$?
  if [ "$rc" -ne 0 ]; then
    st="$(stage "$IID")"
    if [ "$JSON" -eq 1 ]; then jq -n --arg e "$story" --argjson r "$st" '{tracker_error: $e, run: $r}'
    else echo "#$IID"; echo "Tracker: $story"; jq -r '"Run: \(.stage)\nNext: \(.next)"' <<<"$st"; fi
    exit 1
  fi
  tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT; printf '%s' "$story" > "$tmp"
  unapproved="$("$BIN/trust.sh" check --repo "$REPO" --story "$tmp" 2>/dev/null)"
  st="$(stage "$IID" "$(jq -c .labels <<<"$story")")"
  result="$(jq -n --argjson s "$story" --argjson r "$st" --arg u "$unapproved" '{
    iid: $s.iid, title: $s.title, tracker_state: $s.state, milestone: $s.milestone, feature: $s.feature,
    state: ([$s.labels[] | select(startswith("compasso::")) | sub("compasso::"; "")][0] // "new"),
    owner: ([$s.labels[] | select(startswith("owner::")) | sub("owner::"; "")][0] // null),
    estimate_h: $s.estimate_h, open_dependencies: $s.open_dependencies,
    unapproved_verify: ($u | split("\n") | map(select(. != ""))), run: $r}')"
  if [ "$JSON" -eq 1 ]; then printf '%s\n' "$result"; exit 0; fi
  jq -r '
    "#\(.iid) \(.title)",
    "State: \(if .tracker_state == "closed" then "closed" else .state end) · \(.estimate_h)h · owner \(.owner // "?")\(if .milestone then " · \(.milestone)" else "" end)\(if .feature then " · feature #\(.feature)" else "" end)",
    (if (.open_dependencies | length) > 0 then "Waits on: " + (.open_dependencies | map("#\(.iid) \(.title) (\(if .kind == "blocked_by" then "blocker" else "dependency" end))") | join(", ")) else empty end),
    (if (.unapproved_verify | length) > 0 then "Verify commands not approved here: " + (.unapproved_verify | map("`\(.)`") | join(", ")) else empty end),
    "Run: \(.run.stage)" + (if (.run.verify_failures // 0) > 0 then " · \(.run.verify_failures) verify failure(s)" else "" end) + (if (.run.test_violations // 0) > 0 then " · \(.run.test_violations) test violation(s)" else "" end),
    "Next: \(if .tracker_state == "closed" then "nothing: the story is closed"
              elif .run.step == 0 and (.open_dependencies | length) > 0 then "wait for " + (.open_dependencies | map("#\(.iid)") | join(", ")) + " to close"
              else .run.next end)"' <<<"$result"
  exit 0
fi

# ---------- the sprint ----------
[ -n "$MS" ] || { [ -f "$PLAN" ] && MS="S$(yq -r '.epic.sprint.number' "$PLAN")"; }
[ -n "$MS" ] || { echo "status: no .compasso/plan.yaml - pass --milestone S<n>, or run /compasso:plan" >&2; exit 2; }
rc=0
sync="$("$BIN/tracker.sh" sprint-sync --repo "$REPO" --milestone "$MS" --read-only 2>&1)" || rc=1
[ "$rc" -eq 0 ] || sync_err="$sync"
unapproved=""; [ -f "$PLAN" ] && unapproved="$("$BIN/trust.sh" check --repo "$REPO" --plan 2>/dev/null)"
runs='[]'
if [ -d "$RUNS" ]; then
  for d in "$RUNS"/*/; do
    i="$(basename "$d")"; case "$i" in ''|*[!0-9]*) continue ;; esac
    lab='[]'; [ "$rc" -eq 0 ] && lab="$(jq -c --argjson i "$i" 'if ([.in_review[] | select(.iid == $i)] | length) > 0 then ["compasso::in-review"] else [] end' <<<"$sync")"
    runs="$(jq -c --argjson r "$(stage "$i" "$lab")" '. + [$r]' <<<"$runs")"
  done
fi
result="$(jq -n --arg ms "$MS" --argjson plan "$(plan_on_default)" --arg u "$unapproved" --argjson runs "$runs" \
  --argjson sync "$( [ "$rc" -eq 0 ] && printf '%s' "$sync" || echo null)" --arg err "${sync_err:-}" '{
  milestone: $ms, plan: $plan, unapproved_verify: ($u | split("\n") | map(select(. != ""))), runs: ($runs | sort_by(.iid)),
  tracker: (if $sync then $sync | del(.cleaned) else null end), tracker_error: (if $err == "" then null else $err end)}')"
if [ "$JSON" -eq 1 ]; then printf '%s\n' "$result"; exit "$rc"; fi
jq -r '
  def items: map("#\(.iid) \(.title)") | join(", ");
  "\(.milestone) · status",
  "Plan: \(.plan.state)\(if .plan.state == "no plan" then "" else " (\(.plan.branch), as of the last fetch)" end)",
  (if (.unapproved_verify | length) > 0 then "Verify commands not approved here: \(.unapproved_verify | length) (asked when the story is built)" else empty end),
  (if .tracker_error then "Tracker: \(.tracker_error)" else
    (.tracker |
      (if (.runnable | length) > 0 then "Build now: " + (.runnable | map("#\(.iid) \(.title)" + (if .stack_on then " (stacks on #\(.stack_on))" else "" end)) | join(", ")) else "Build now: nothing" end),
      (if (.building | length) > 0 then "Building: " + (.building | items) else empty end),
      (if (.in_review | length) > 0 then "In review: " + (.in_review | items) else empty end),
      (if (.waiting | length) > 0 then "Waiting: " + (.waiting | map("#\(.iid) on " + (.on | map("#\(.)") | join(", "))) | join("; ")) else empty end),
      (if (.blocked | length) > 0 then "Blocked: " + (.blocked | map("#\(.iid) by " + (.by | map("#\(.iid) \(.title)" + (if (.assignees | length) > 0 then " (@" + (.assignees | join(", @")) + ")" else " (no one assigned)" end)) | join(", "))) | join("; ")) else empty end),
      (if (.human | length) > 0 then "For a person: " + (.human | map("#\(.iid) \(.title)" + (if (.assignees | length) > 0 then " (@" + (.assignees | join(", @")) + ")" else "" end)) | join(", ")) else empty end),
      (if (.features | length) > 0 then "Features: " + (.features | map("#\(.iid) \(.title) \(.stories - .open)/\(.stories) done" + (if .ready_to_verify then ", ready to verify" elif .ready_to_finish then ", ready to finish" else "" end)) | join("; ")) else empty end),
      (if .sprint_done then "The sprint is done: write the test guide (/compasso:sprint)" else empty end))
  end),
  (if (.runs | length) > 0 then "Local runs:", (.runs[] | "  #\(.iid) \(.stage) → \(.next)") else empty end)' <<<"$result"
exit "$rc"
