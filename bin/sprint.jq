# Classify a sprint's work items. Input (as $vars): $ms, $items (issues with .parsed
# and .parent), $ext ([{iid, state, title}] for dependencies outside the sprint),
# $cleaned, $parallel, $feature (a feature iid, or "" for the whole sprint). Output: what can be built now, what waits and on whom.
# In a team project ($team true) work is assigned by a dev::<name> label, on the item or on its feature;
# $me is the developer asking ("" for the tech lead, who builds nothing): only its own work can be built.

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
def own_dev: [.labels[]? | select(startswith("dev::")) | sub("dev::"; "")][0] // null;
def brief: {iid, title} + (if $team then {dev} else {} end);

# $items and $ext come with --slurpfile: a sprint's items and their descriptions can pass the 128 KB
# Linux allows one argument, so they never travel as arguments
$items[0] as $items | $ext[0] as $ext
| ($items | map(. + {kind: kind})) as $all0
| ($all0 + $ext | map({key: (.iid | tostring), value: .}) | from_entries) as $by
# a feature's developer covers its stories and bugs; an item's own label wins
| ($all0 | map(. + {dev: (own_dev // (if .parent then ($by[.parent | tostring] // {} | own_dev) else null end))})) as $all
| def open($i): ($by[$i | tostring].state // "opened") == "opened";
  ($all | map(select(.kind == "story" or .kind == "bug"))
    | if $feature == "" then . else map(select(.parent == ($feature | tonumber))) end) as $work
| ($work | map(select(.state == "opened")) | map(
    . as $w
    | ([$w.parsed.blocked_by[] | select(open(.))]) as $blocked
    | ([$w.parsed.depends_on[] | select(open(.))]) as $waiting
    | . + {status:
        (if (.labels | index("compasso::in-review")) then "in-review"
         elif $team and (.labels | index("needs::lead")) then "needs-lead"
         elif ($blocked | length) > 0 then "blocked"
         elif $team and .dev == null then "unassigned"
         elif $team and $me != "" and .dev != $me then "other"
         elif ($waiting | length) == 1 and (($by[$waiting[0] | tostring].labels // []) | index("compasso::in-review"))
              and ((.labels | index("owner::human")) | not) and ((.labels | index("compasso::building")) | not) then "stackable"
         elif ($waiting | length) > 0 then "waiting"
         elif ($team | not) and (.labels | index("owner::human")) then "human"
         elif (.labels | index("compasso::building")) then "building"
         else "runnable" end),
        open_blockers: $blocked, open_dependencies: $waiting})) as $open
| ($open | map(select(.status == "runnable" or .status == "stackable")) | sort_by(.iid)) as $runnable
| (reduce (if $team and $me == "" then [] else $runnable end)[] as $r ([];
     if length < $parallel and all(.[]; overlaps(.parsed.touches; $r.parsed.touches) | not)
     then . + [$r] else . end)) as $batch
| {
    milestone: $ms,
    # a stackable story starts from the branch of the one story it waits on, whose merge request is open
    next_batch: ($batch | map(brief + {kind} + (if .status == "stackable" then {stack_on: .open_dependencies[0]} else {} end))),
    runnable: ($runnable | map(brief + {kind} + (if .status == "stackable" then {stack_on: .open_dependencies[0]} else {} end))),
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
  + (if $team then {team: {
        me: (if $me == "" then null else $me end),
        # the tech lead's queue: questions, work nobody has, and how much each developer holds
        needs_lead: ($open | map(select(.labels | index("needs::lead")) | brief + {kind})),
        unassigned: ($open | map(select(.status == "unassigned") | brief + {kind}
          + {unblocked: ((.parsed.blocked_by | length) > 0 and (.open_blockers | length) == 0)})),
        others: ($open | map(select(.status == "other") | brief)),
        load: ($open | map(select(.dev != null)) | group_by(.dev)
          | map({dev: .[0].dev, open: length, hours: (map(.time_stats.time_estimate // 0) | add / 3600 * 10 | round / 10),
                 backlog: (map(select(.labels | index("compasso::backlog"))) | length)}))
      }} else {} end)
