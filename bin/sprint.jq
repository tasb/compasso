# Classify a sprint's work items. Input (as $vars): $ms, $items (issues with .parsed
# and .parent), $ext ([{iid, state, title}] for dependencies outside the sprint),
# $cleaned, $parallel, $feature (a feature iid, or "" for the whole sprint). Output: what can be built now, what waits and on whom.
# In a team project ($team true) work is assigned by a dev::<name> label, on the item or on its feature;
# $me is the developer asking ("" for the tech lead, who builds nothing): only its own work can be built.
# $devs are the team's developers. A story or bug with no Acceptance (a bug: Expected) or no Verify, or whose
# developer is not in the team, is not ready: nobody builds it or is assigned it until the story is fixed.
# A story whose Touches overlap a story in review waits until that merge request merges.

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
| ($work | map(select(.state == "opened" and (.labels | index("compasso::in-review"))))) as $review
| ($work | map(select(.state == "opened")) | map(
    . + {missing: [(if ((.parsed.acceptance + (if .kind == "bug" then .parsed.expected else [] end)) | length) == 0 then "acceptance" else empty end),
                   (if (.parsed.verify | length) == 0 then "verify" else empty end),
                   (.dev as $d | if $d != null and ($devs | index($d) | not) then "developer" else empty end)]}
    | . as $w
    | ([$w.parsed.blocked_by[] | select(open(.))]) as $blocked
    | ([$w.parsed.depends_on[] | select(open(.))]
       + [$review[] | select(.iid != $w.iid and overlaps(.parsed.touches; $w.parsed.touches)) | .iid] | unique) as $waiting
    | . + {status:
        (if (.labels | index("compasso::in-review")) then "in-review"
         elif $team and (.labels | index("needs::lead")) then "needs-lead"
         elif $team and ((.labels | index("owner::human")) | not) and (.missing | length) > 0 then "not-ready"
         elif ($blocked | length) > 0 then "blocked"
         elif $team and .dev == null then (if (.labels | index("owner::human")) then "human" else "unassigned" end)
         elif $team and $me != "" and .dev != $me then "other"
         elif ($waiting | length) > 0 then "waiting"
         elif ($team | not) and (.labels | index("owner::human")) then "human"
         elif (.labels | index("compasso::building")) then "building"
         else "runnable" end),
        open_blockers: $blocked, open_dependencies: $waiting})) as $open
| ($open | map(select(.status == "runnable")) | sort_by(.iid)) as $runnable
| (reduce (if $team and $me == "" then [] else $runnable end)[] as $r ([];
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
  + (if $team then {team: {
        me: (if $me == "" then null else $me end),
        # the tech lead's queue: questions, work nobody has, and how much each developer holds
        needs_lead: ($open | map(select(.labels | index("needs::lead")) | brief + {kind})),
        not_ready: ($open | map(select(.status == "not-ready") | brief + {kind, missing})),
        # what can start first, and what holds up the most open work, comes first
        unassigned: ([$open[] | .parsed | (.depends_on + .blocked_by)[]] as $deps
          | $open | map(select(.status == "unassigned") | . as $u | brief + {kind}
            + {unblocked: ((.parsed.blocked_by | length) > 0 and (.open_blockers | length) == 0),
               ready: (.open_dependencies | length == 0), holds: ([$deps[] | select(. == $u.iid)] | length)})
          | sort_by([(.ready | not), -.holds, .iid])),
        others: ($open | map(select(.status == "other") | brief)),
        load: ($open | map(select(.dev != null)) | group_by(.dev)
          | map({dev: .[0].dev, open: length, hours: (map(.time_stats.time_estimate // 0) | add / 3600 * 10 | round / 10),
                 backlog: (map(select(.labels | index("compasso::backlog"))) | length),
                 # of those, what could be built now: nothing open ahead of it
                 ready: (map(select((.labels | index("compasso::backlog")) and .status == "runnable")) | length)}))
      }} else {} end)
