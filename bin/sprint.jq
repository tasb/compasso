# Classify a sprint's work items. Input (as $vars): $ms, $items (issues with .parsed
# and .parent), $ext ([{iid, state, title}] for dependencies outside the sprint),
# $cleaned, $parallel, $feature (a feature iid, or "" for the whole sprint). Output: what can be built now, what waits and on whom.

def kind: .labels as $l
  | if ($l | index("type::epic")) then "epic"
    elif ($l | index("type::feature")) then "feature"
    elif ($l | index("type::blocker")) then "blocker"
    elif ($l | index("type::bug")) then "bug"
    elif .issue_type == "task" then "story"
    else "other" end;
def glob_prefix: sub("[*?\\[].*$"; "");
def overlaps($a; $b):
  any(($a // [])[] | glob_prefix; . as $x | any(($b // [])[] | glob_prefix; . as $y
    | ($y | startswith($x)) or ($x | startswith($y))));
def brief: {iid, title};

($items | map(. + {kind: kind})) as $all
| ($all + $ext | map({key: (.iid | tostring), value: .}) | from_entries) as $by
| def open($i): ($by[$i | tostring].state // "opened") == "opened";
  ($all | map(select(.kind == "story" or .kind == "bug"))
    | if $feature == "" then . else map(select(.parent == ($feature | tonumber))) end) as $work
| ($work | map(select(.state == "opened")) | map(
    . as $w
    | ([$w.parsed.blocked_by[] | select(open(.))]) as $blocked
    | ([$w.parsed.depends_on[] | select(open(.))]) as $waiting
    | . + {status:
        (if (.labels | index("compasso::in-review")) then "in-review"
         elif ($blocked | length) > 0 then "blocked"
         elif ($waiting | length) > 0 then "waiting"
         elif (.labels | index("owner::human")) then "human"
         elif (.labels | index("compasso::building")) then "building"
         else "runnable" end),
        open_blockers: $blocked, open_dependencies: $waiting})) as $open
| ($open | map(select(.status == "runnable")) | sort_by(.iid)) as $runnable
| (reduce $runnable[] as $r ([];
     if length < $parallel and all(.[]; overlaps(.parsed.touches; $r.parsed.touches) | not)
     then . + [$r] else . end)) as $batch
| {
    milestone: $ms,
    next_batch: ($batch | map(brief + {kind})),
    runnable: ($runnable | map(brief + {kind})),
    building: ($open | map(select(.status == "building") | brief)),
    in_review: ($open | map(select(.status == "in-review") | brief)),
    human: ($open | map(select(.status == "human") | brief + {assignees: [.assignees[]?.username]})),
    blocked: ($open | map(select(.status == "blocked") | brief + {by: [.open_blockers[] | . as $b
                | {iid: $b, title: $by[$b | tostring].title, assignees: [$by[$b | tostring].assignees[]?.username]}]})),
    waiting: ($open | map(select(.status == "waiting") | brief + {on: .open_dependencies})),
    features: ($all | map(select(.kind == "feature" and ($feature == "" or .iid == ($feature | tonumber)))) | map(. as $f
      | ($work | map(select(.parent == $f.iid))) as $children
      | brief + {
          state: (if .state == "closed" then "closed"
                  else ([.labels[] | select(startswith("compasso::")) | sub("compasso::"; "")][0] // "new") end),
          stories: ($children | length),
          open: ($children | map(select(.state == "opened")) | length),
          ready_to_verify: (.state == "opened" and ($children | length) > 0
            and all($children[]; .state == "closed")
            and ((.labels | index("compasso::verifying")) or (.labels | index("compasso::done")) | not)),
          ready_to_finish: (.state == "opened" and (.labels | index("compasso::verifying") != null)
            and all($children[]; .state == "closed"))})),
    cleaned: $cleaned,
    sprint_done: ($all | map(select(.kind == "feature")) | length > 0 and all(.[]; .state == "closed" or (.labels | index("compasso::done"))))
  }
