# Input: {a: architecture, b: backlog | null, screens: [ids] | null}
def blank: . == null or . == "" or . == [];
.a as $a | .b as $b | .screens as $screens
| ([$a.components[]?.name]) as $names
| ([$b.features[]? | select(.mvp == true) | .key]) as $mvp
| ([$a.components[]?.features[]?] | unique) as $served
| [
    (if ($a.summary | blank) then "summary is empty" else empty end),
    (if ($a.stack | blank) then "stack is empty" else ($a.stack[] | select((.layer | blank) or (.choice | blank) or (.why | blank)) | "stack: every layer needs a choice and why") end),
    (if ($a.components | blank) then "components is empty" else empty end),
    ($a.components[]? | select((.name | blank) or (.responsibility | blank)) | "every component needs a name and a responsibility"),
    ($names | group_by(.)[] | select(length > 1) | "component \(.[0]) is named twice"),
    ($a.components[]? | .name as $n | (.talks_to // [])[] | select(. as $t | $names | index($t) | not) | "\($n) talks to \(.), which is not a component"),
    (if $b then ($a.components[]? | .name as $n | (.features // [])[] | select(. as $f | [$b.features[].key] | index($f) | not) | "\($n) serves \(.), which is not in the backlog") else empty end),
    ($mvp[] | select(. as $f | $served | index($f) | not) | "MVP feature \(.) is served by no component"),
    (if ($a.observability.metrics | blank) then "observability.metrics is empty" else empty end),
    (if ($a.observability.alerts | blank) then "observability.alerts is empty" else empty end),
    (if $screens then ($a.observability.dashboards[]? | select((.screen // "") != "" and (.screen as $s | $screens | index($s) | not)) | "dashboard \(.name) cites screen \(.screen), which is not in the prototype inventory") else empty end),
    (if ($a.security | blank) then "security is empty: security's review fills it" else empty end),
    (if ([$a.data[]? | select(.personal == true)] | length) > 0 and ([$a.security[]? | select(.concern | test("personal|privacy|GDPR|RGPD"; "i"))] | length) == 0
     then "personal data is stored but no security control covers it" else empty end),
    (if ($a.deployment.environments | blank) then "deployment.environments is empty" else empty end),
    (if ($a.decisions | blank) then "decisions is empty" else ($a.decisions[] | select((.title | blank) or (.choice | blank) or (.why | blank)) | "every decision needs a title, a choice and why") end)
  ] as $errors
| {errors: $errors,
   notes: ([$a.decisions[]? | select(.alternatives | blank) | "decision \"\(.title)\" names no alternative"]
           + [$b.features[]? | select(.mvp != true) | .key as $f | select($served | index($f) | not) | "\($f) (after the MVP) is served by no component yet"])}
