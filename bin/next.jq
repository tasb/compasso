# The next job for one role, from a tracker snapshot (bin/snapshot.jq), or {job: null}: bin/run.sh
# starts a model only when there is a job. Named arguments:
#   $role   lead | dev        $name   the developer's name (dev)
#   $devs   the developers' names        $queue   ready stories each developer should have waiting
#   $stage  mvp | harden | production        $audited  the lead's machine already audited the code in harden
#   $skip   job keys that failed run.failures times: not run while the person asked about them has not answered
# A job is {job, iids, key} (and mrs, devs where they apply); key names it for the failure count.
#   dev:  rework (its merge request was sent back, or its pipeline failed) > build (a story it was building)
#         > build (its next ready story)
# The next story or feature: bugs first, the most severe first; then the earliest sprint (its milestone's due date;
# none comes last); then the oldest.
#   lead: unblock (a question answered; the runner does it without a model) > red-main (no fix open, or the fix
#         failed: mrs; none while a person is asked) > review (every green merge request but the fix, one job)
#         > in harden: audit (the whole code, once) > in harden and production: drain (the after-MVP list into stories)
#         > deliver (a feature being built with no open story of it, main green) > assign (devs: the developers
#         short of ready stories, fewest first) > plan

def work: .kind == "story" or .kind == "bug";
def ready: work and (.state == "backlog" or .state == null) and (.blocked_by | length) == 0 and (.needs_human | not);   # no state: not started
def keyed($j; $ids): {key: "\($j):\($ids | map(tostring) | join(","))"};
def job($j; $iids): {job: $j, iids: $iids} + keyed($j; $iids);
def job($j; $iids; $extra; $ids): {job: $j, iids: $iids} + $extra + keyed($j; $ids);
def unskipped: select(.key as $k | $ARGS.named.skip | index($k) | not);
def severity: {blocker: 0, major: 1, minor: 2}[[.labels[] | select(startswith("severity::")) | ltrimstr("severity::")][0] // "minor"] // 2;
def in_order: sort_by([(if .kind == "bug" then severity else 9 end), (.sprint.due // "9999-12-31"), .iid]);   # bugs first: fixes keep pace

def dev_job:
  . as $s | ($s.issues | map(select(work and .dev == $ARGS.named.name and (.needs_human | not)))) as $mine
  | ($s.mrs | map(.story)) as $with_mr
  | [ ($s.mrs[] | select((.rework or .pipeline == "failed") and (.story as $i | $mine | any(.iid == $i)))
         | job("rework"; [.story]; {mrs: [.iid]}; [.story])),
      ($mine | map(select(.state == "building" and (.iid as $i | $with_mr | index($i) | not))) | sort_by(.iid)[] | job("build"; [.iid])),
      ($mine | map(select(ready)) | in_order[] | job("build"; [.iid])) ]
  | map(unskipped) | .[0] // {job: null};

def lead_job:
  . as $s
  | ($s.mrs | map(select(.labels | index("compasso::fix-main")))) as $fixes
  | ($s.issues | any(.kind == "ask" and ((.ask_key // "") | startswith("red-main-")))) as $red_asked
  | ($s.issues | map(select(.kind == "ask") | .ask_for)) as $asked
  | ($s.issues | map(select(.needs_human and work and (.iid as $i | $asked | index($i) | not)) | .iid) | sort) as $answered
  | ($s.issues | map(select(.needs_human) | .iid)) as $waiting
  | ($s.mrs | map(select(.pipeline == "success" and (.draft | not) and (.rework | not) and (.labels | index("compasso::fix-main") | not)
                         and (.story as $i | $waiting | index($i) | not)))) as $green
  | ($ARGS.named.devs | map(. as $d | {dev: $d, ready: ($s.issues | map(select(ready and .dev == $d)) | length)})
     | map(select(.ready < $ARGS.named.queue)) | sort_by(.ready) | map(.dev)) as $short
  | ($s.issues | map(select(ready and .dev == null and (.labels | index("owner::human") | not))) | in_order) as $unassigned
  | [ (if ($answered | length) > 0 then job("unblock"; $answered) else empty end),
      (if $s.main.pipeline == "failed" and ($fixes | all(.pipeline == "failed")) and ($red_asked | not)
       then job("red-main"; []; {mrs: ($fixes | map(.iid))}; [$s.main.sha]) else empty end),
      (if ($green | length) > 0 then job("review"; $green | map(.story); {mrs: ($green | map(.iid))}; $green | map(.iid)) else empty end),
      (if $ARGS.named.stage == "harden" and ($ARGS.named.audited | not) then {job: "audit", iids: [], key: "audit"} else empty end),
      (if $ARGS.named.stage == "harden" or $ARGS.named.stage == "production" then ($s.issues | map(select(.kind == "later")) | sort_by(.iid)[] | job("drain"; [.iid])) else empty end),
      (if $s.main.pipeline == "success"
       then ($s.issues | map(select(.kind == "feature" and .state == "building" and (.iid as $f | $s.issues | any(work and .feature == $f) | not)))
             | sort_by(.iid)[] | job("deliver"; [.iid])) else empty end),
      (if ($short | length) > 0 and ($unassigned | length) > 0 then job("assign"; [$unassigned[0].iid]; {devs: $short}; [$unassigned[0].iid]) else empty end),
      (if ($short | length) > 0 and ($unassigned | length) == 0
       then ($s.issues | map(select(.kind == "feature" and .state == "new")) | in_order[0] // empty | job("plan"; [.iid])) else empty end) ]
  | map(unskipped) | .[0] // {job: null};

def next: if $ARGS.named.role == "lead" then lead_job else dev_job end;
