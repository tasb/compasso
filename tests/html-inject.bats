#!/usr/bin/env bats
load helper

setup() {
  T="$BATS_TEST_TMPDIR/t.html"; D="$BATS_TEST_TMPDIR/d.json"; O="$BATS_TEST_TMPDIR/out/p.html"
  printf '<html lang="__LANG__">\n<title>__TITLE__</title>\n<script type="application/json">__DATA__</script>\n</html>\n' > "$T"
}
inj() { "$ROOT/bin/html-inject.sh" --template "$T" --marker __DATA__ --data "$D" --out "$O" "$@"; }
embedded() { sed -n 's#^<script type="application/json">\(.*\)</script>$#\1#p' "$O"; }

@test "a large page (1.4 MB of data, far over the 128 KB Linux allows one argument) is written whole" {
  jq -n '{items: [range(0; 7) | {n: ., text: ("x" * 200000)}]}' > "$D"
  run inj --lang pt-PT --title "Plano"
  [ "$status" -eq 0 ]
  [ "$(embedded | jq -c '[(.items | length), (.items[6].text | length)]')" = '[7,200000]' ]
}

@test "the language and an escaped title are in the HTML itself" {
  echo '{"a": 1}' > "$D"
  inj --lang pt-BR --title 'Shop & <Co> "1"' 
  grep -qx '<html lang="pt-BR">' "$O"
  grep -qx '<title>Shop &amp; &lt;Co&gt; &quot;1&quot;</title>' "$O"
}

@test "no text in the data can end the data block or open a tag" {
  echo '{"a": "</script><script>alert(1)</script><!--"}' > "$D"
  inj --title t
  [ "$(grep -c '<script' "$O")" -eq 1 ]
  [ "$(embedded | jq -r .a)" = '</script><script>alert(1)</script><!--' ]
}

@test "on any failure it exits 1 and leaves the page that was there untouched" {
  mkdir -p "$(dirname "$O")" && echo previous > "$O"
  echo 'not json' > "$D"
  run inj --title t
  [ "$status" -eq 1 ]
  [ "$(cat "$O")" = previous ]
  echo '{"a": 1}' > "$D"
  run inj --title t --lang 'en"><script>'
  [ "$status" -eq 1 ]
  printf 'no marker\n' > "$T"
  run inj --title t
  [ "$status" -eq 1 ]
  [ "$(cat "$O")" = previous ]
}
