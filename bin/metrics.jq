# Build the sprint report's data. Input ($vars): $sprint {number, goal, start, end,
# capacity_h, status}, $today (YYYY-MM-DD), $now (ISO), $items (issues in the
# milestone, each with .label_events), $sync (sprint-sync output), $history
# ([{sprint, done_h}] for past sprints), $files (story metrics files), $results
# (testers' results files), $prices ({model: price per million tokens}), $currency.

def ts: if . == null then null else sub("\\.[0-9]+"; "") | sub("\\+00:00$"; "Z") | fromdateiso8601 end;
def hours($a; $b): (($b - $a) / 3600);
def r1: (. * 10 | round) / 10;
def kind: .labels as $l
  | if ($l | index("type::epic")) then "epic" elif ($l | index("type::feature")) then "feature"
    elif ($l | index("type::blocker")) then "blocker" elif ($l | index("type::bug")) then "bug"
    elif .issue_type == "task" then "story" else "other" end;
def est: ((.time_stats.time_estimate // 0) / 3600);
def first_add($label): [.label_events[]? | select(.action == "add" and .label.name == $label) | .created_at | ts] | min;

($now | ts) as $nowts
| ($items | map(. + {kind: kind})) as $all
| ($all | map({key: (.iid | tostring), value: .}) | from_entries) as $by
| ($all | map(select(.kind == "story" or .kind == "bug"))) as $work
| ($work | map(est) | add // 0) as $planned
| ($work | map(select(.state == "closed")) | map(est) | add // 0) as $done
| ([$sprint.start, (if $today < $sprint.end then $today else $sprint.end end)]) as [$from, $to]
| ([range(($from + "T00:00:00Z" | ts); ($to + "T00:00:00Z" | ts) + 1; 86400)] | map(todate[0:10])) as $days
| ($files | map({key: (.iid | tostring), value: .}) | from_entries) as $fby
| [$files[].agents[]?] as $runs
| def cost($a): if ($prices[$a.model] | type) == "number" and ($a.tokens | type) == "number"
                then $a.tokens / 1e6 * $prices[$a.model] else null end;
{
  sprint: ($sprint + {generated: $today}),
  delivery: {
    planned_h: ($planned | r1), done_h: ($done | r1),
    stories_total: ($work | length), stories_done: ($work | map(select(.state == "closed")) | length),
    stories_blocked: ($sync.blocked | length),
    burndown: [$days[] as $d | {date: $d, remaining_h: (($planned - ($work
       | map(select(.state == "closed" and (.closed_at // "")[0:10] <= $d)) | map(est) | add // 0)) | r1)}],
    velocity: ($history + [{sprint: "S\($sprint.number)", done_h: ($done | r1)}]),
    blockers: [$all[] | select(.kind == "blocker") | {
      title, owner: ([.assignees[]?.username] | join(", ")),
      open_days: (hours(.created_at | ts; (.closed_at | ts) // $nowts) / 24 | floor),
      state: (if .state == "closed" then "resolved" else "open" end)}],
    open: [$work[] | select(.state == "opened") | . as $w | {
      title, estimate_h: (est | r1),
      waiting_on: (
        ([$sync.blocked[] | select(.iid == $w.iid) | .by[] | "blocker: \(.title)"] | first)
        // ([$sync.waiting[] | select(.iid == $w.iid) | .on[] | "#\(.) \($by[tostring].title // "")"] | first)
        // (if ([$sync.human[] | select(.iid == $w.iid)] | length) > 0 then "a person (owner::human)" else null end)
        // (if ([$sync.in_review[] | select(.iid == $w.iid)] | length) > 0 then "approval of its merge request" else null end)
        // (if ([$sync.building[] | select(.iid == $w.iid)] | length) > 0 then "being built" else null end)
        // "nothing - ready to build")}]
  },
  flow: {stories: [$work[] | select(first_add("compasso::building") != null) | . as $w
    | first_add("compasso::building") as $b | first_add("compasso::in-review") as $r
    | ((.closed_at | ts) // $nowts) as $end
    | {title, merged: (.state == "closed"),
       building_h: (hours($b; ($r // $end)) | r1),
       waiting_h: (if $r then hours($r; $end) | r1 else 0 end)}]},
  quality: {
    findings: (["reviewer", "security"] | map({key: ., value: (. as $s | {
      blocker: ([$files[].findings[$s].blocker] | add // 0),
      major: ([$files[].findings[$s].major] | add // 0),
      minor: ([$files[].findings[$s].minor] | add // 0)})}) | from_entries),
    security_open: ([$files[].security_open] | add // 0),
    review_rounds_avg: (if ($files | length) == 0 then null else ([$files[].review_rounds] | add / length | r1) end),
    bugs: {
      testers: ([$all[] | select(.kind == "bug" and ((.description // "") | test("business test")))] | length),
      feature_e2e: ([$all[] | select(.kind == "bug" and ((.description // "") | test("business test") | not))] | length)},
    test_guide: (if ($results | length) == 0 then null else
      ([$results[].results[]] | {pass: map(select(.status == "pass")) | length, fail: map(select(.status == "fail")) | length,
        blocked: map(select(.status == "blocked")) | length, not_tested: map(select(.status == "not-tested")) | length}) end),
    coverage_avg: ([$files[].coverage | select(. != null and .percent != null) | .percent] as $c
      | if ($c | length) == 0 then null else ($c | add / length | round) end)
  },
  agents: {
    by_role: ($runs | group_by(.role) | map({
      role: .[0].role, model: (map(.model) | group_by(.) | max_by(length) | .[0]), runs: length,
      tokens: (map(.tokens // 0) | add), minutes: ((map(.ms // 0) | add) / 60000 | r1)})),
    stories: [$files[] | select((.agents | length) > 0) | {
      title, estimate_h: ((.estimate_h // 0) | r1),
      agent_minutes: (([.agents[].ms // 0] | add) / 60000 | r1),
      tokens: ([.agents[].tokens // 0] | add),
      cost: ([.agents[] | cost(.)] | if ($prices | length) == 0 or any(. == null) then null else add end)}],
    cost: (if ($prices | length) == 0 then null else {currency: $currency,
      total: ([$runs[] | cost(.) // 0] | add // 0)} end)
  }
}
