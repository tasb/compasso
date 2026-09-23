# Input: {plan: <plan.yaml as JSON>, cfg: {max, target, hpd, weeks, cap}}
# Output: {errors, notes, totals, waves, critical, overlaps}

def blank: . == null or . == "" or . == [];
def ext_ref: type == "string" and test("^#[0-9]+$");
def glob_prefix: sub("[*?\\[].*$"; "");
def hours: (.estimate_h | numbers) // 0;

.plan as $p | .cfg as $c
| ($p.features // []) as $features
| ($p.blockers // []) as $blockers
| [$features[] as $f | ($f.stories // [])[] | . + {feature: $f.key}] as $stories
| ($stories | map({key: .key, value: .}) | from_entries) as $by
| ($stories | map({key: .key, value: [(.depends_on // [])[] | select(ext_ref | not)]}) | from_entries) as $deps
| (($c.weeks * 5 * $c.hpd) / 2) as $feature_max
| ($stories | map(hours) | add // 0) as $epic_total

# ---------- errors ----------
| [
    # epic
    (if ($p.epic.key | blank) then "epic.key is required" else empty end),
    (if ($p.epic.goal | blank) then "epic.goal is required" else empty end),
    (if ($p.epic.sprint.number | type) != "number" or $p.epic.sprint.number < 1 or ($p.epic.sprint.number | floor) != $p.epic.sprint.number
       then "epic.sprint.number must be a positive integer" else empty end),
    (if ($p.epic.sprint.start | blank) or ($p.epic.sprint.end | blank)
       then "epic.sprint needs start and end" else empty end),
    (if ($p.epic.sprint.start | type) == "string" and ($p.epic.sprint.end | type) == "string"
        and ($p.epic.sprint.start >= $p.epic.sprint.end)
       then "epic.sprint.end must be after start" else empty end),
    (if ($features | length) == 0 then "the plan has no features" else empty end),
    (if $epic_total > $c.cap then "epic \($p.epic.key): \($epic_total)h exceeds sprint capacity (\($c.cap)h)" else empty end),

    # unique keys
    ([$p.epic.key, ($features[].key), ($stories[].key), ($blockers[].key)] | map(select(. != null)) | group_by(.)[]
       | select(length > 1) | "key \(.[0]) is used more than once"),

    # coverage overrides
    ([$p.epic, $features[], $stories[]][] | select(.coverage != null)
       | select((.coverage | type) != "number" or .coverage < 0 or .coverage > 100 or (.coverage | floor) != .coverage)
       | "\(.key): coverage must be an integer from 0 to 100"),

    # features
    ($features[] | . as $f
      | (if ($f.key | blank) then "a feature has no key" else empty end),
        (["title", "goal", "scope", "acceptance", "stories"][] as $k
          | select($f[$k] | blank) | "\($f.key): \($k) is required"),
        (($f.stories // []) | map(hours) | add // 0) as $t
        | select($t > $feature_max)
        | "\($f.key): \($t)h exceeds half a sprint (\($feature_max)h)"),

    # stories
    ($stories[] | . as $s
      | (["title", "as", "want", "so_that", "acceptance", "verify", "tests"][] as $k
          | select($s[$k] | blank) | "\($s.key): \($k) is required"),
        (if ($s.estimate_h | type) != "number" or $s.estimate_h <= 0
           then "\($s.key): estimate_h must be a positive number of hours"
         elif $s.estimate_h > $c.max
           then "\($s.key): \($s.estimate_h)h exceeds the \($c.max)h story limit - split it"
         else empty end),
        (if ($s.owner // "") | IN("agent", "human", "either") | not
           then "\($s.key): owner must be agent, human or either" else empty end),
        (if ($s.tests // []) | index("unit") | not then "\($s.key): tests must include unit" else empty end),
        (($s.tests // [])[] | select(IN("unit", "e2e") | not) | "\($s.key): unknown test level '\(.)'"),
        (($s.depends_on // [])[] | select(ext_ref | not) | select($by[.] == null)
          | "\($s.key): depends on unknown story \(.)"),
        (($s.blocked_by // [])[] | select(. as $b | $blockers | map(.key) | index($b) | not)
          | "\($s.key): blocked by unknown blocker \(.)"),
        (($s.depends_on // [])[] | select(. == $s.key) | "\($s.key): depends on itself")),

    # blockers: a task for a person, with the steps that unblock the work
    ($blockers[] | . as $b
      | (["key", "title", "assignee", "steps"][] as $k | select($b[$k] | blank) | "\($b.key // "a blocker"): \($k) is required"),
        (if [$stories[] | (.blocked_by // [])[]] | index($b.key) | not
           then "\($b.key): blocks no story" else empty end))
  ] as $errors

# ---------- waves (Kahn) and cycles ----------
| ({done: [], waves: [], rest: [$stories[].key]}
   | until((.rest | length) == 0 or .stuck;
       .done as $d
       | [.rest[] | select((($deps[.] // []) - $d) | length == 0)] as $ready
       | if ($ready | length) == 0 then .stuck = true
         else .waves += [$ready] | .done += $ready | .rest -= $ready end)) as $k
| (if $k.stuck then ["dependency cycle among: \($k.rest | join(", "))"] else [] end) as $cycle

# ---------- critical path (hours along hard dependencies) ----------
| (reduce ($k.waves | flatten)[] as $s ({};
     . as $acc
     | ([($deps[$s] // [])[] | {k: ., fin: $acc[.].fin}] | max_by(.fin)) as $pred
     | .[$s] = {fin: (($pred.fin // 0) + ($by[$s] | hours)), pred: $pred.k})) as $fin
| (if ($fin | length) == 0 then {hours: 0, path: []}
   else ($fin | to_entries | max_by(.value.fin)) as $end
   | {hours: $end.value.fin,
      path: ([$end.key] | until(($fin[.[0]].pred // null) == null; [$fin[.[0]].pred] + .))}
   end) as $critical

# ---------- soft dependencies: overlapping touches ----------
| [range(0; $stories | length) as $i | range($i + 1; $stories | length) as $j
   | $stories[$i] as $a | $stories[$j] as $b
   | select(any(($a.touches // [])[] | glob_prefix; . as $x
         | any(($b.touches // [])[] | glob_prefix; . as $y | ($y | startswith($x)) or ($x | startswith($y)))))
   | [$a.key, $b.key]] as $overlaps

| {
    errors: ($errors + $cycle),
    notes: [$stories[] | select((.estimate_h | type) == "number" and .estimate_h > $c.target and .estimate_h <= $c.max)
            | "\(.key): \(.estimate_h)h is above the \($c.target)h target"],
    totals: {epic: $epic_total, capacity: $c.cap, feature_max: $feature_max,
             features: [$features[] | {key, hours: ((.stories // []) | map(hours) | add // 0)}]},
    waves: (if $k.stuck then [] else $k.waves end),
    critical: $critical,
    overlaps: $overlaps
  }
