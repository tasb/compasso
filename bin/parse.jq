# Parse a Compasso work-item description (the approved formats) back into fields.
# Input: the description as a string. Output:
#   {key, goal, scope, acceptance, decisions, expected, verify, tests, touches, depends_on, blocked_by, coverage}
# depends_on / blocked_by are tracker numbers; coverage is a number or null.
# Section and field names are read in every language Compasso ships: pass --argjson N with
# bin/locale.sh --names; without it, English only.

def names($k): ($ARGS.named.N[$k] // null) as $n | if $n then $n else [{goal: "Goal", scope: "Scope", acceptance: "Acceptance", decisions: "Decisions", expected: "Expected", verify: "Verify", tests: "Tests", touches: "Touches", depends_on: "Depends on", blocked_by: "Blocked by", coverage: "Coverage"}[$k]] end;
def esc: gsub("(?<c>[.*+?^${}()|\\[\\]\\\\])"; "\\\(.c)");
def lines: split("\n") | map(sub("\\\\$"; "") | sub("\\s+$"; ""));
def section($k):      # bullet items under "## <name>" (the name in any language), up to the next heading
  . as $l | (names($k) | map("## " + .)) as $heads
  | ([range(0; $l | length) | select($l[.] as $x | $heads | index($x))][0]) as $start
  | if $start == null then []
    else [ $l[$start + 1:][] ] | (map(startswith("## ")) | index(true)) as $end
         | (if $end == null then . else .[:$end] end)
         | map(select(test("^(- |[0-9]+\\. )")) | sub("^(- (\\[[ xX]\\] )?|[0-9]+\\. )"; ""))
    end;
def field($k):        # value after "**<name>:**" (the name in any language) on any line, up to the next " · **"
  (names($k) | map(esc) | join("|")) as $alt
  | [ .[] | capture("\\*\\*(" + $alt + "):\\*\\* (?<v>.*?)( · \\*\\*.*)?$")? | .v ][0];
def iids: if . == null then [] else [ scan("#([0-9]+)") | .[0] | tonumber ] end;
def list: if . == null then [] else split(",") | map(gsub("^\\s+|\\s+$|`"; "")) | map(select(. != "")) end;

lines as $l
| {
    key: ([ $l[] | capture("<!-- compasso:key=(?<k>[^ ]+) -->")? | .k ][0]),
    goal: ($l | field("goal")),
    scope: ($l | section("scope")),
    acceptance: ($l | section("acceptance")),
    decisions: ($l | section("decisions")),
    expected: ($l | section("expected")),
    verify: ($l | section("verify") | map(gsub("^`|`$"; ""))),
    tests: ($l | field("tests") | list),
    touches: ($l | field("touches") | list),
    depends_on: ($l | field("depends_on") | iids),
    blocked_by: ($l | field("blocked_by") | iids),
    coverage: ($l | field("coverage") | if . == null then null else ([scan("[0-9]+")][0] | if . == null then null else tonumber end) end)
  }
