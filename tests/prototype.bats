#!/usr/bin/env bats
load helper

setup() { setup_repo; }
p() { "$ROOT/bin/prototype.sh" "$@"; }
INV() { echo "$BATS_TEST_TMPDIR/prototype.json"; }

@test "inventory: one screen per page, ids from the path, hash routes kept, links between screens" {
  run p inventory --raw "$ROOT/tests/fixtures/prototype/raw.json" --url https://proto.example/ --out "$(INV)"
  [ "$status" -eq 0 ]
  [[ "$output" == *"3 screen(s)"* ]] || false
  [ "$(jq -c '[.screens[].id]' "$(INV)")" = '["home","catalog","cart"]' ]
  [ "$(jq -c '.screens[0] | [.name, .links_to, .actions]' "$(INV)")" = '["Shop",["cart","catalog"],["Sign up"]]' ]
  [ "$(jq -c '.screens[1] | [.name, .actions, .forms[0].fields[0].label, .forms[0].submit]' "$(INV)")" = '["catalog",["Add to cart"],"Search","Go"]' ]
  [ "$(jq -c '.unreached' "$(INV)")" = '[{"url":"https://proto.example/broken","error":"net::ERR_ABORTED"}]' ]
  run p check --file "$(INV)"
  [ "$status" -eq 0 ]
}

@test "check: an inventory written from code or Figma must be well formed" {
  echo '{"source": "figma", "where": "f", "screens": [{"id": "Cart Page", "name": ""}, {"id": "home", "name": "Home", "links_to": ["pay"]}], "flows": [{"name": "buy", "steps": ["home", "gone"]}]}' > "$(INV)"
  run p check --file "$(INV)"
  [ "$status" -eq 1 ]
  [[ "$output" == *"screen id Cart Page must be lowercase"* ]] || false
  [[ "$output" == *"screen Cart Page has no name"* ]] || false
  [[ "$output" == *"screen home links to unknown screen pay"* ]] || false
  [[ "$output" == *"flow buy goes through unknown screen gone"* ]] || false
  echo '{"source": "sketch", "screens": []}' > "$(INV)"
  run p check --file "$(INV)"
  [[ "$output" == *"source must be url, code or figma"* ]] || false
  [[ "$output" == *"screens must be a non-empty list"* ]] || false
}

@test "crawl: needs an http URL and Docker; runs the crawler in the Playwright image" {
  run p crawl --repo "$REPO" --url proto.example --out "$BATS_TEST_TMPDIR/c"
  [ "$status" -eq 2 ]
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/usr/bin/env bash\n[ "$1" = info ] && exit 0\necho "$@" > "%s/docker.args"\ncp "%s" "%s/c/raw.json"\n' \
    "$BATS_TEST_TMPDIR" "$ROOT/tests/fixtures/prototype/raw.json" "$BATS_TEST_TMPDIR" > "$BATS_TEST_TMPDIR/bin/docker"
  chmod +x "$BATS_TEST_TMPDIR/bin/docker"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run p crawl --repo "$REPO" --url http://localhost:5173/ --out "$BATS_TEST_TMPDIR/c" --max 5
  [ "$status" -eq 0 ]
  [[ "$output" == *"crawled 4 page(s)"* ]] || false
  grep -q "mcr.microsoft.com/playwright:v1.55.0-noble" "$BATS_TEST_TMPDIR/docker.args"
  grep -q "npm i --silent playwright@1.55.0" "$BATS_TEST_TMPDIR/docker.args"
  grep -q "http://host.docker.internal:5173/ 5" "$BATS_TEST_TMPDIR/docker.args"
  cmp -s "$ROOT/bin/prototype-crawl.mjs" "$BATS_TEST_TMPDIR/c/crawl.mjs"
}

@test "crawl: without Docker it says so" {
  mkdir -p "$BATS_TEST_TMPDIR/bin"; printf '#!/usr/bin/env bash\nexit 1\n' > "$BATS_TEST_TMPDIR/bin/docker"; chmod +x "$BATS_TEST_TMPDIR/bin/docker"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run p crawl --repo "$REPO" --url https://proto.example/ --out "$BATS_TEST_TMPDIR/c"
  [ "$status" -eq 1 ]
  [[ "$output" == *"needs Docker running"* ]] || false
}

@test "inventory: file extensions and index pages make plain ids; pages of one template are one screen" {
  jq -n '[{url: "https://p.example/index.html", title: "Home", links: [{href: "https://p.example/item.html?id=1"}]},
          {url: "https://p.example/signup.html", title: "Sign up"},
          {url: "https://p.example/item.html?id=1", title: "Red shoe"},
          {url: "https://p.example/item.html?id=2", title: "Blue shoe"}]' > "$BATS_TEST_TMPDIR/raw.json"
  p inventory --raw "$BATS_TEST_TMPDIR/raw.json" --url https://p.example/ --out "$(INV)" >/dev/null
  [ "$(jq -c '[.screens[] | [.id, .pages, .name]]' "$(INV)")" = '[["home",1,"Home"],["signup",1,"Sign up"],["item",2,"Red shoe"]]' ]
  [ "$(jq -c '.screens[0].links_to' "$(INV)")" = '["item"]' ]
  p check --file "$(INV)" >/dev/null
}
