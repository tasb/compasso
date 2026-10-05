# Render one plan item as a tracker description in the approved work-item format, in the project's
# language: run with -L <bin> and --argjson L <bin/locale.sh output>.
include "i18n";
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
def key($k): "**\(md($k)):**";
def coverage_line: if .coverage != null then "\(key("coverage")) \(.coverage)%" else empty end;
def hours: (. | tostring) + "h";

.ctx as $ctx
| .item as $i
| if .kind == "epic" then
    [
      ([ "\(key("goal")) \($i.goal)",
         "\(key("sprint")) \($i.sprint.start) → \($i.sprint.end)",
         "\(key("capacity")) \($ctx.capacity | hours)",
         "\(key("planned")) \($ctx.features | map(.hours) | add // 0 | hours)",
         ($i | coverage_line) ] | join("\\\n")),   # a trailing backslash is a line break in GitLab
      section(md("features"); $ctx.features | map("#\(.iid) \(.title) — \(.hours | hours)") | checks),
      section(md("risks"); ($i.risks // []) | if length > 0 then bullets else "" end),
      ($i | key_line)
    ]
  elif .kind == "blocker" then
    [
      (if ($ctx.needed // []) | length > 0
         then "\(key("needed_for")) " + ($ctx.needed | map("#\(.iid) \(.title)") | join(", ")) else empty end),
      section(md("steps"); $i.steps | to_entries | map("\(.key + 1). \(.value)") | join("\n")),
      ($i | key_line)
    ]
  elif .kind == "feature" then
    [
      ([ "\(key("goal")) \($i.goal)", ($i | coverage_line) ] | join("\\\n")),
      section(md("scope"); $i.scope | bullets),
      section(md("acceptance"); $i.acceptance | checks),
      section(md("decisions"); ($i.decisions // []) | if length > 0 then bullets else "" end),
      ($i | key_line)
    ]
  else
    ([ ($i.depends_on // [])[] | if startswith("#") then . else "#\($ctx.iids[.] // .)" end ]) as $deps
    | [
      "**\(md("as"))** \($i.as) **\(md("i_want"))** \($i.want) **\(md("so_that"))** \($i.so_that).",
      section(md("acceptance"); $i.acceptance | checks),
      section(md("verify"); $i.verify | map("`\(.)`") | bullets),
      ([ "\(key("tests")) \($i.tests | join(", "))",
         (if ($i.touches // []) | length > 0 then "\(key("touches")) \($i.touches | map("`\(.)`") | join(", "))" else empty end),
         (if $ctx.tier == "free" and ($deps | length) > 0 then "\(key("depends_on")) \($deps | join(", "))" else empty end),
         (if ($i.blocked_by // []) | length > 0 then "\(key("blocked_by")) \(($i.blocked_by | map("#\($ctx.iids[.] // .)") | join(", ")))" else empty end),
         ($i | coverage_line) ] | join("\\\n")),
      ($i | key_line)
    ]
  end
| join("\n\n")
