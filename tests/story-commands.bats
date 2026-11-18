#!/usr/bin/env bats
load helper

setup() {
  setup_repo
  export FAKE_GL="$BATS_TEST_TMPDIR/gl"; mkdir -p "$FAKE_GL/issues" "$FAKE_GL/parent"; : > "$FAKE_GL/calls.log"
  export PATH="$ROOT/tests/fake:$PATH"
  # feature #6 (coverage 85), story #8 under it in milestone S20, epic #12 (coverage 70)
  issue 6 issue "Invoice history" opened $'**Goal:** g\\\n**Coverage:** 85%\n\n<!-- compasso:key=F-1 -->'
  issue 8 task "Invoice list API" opened "$(cat <<'EOF'
**As** a customer **I want** a list **so that** I see history.

## Acceptance
- [ ] Given 3 invoices, When GET /invoices, Then 3 items

## Verify
- `npm test -- billing`

**Tests:** unit, e2e · **Touches:** `src/billing/**`

<!-- compasso:key=S-1 -->
EOF
)"
  echo 1006 > "$FAKE_GL/parent/1008"
  jq -n '[{iid: 12, description: "**Goal:** g\\\n**Coverage:** 70%"}]' > "$FAKE_GL/epic-query.json"
}
issue() { # iid type title state description
  jq -n --argjson iid "$1" --arg t "$2" --arg title "$3" --arg s "$4" --arg d "$5" \
    '{iid: $iid, id: (1000 + $iid), issue_type: $t, title: $title, state: $s, description: $d, labels: [], milestone: {id: 501, title: "S20"}}' \
    > "$FAKE_GL/issues/$1.json"
}
gl() { "$ROOT/bin/tracker/gitlab.sh" "$@" --repo "$REPO"; }
calls() { grep -c -- "$1" "$FAKE_GL/calls.log" || true; }

# ---------- story ----------

@test "story: parses the description and names the feature and epic" {
  run gl story --iid 8
  [ "$status" -eq 0 ]
  [ "$(jq -c '[.feature, .epic]' <<<"$output")" = "[6,12]" ]
  [ "$(jq -r '.story.verify[0]' <<<"$output")" = "npm test -- billing" ]
  [ "$(jq -c '.story.tests' <<<"$output")" = '["unit","e2e"]' ]
  [ "$(jq -r '.story.key' <<<"$output")" = "S-1" ]
}

@test "story: coverage comes from the story, else the feature, else the epic, else the project" {
  [ "$(gl story --iid 8 | jq .coverage_min)" = 85 ]
  issue 6 issue "Invoice history" opened '**Goal:** g'
  [ "$(gl story --iid 8 | jq .coverage_min)" = 70 ]
  echo '[{"iid": 12, "description": "**Goal:** g"}]' > "$FAKE_GL/epic-query.json"
  [ "$(gl story --iid 8 | jq .coverage_min)" = 80 ]
  issue 8 task "t" opened $'**Tests:** unit\n**Coverage:** 95%'
  [ "$(gl story --iid 8 | jq .coverage_min)" = 95 ]
}

@test "story: open dependencies and blockers are listed; closed ones are not" {
  issue 8 task "t" opened $'**Tests:** unit\n**Depends on:** #3, #4\n**Blocked by:** #13'
  issue 3 task "done dep" closed ""
  issue 4 task "open dep" opened ""
  issue 13 task "credentials" opened ""
  run gl story --iid 8
  [ "$(jq -c '.open_dependencies | map([.iid, .kind])' <<<"$output")" = '[[4,"depends_on"],[13,"blocked_by"]]' ]
}

@test "story: a missing dependency or story is an error" {
  issue 8 task "t" opened '**Depends on:** #77'
  run gl story --iid 8
  [ "$status" -eq 1 ]
  [[ "$output" == *"#77 referenced by #8 does not exist"* ]] || false
  run gl story --iid 99
  [ "$status" -eq 1 ]
}

@test "story: needs --iid" {
  run gl story
  [ "$status" -eq 1 ]
  [[ "$output" == *"story needs --iid"* ]] || false
}

# ---------- set-state ----------

@test "set-state: adds the new state and removes every other compasso state" {
  run gl set-state --iid 8 --state in-review
  [ "$status" -eq 0 ]
  grep -q "PUT projects/acme%2Fapp/issues/8 add_labels=compasso::in-review remove_labels=compasso::new,compasso::backlog,compasso::building,compasso::verifying,compasso::done" "$FAKE_GL/calls.log"
}

@test "set-state: an unknown state is refused" {
  run gl set-state --iid 8 --state shipped
  [ "$status" -eq 1 ]
  [ "$(calls 'PUT')" -eq 0 ]
}

# ---------- open-mr ----------

@test "open-mr: creates the merge request from the branch to the default branch" {
  echo "Closes #8" > "$BATS_TEST_TMPDIR/body.md"
  run gl open-mr --iid 8 --branch story/8-invoice-list --body-file "$BATS_TEST_TMPDIR/body.md"
  [ "$status" -eq 0 ]
  [ "$(jq -r .iid <<<"$output")" = 31 ]
  grep -q "POST projects/acme%2Fapp/merge_requests source_branch=story/8-invoice-list target_branch=main title=Invoice list API remove_source_branch=true" "$FAKE_GL/calls.log"
}

@test "open-mr: updates the open merge request of the branch instead of opening another" {
  echo '[{"iid": 40}]' > "$FAKE_GL/mr-query.json"
  echo "Closes #8" > "$BATS_TEST_TMPDIR/body.md"
  run gl open-mr --iid 8 --branch story/8-invoice-list --body-file "$BATS_TEST_TMPDIR/body.md"
  [ "$status" -eq 0 ]
  [ "$(jq -r .iid <<<"$output")" = 40 ]
  [ "$(calls 'POST projects/acme%2Fapp/merge_requests')" -eq 0 ]
}

# ---------- followup ----------

# ---------- merge ----------

findings() { echo "$1" > "$BATS_TEST_TMPDIR/findings.json"; }

@test "mr-checks: the pipeline of the last commit and whether it conflicts with its target" {
  for p in 'success:success' 'failed:failed' 'canceled:failed' 'running:running' 'pending:running' 'created:running'; do
    echo "{\"iid\":31,\"has_conflicts\":false,\"head_pipeline\":{\"status\":\"${p%%:*}\"}}" > "$FAKE_GL/mr-31.json"
    [ "$(gl mr-checks --mr 31 | jq -c .)" = "{\"pipeline\":\"${p#*:}\",\"conflicts\":false}" ]
  done
  echo '{"iid":31,"has_conflicts":true,"head_pipeline":null}' > "$FAKE_GL/mr-31.json"
  [ "$(gl mr-checks --mr 31 | jq -c .)" = '{"pipeline":"none","conflicts":true}' ]
  run gl mr-checks --mr 32
  [ "$status" -eq 1 ]
}

@test "main-pipeline: the last finished pipeline on the default branch; when it failed, the merge request that broke it" {
  [ "$(gl main-pipeline | jq -c .)" = '{"pipeline":"none","sha":null,"web_url":null,"broken_by":null}' ]
  grep -q 'GET projects/acme%2Fapp/pipelines?ref=main&scope=finished' "$FAKE_GL/calls.log"
  echo '[{"status":"canceled","sha":"c9","web_url":"u9"},{"status":"success","sha":"c1","web_url":"u1"}]' > "$FAKE_GL/pipelines.json"
  [ "$(gl main-pipeline | jq -c '[.pipeline, .sha, .broken_by]')" = '["success","c1",null]' ]
  # a canceled or skipped pipeline says nothing; the oldest of the newest failures broke it
  echo '[{"status":"failed","sha":"c3","web_url":"u3"},{"status":"skipped","sha":"c2b"},{"status":"failed","sha":"c2","web_url":"u2"},{"status":"success","sha":"c1","web_url":"u1"},{"status":"failed","sha":"c0"}]' > "$FAKE_GL/pipelines.json"
  mkdir -p "$FAKE_GL/commit-mrs"; echo '[{"iid":30,"state":"merged"}]' > "$FAKE_GL/commit-mrs/c2.json"
  echo '{"iid":30,"title":"List API","state":"merged","source_branch":"story/8-list","target_branch":"main","web_url":"w","author":{"username":"ana"}}' > "$FAKE_GL/mr-30.json"
  echo '[{"iid":8}]' > "$FAKE_GL/closes.json"
  [ "$(gl main-pipeline | jq -c .)" = '{"pipeline":"failed","sha":"c3","web_url":"u3","broken_by":{"sha":"c2","mr":30,"closes":[8]}}' ]
  echo '[]' > "$FAKE_GL/commit-mrs/c2.json"   # pushed by a person: no merge request
  [ "$(gl main-pipeline | jq -c .broken_by)" = '{"sha":"c2","mr":null,"closes":[]}' ]
}

# ---------- mr-info and comment ----------

@test "mr-info: branches, author and the issues it closes" {
  echo '{"iid":31,"title":"t","state":"opened","source_branch":"feat","target_branch":"main","web_url":"u","author":{"username":"ana"},"draft":false}' > "$FAKE_GL/mr-31.json"
  echo '[{"iid":8},{"iid":9}]' > "$FAKE_GL/closes.json"
  run gl mr-info --mr 31
  [ "$status" -eq 0 ]
  [ "$(jq -c '[.source_branch, .author, .closes]' <<<"$output")" = '["feat","ana",[8,9]]' ]
}

@test "comment: posts the body as a merge request note" {
  echo "**Review** · 0 findings" > "$BATS_TEST_TMPDIR/c.md"
  run gl comment --mr 31 --body-file "$BATS_TEST_TMPDIR/c.md"
  [ "$status" -eq 0 ]
  grep -q "POST projects/acme%2Fapp/merge_requests/31/notes" "$FAKE_GL/calls.log"
}

@test "story: key lines parse the same whether they end in \\ or are separated by blank lines" {
  issue 8 task "t" opened $'**Tests:** unit, e2e\\\n**Touches:** `src/a/**`, `src/b/**`\\\n**Blocked by:** #13\\\n**Coverage:** 90%'
  issue 13 task "b" closed ""
  a="$(gl story --iid 8 | jq -c '.story | {tests, touches, blocked_by, coverage}')"
  issue 8 task "t" opened $'**Tests:** unit, e2e\n\n**Touches:** `src/a/**`, `src/b/**`\n\n**Blocked by:** #13\n\n**Coverage:** 90%'
  b="$(gl story --iid 8 | jq -c '.story | {tests, touches, blocked_by, coverage}')"
  [ "$a" = '{"tests":["unit","e2e"],"touches":["src/a/**","src/b/**"],"blocked_by":[13],"coverage":90}' ]
  [ "$a" = "$b" ]
}

@test "open-mr always targets the default branch: no stacking on another story's branch" {
  echo "Closes #8" > "$BATS_TEST_TMPDIR/body.md"
  run gl open-mr --iid 8 --branch story/9-next --body-file "$BATS_TEST_TMPDIR/body.md" --target story/8-list
  [ "$status" -eq 1 ]
  [ "$(grep -c 'merge_requests' "$FAKE_GL/calls.log")" -eq 0 ]
  run gl open-mr-branch --iid 8
  [ "$status" -eq 1 ]
}

@test "open-mr --title opens a merge request that is not a story's" {
  echo "The plan" > "$BATS_TEST_TMPDIR/body.md"
  run gl open-mr --branch plan/S20 --title "Plan S20: invoices" --body-file "$BATS_TEST_TMPDIR/body.md"
  [ "$status" -eq 0 ]
  grep -q "source_branch=plan/S20 target_branch=main title=Plan S20: invoices" "$FAKE_GL/calls.log"
  run gl open-mr --branch plan/S20 --body-file "$BATS_TEST_TMPDIR/body.md"
  [ "$status" -eq 1 ]
  [[ "$output" == *"needs --iid"* ]] || false
}

@test "story: an item written in another language is read the same, whatever the project's language" {
  issue 8 task "t" opened $'**Como** cliente **quero** uma lista **para que** veja o histórico.\n\n## Critérios de aceitação\n- [ ] Dado 3 faturas, Quando abro, Então vejo 3\n\n## Verificação\n- `npm test`\n\n**Testes:** unit, e2e\\\n**Cobertura:** 90%\n\n<!-- compasso:key=S-1 -->'
  run gl story --iid 8
  [ "$(jq -c '[.story.acceptance, .story.verify, .story.tests, .coverage_min]' <<<"$output")" = '[["Dado 3 faturas, Quando abro, Então vejo 3"],["npm test"],["unit","e2e"],90]' ]
  cfg_set '.language = "pt-BR"'
  issue 8 task "t" opened $'## Acceptance\n- [ ] Given x, When y, Then z\n\n## Verify\n- `make test`\n\n**Tests:** unit'
  [ "$(gl story --iid 8 | jq -c '[.story.acceptance, .story.verify]')" = '[["Given x, When y, Then z"],["make test"]]' ]
}

@test "story: a description over 1 MB is read like any other" {
  head -c 1100000 /dev/zero | tr '\0' x > "$BATS_TEST_TMPDIR/big.txt"
  jq --rawfile big "$BATS_TEST_TMPDIR/big.txt" '.description += "\n\n" + $big' "$FAKE_GL/issues/8.json" > "$BATS_TEST_TMPDIR/i.json" && mv "$BATS_TEST_TMPDIR/i.json" "$FAKE_GL/issues/8.json"
  run gl story --iid 8
  [ "$status" -eq 0 ]
  [ "$(jq -r '.story.verify[0]' <<<"$output")" = "npm test -- billing" ]
}
