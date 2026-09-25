# Input: {b: backlog, r: roadmap | null, cap, start, mode: "propose" | "check"}
.b as $b | .cap as $cap | .start as $start | (.r // {sprints: []}) as $old
| ($b.features // []) as $fs
| ($fs | map({key: .key, value: .}) | from_entries) as $by
# features already in kept sprints (numbered before $start) stay where they are
| ([$old.sprints[] | select(.number < $start)]) as $kept
| ([$kept[].features[]]) as $placed_before
| def topo($keys): {done: [], out: [], rest: $keys}
    | until((.rest | length) == 0 or .stuck;
        .done as $d
        | [.rest[] | select(((($by[.].depends_on // []) | map(select(. as $x | $keys | index($x)))) - $d) | length == 0)] as $r
        | if ($r | length) == 0 then .stuck = true else .out += $r | .done += $r | .rest -= $r end)
    | .out + .rest;
  def place($keys; $floor):
    reduce $keys[] as $k (.;
      . as $st | ($by[$k]) as $f
      | ([($f.depends_on // [])[] | $st.at[.] // -1] | max // -1) as $earliest
      | ([$earliest, $floor, 0] | max) as $from
      | ([.sprints | to_entries[] | select(.key >= $from and (.value.hours + $f.size_h) <= $cap) | .key][0]) as $i
      | (if $i == null then ([(.sprints | length), $from] | max) else $i end) as $i
      | until((.sprints | length) > $i; .sprints += [{features: [], hours: 0}])
      | .sprints[$i].features += [$k] | .sprints[$i].hours += $f.size_h | .at[$k] = $i);
  # MVP features first; the rest only after the MVP line, so they never delay the MVP
  def propose:
    ([$fs[] | select(.key as $k | $placed_before | index($k) | not)]) as $todo
    | {sprints: [], at: {}}
    | place(topo([$todo[] | select(.mvp == true) | .key]); 0)
    | place(topo([$todo[] | select(.mvp != true) | .key]); (.sprints | length))
    | .sprints | to_entries
    | map(.key as $i | .value as $s
          | ($start + $i) as $n
          | ([$old.sprints[] | select(.number == $n and .features == $s.features) | .goal][0] // "") as $goal
          | {number: $n, goal: $goal, features: $s.features, hours: $s.hours})
    | ($kept + .) as $all
    | {capacity_h: $cap, sprints: $all,
       mvp_sprint: ([$all[] | select(any(.features[]; $by[.].mvp == true)) | .number] | max // $start)};
  def check($r):
    ([$r.sprints[] | .number as $n | .features[] | {k: ., n: $n}]) as $at
    | ($at | map({key: .k, value: .n}) | from_entries) as $sprint_of
    | [
        ($at | group_by(.k) | map(select(length > 1) | "\(.[0].k) is in more than one sprint")[]),
        ($at[] | select($by[.k] == null) | "sprint \(.n): \(.k) is not in the backlog"),
        ($r.sprints[] | select(.hours > $r.capacity_h) | "sprint \(.number): \(.hours)h is more than the capacity (\($r.capacity_h)h)"),
        ($r.sprints[] | . as $s | select(([.features[] | $by[.].size_h // 0] | add // 0) != $s.hours) | "sprint \(.number): hours say \(.hours)h but its features add up to \([.features[] | $by[.].size_h // 0] | add // 0)h"),
        ($r.sprints[] | select((.goal // "") == "") | "sprint \(.number) has no goal"),
        ($at[] | . as $a | ($by[$a.k].depends_on // [])[] | select($sprint_of[.] != null and $sprint_of[.] > $a.n) | "\($a.k) (sprint \($a.n)) depends on \(.), planned later (sprint \($sprint_of[.]))"),
        ($at[] | select($by[.k].mvp == true and .n > $r.mvp_sprint) | "\(.k) is in the MVP but planned after the MVP sprint (\($r.mvp_sprint))")
      ] as $errors
    | {errors: $errors,
       notes: [$fs[] | select(.key as $k | $sprint_of[$k] == null) | "\(.key) \(.title) is in no sprint"]};
  if .mode == "propose" then propose else check(.r) end
