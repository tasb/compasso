# Render one plan item as a GitLab description in the approved work-item format.
# Input: {kind: "epic"|"feature"|"story"|"blocker", item, ctx}
#   ctx.tier       "free" | "premium" (story Depends on lines are Free only)
#   ctx.iids       {"S-1": 12, ...}   plan key -> GitLab iid, for dependencies
#   ctx.capacity   sprint capacity in hours (epic)
#   ctx.features   [{iid, title, hours}] (epic)
#   ctx.needed     [{iid, title}] stories a blocker holds up (blocker)

def bullets: map("- " + .) | join("\n");
def checks: map("- [ ] " + .) | join("\n");
def section($title; $body): if ($body // "") == "" then empty else "## \($title)\n\($body)" end;
def key_line: "<!-- compasso:key=\(.key) -->";
def coverage_line: if .coverage != null then "**Coverage:** \(.coverage)%" else empty end;
def hours: (. | tostring) + "h";

.ctx as $ctx
| .item as $i
| if .kind == "epic" then
    [
      ([ "**Goal:** \($i.goal)",
         "**Sprint:** \($i.sprint.start) → \($i.sprint.end) · **Capacity:** \($ctx.capacity | hours) · **Planned:** \($ctx.features | map(.hours) | add // 0 | hours)",
         ($i | coverage_line) ] | join("\n")),
      section("Features"; $ctx.features | map("#\(.iid) \(.title) — \(.hours | hours)") | checks),
      section("Risks"; ($i.risks // []) | if length > 0 then bullets else "" end),
      ($i | key_line)
    ]
  elif .kind == "blocker" then
    [
      (if ($ctx.needed // []) | length > 0
         then "**Needed for:** " + ($ctx.needed | map("#\(.iid) \(.title)") | join(", ")) else empty end),
      section("Steps"; $i.steps | to_entries | map("\(.key + 1). \(.value)") | join("\n")),
      ($i | key_line)
    ]
  elif .kind == "feature" then
    [
      ([ "**Goal:** \($i.goal)", ($i | coverage_line) ] | join("\n")),
      section("Scope"; $i.scope | bullets),
      section("Acceptance"; $i.acceptance | checks),
      section("Decisions"; ($i.decisions // []) | if length > 0 then bullets else "" end),
      ($i | key_line)
    ]
  else
    ([ ($i.depends_on // [])[] | if startswith("#") then . else "#\($ctx.iids[.] // .)" end ]) as $deps
    | [
      "**As** \($i.as) **I want** \($i.want) **so that** \($i.so_that).",
      section("Acceptance"; $i.acceptance | checks),
      section("Verify"; $i.verify | map("`\(.)`") | bullets),
      ([ "**Tests:** \($i.tests | join(", "))"
         + (if ($i.touches // []) | length > 0 then " · **Touches:** \($i.touches | map("`\(.)`") | join(", "))" else "" end),
         (if $ctx.tier == "free" and ($deps | length) > 0 then "**Depends on:** \($deps | join(", "))" else empty end),
         (if ($i.blocked_by // []) | length > 0 then "**Blocked by:** \(($i.blocked_by | map("#\($ctx.iids[.] // .)") | join(", ")))" else empty end),
         ($i | coverage_line) ] | join("\n")),
      ($i | key_line)
    ]
  end
| join("\n\n")
