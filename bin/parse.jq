# Parse a Compasso work-item description (the approved formats) back into fields.
# Input: the description as a string. Output:
#   {key, acceptance, verify, tests, touches, depends_on, blocked_by, coverage}
# depends_on / blocked_by are GitLab iids (numbers); coverage is a number or null.

def lines: split("\n") | map(sub("\\\\$"; "") | sub("\\s+$"; ""));
def section($name):   # bullet items under "## <name>", up to the next heading
  . as $l
  | ([range(0; $l | length) | select($l[.] == "## " + $name)][0]) as $start
  | if $start == null then []
    else [ $l[$start + 1:][] ] | (map(startswith("## ")) | index(true)) as $end
         | (if $end == null then . else .[:$end] end)
         | map(select(test("^(- |[0-9]+\\. )")) | sub("^(- (\\[[ xX]\\] )?|[0-9]+\\. )"; ""))
    end;
def field($name):     # value after "**<name>:**" on any line, up to the next " · **"
  [ .[] | capture("\\*\\*" + $name + ":\\*\\* (?<v>.*?)( · \\*\\*.*)?$")? | .v ][0];
def iids: if . == null then [] else [ scan("#([0-9]+)") | .[0] | tonumber ] end;
def list: if . == null then [] else split(",") | map(gsub("^\\s+|\\s+$|`"; "")) | map(select(. != "")) end;

lines as $l
| {
    key: ([ $l[] | capture("<!-- compasso:key=(?<k>[^ ]+) -->")? | .k ][0]),
    acceptance: ($l | section("Acceptance")),
    verify: ($l | section("Verify") | map(gsub("^`|`$"; ""))),
    tests: ($l | field("Tests") | list),
    touches: ($l | field("Touches") | list),
    depends_on: ($l | field("Depends on") | iids),
    blocked_by: ($l | field("Blocked by") | iids),
    coverage: ($l | field("Coverage") | if . == null then null else ([scan("[0-9]+")][0] | if . == null then null else tonumber end) end)
  }
