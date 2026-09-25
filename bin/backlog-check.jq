# Input: {b: backlog, c: {weeks, hpd, cap}, screens: [screen ids] | null}
def blank: . == null or . == "" or . == [];
.b as $b | .c as $c | .screens as $screens
| (($c.weeks * 5 * $c.hpd) / 2) as $fmax
| ($b.features // []) as $fs
| ([$fs[].key]) as $keys
| ($fs | map({key: .key, value: (.depends_on // [])}) | from_entries) as $deps
| ($fs | map({key: .key, value: (.mvp == true)}) | from_entries) as $mvp
| [
    (if ($b.product.name | blank) then "product.name is empty" else empty end),
    (if ($fs | length) == 0 then "the backlog has no features" else empty end),
    ($keys | group_by(.) | map(select(length > 1) | "feature key \(.[0]) is used \(length) times")[]),
    ($fs[] | . as $f
      | (if ($f.key | type) != "string" or ($f.key | test("^F-[0-9]+$") | not) then "feature key \($f.key) must look like F-<n>" else empty end),
        (if ($f.title | blank) then "\($f.key): title is empty" else empty end),
        (if ($f.goal | blank) then "\($f.key): goal is empty" else empty end),
        (if ($f.acceptance | blank) then "\($f.key): needs at least one acceptance line" else empty end),
        (if ($f.size_h | type) != "number" or $f.size_h <= 0 then "\($f.key): size_h must be a number of hours above 0"
         elif $f.size_h > $fmax then "\($f.key): \($f.size_h)h is more than half a sprint (\($fmax)h) - split it" else empty end),
        (if ($f.mvp | type) != "boolean" then "\($f.key): mvp must be true or false" else empty end),
        (($f.depends_on // [])[] | . as $d
          | if ($keys | index($d)) == null then "\($f.key): depends on \($d), which is not in the backlog"
            elif $f.mvp == true and $mvp[$d] != true then "\($f.key) is in the MVP but depends on \($d), which is not"
            else empty end))
  ] as $errors
| ({done: [], waves: [], rest: $keys}
   | until((.rest | length) == 0 or .stuck;
       .done as $d
       | [.rest[] | select((($deps[.] // []) - $d) | length == 0)] as $ready
       | if ($ready | length) == 0 then .stuck = true
         else .waves += [$ready] | .done += $ready | .rest -= $ready end)) as $k
| (if $k.stuck then ["dependency cycle among: \($k.rest | join(", "))"] else [] end) as $cycle
| ([$fs[] | select(.mvp == true) | .size_h | numbers] | add // 0) as $mvp_h
| ([$fs[].size_h | numbers] | add // 0) as $all_h
| ([$fs[] | (.sources // [])[] | strings | select(startswith("screen: ")) | sub("^screen: "; "")] | unique) as $used
| {
    errors: ($errors + $cycle),
    notes: (
      [$fs[] | select(.sensitive == true) | "\(.key) is sensitive: security writes its abuse cases when it is planned"]
      + (if $screens then [$screens[] | select(. as $s | $used | index($s) | not) | "prototype screen \(.) is in no feature"] else [] end)
      + [$used[] | select(. as $u | ($screens // []) | index($u) | not) | select($screens != null) | "a feature cites screen \(.), which is not in the prototype inventory"]),
    totals: {features: ($fs | length), mvp_features: ([$fs[] | select(.mvp == true)] | length),
             mvp_hours: $mvp_h, all_hours: $all_h, feature_max: $fmax, capacity: $c.cap,
             mvp_sprints: (if $c.cap > 0 then (($mvp_h / $c.cap) | ceil) else null end)},
    order: ($k.waves | flatten)
  }
