#!/usr/bin/env bats
load helper

# bin/run.sh: what cron starts on each agent's machine. One job per run, in a fresh session; when
# the tracker shows nothing to do, no model starts. The fake GitLab answers the snapshot from
# issue-query.json, mr-query.json and pipelines.json; the fake claude logs how it was started.
setup() {
  setup_repo
  cfg_set '.stage = "mvp" | .team.enabled = true | .team.developers = ["ana", "rui"] | .run.job_minutes = 1 | .run.failures = 2'
  export FAKE_GL="$BATS_TEST_TMPDIR/gl"; mkdir -p "$FAKE_GL"; : > "$FAKE_GL/calls.log"
  export PATH="$ROOT/tests/fake:$PATH" FAKE_CLAUDE_LOG="$BATS_TEST_TMPDIR/claude.log"
  : > "$FAKE_CLAUDE_LOG"
  echo '[{"id":1,"ref":"main","sha":"m1","status":"success"}]' > "$FAKE_GL/pipelines.json"
  RUNNER="$REPO/.compasso/runs/runner"
  git -C "$REPO" init -q; as dev ana
}
# as lead | as dev <name>: this checkout's persona, with a tracker account of its own
as() {
  local login="svc-${2:-lead}"
  if [ "$1" = lead ]; then "$ROOT/bin/persona.sh" set --repo "$REPO" --persona tech-lead >/dev/null
  else "$ROOT/bin/persona.sh" set --repo "$REPO" --persona developer --name "$2" >/dev/null; fi
  mkdir -p "$COMPASSO_HOME/accounts/gitlab.com"; printf 'glpat-x' > "$COMPASSO_HOME/accounts/gitlab.com/$login"; chmod 600 "$COMPASSO_HOME/accounts/gitlab.com/$login"
  "$ROOT/bin/persona.sh" account --repo "$REPO" --set "$login" --email "$login@agents.example" >/dev/null
}
issues() { printf '%s' "$1" > "$FAKE_GL/issue-query.json"; }
story() { # iid state [label...]
  local l="" x; for x in "${@:3}"; do l="$l,\"$x\""; done
  printf '{"iid":%s,"title":"t%s","state":"opened","labels":["type::story","compasso::%s"%s],"description":"","web_url":"u"}' "$1" "$1" "$2" "$l"
}
run_() { "$ROOT/bin/run.sh" "$@" --repo "$REPO"; }

@test "nothing to do: no model starts, and the run is recorded as idle" {
  issues "[$(story 5 backlog dev::rui)]"
  run run_ dev --name ana
  [ "$status" -eq 0 ]
  [[ "$output" == "run: dev ana - nothing to do" ]] || false
  [ ! -s "$FAKE_CLAUDE_LOG" ]
  [ "$(jq -c '{role, name, job, result}' "$RUNNER/events.jsonl")" = '{"role":"dev","name":"ana","job":null,"result":"idle"}' ]
}

@test "a job starts one headless session with the skill and the job, without permission prompts" {
  issues "[$(story 5 backlog dev::ana)]"
  run run_ dev --name ana
  [ "$(cat "$FAKE_CLAUDE_LOG")" = '-p /compasso:build {"job":"build","iids":[5],"key":"build:5"} --output-format json --permission-mode bypassPermissions' ]
  issues "[$(story 5 in-review dev::ana)]"
  echo '[{"iid":30,"source_branch":"story/5-x","draft":false,"labels":[],"description":"","sha":"h","web_url":"u","author":{"username":"a"}}]' > "$FAKE_GL/mr-query.json"
  echo '[{"id":2,"ref":"story/5-x","sha":"h","status":"success"},{"id":1,"ref":"main","sha":"m1","status":"success"}]' > "$FAKE_GL/pipelines.json"
  : > "$FAKE_CLAUDE_LOG"
  as lead
  run run_ lead
  [ "$(cat "$FAKE_CLAUDE_LOG")" = '-p /compasso:lead {"job":"review","iids":[5],"mrs":[30],"key":"review:30"} --output-format json --permission-mode bypassPermissions' ]
}

@test "a job that moved the work on is done; one that left the same job behind counts as a failure" {
  issues "[$(story 5 backlog dev::ana)]"
  FAKE_CLAUDE_DO="printf '%s' '[$(story 5 in-review dev::ana)]' > '$FAKE_GL/issue-query.json'" run run_ dev --name ana
  [ "$status" -eq 0 ]
  [ "$(tail -1 "$RUNNER/events.jsonl" | jq -c '{key, result}')" = '{"key":"build:5","result":"done"}' ]
  [ "$(jq -c . "$RUNNER/failures.json")" = '{}' ]
  issues "[$(story 6 backlog dev::ana)]"
  run run_ dev --name ana
  [ "$status" -eq 1 ]
  [ "$(tail -1 "$RUNNER/events.jsonl" | jq -c '{key, result}')" = '{"key":"build:6","result":"no-progress"}' ]
  [ "$(jq -c . "$RUNNER/failures.json")" = '{"build:6":1}' ]
}

@test "a session that fails, or runs past run.job_minutes, is a failure; a job that later succeeds clears its count" {
  issues "[$(story 5 backlog dev::ana)]"
  FAKE_CLAUDE_EXIT=3 run run_ dev --name ana
  [ "$status" -eq 1 ]
  [ "$(tail -1 "$RUNNER/events.jsonl" | jq -r .result)" = failed ]
  COMPASSO_JOB_SECONDS=1 FAKE_CLAUDE_SLEEP=5 run run_ dev --name ana
  [ "$status" -eq 1 ]
  [ "$(tail -1 "$RUNNER/events.jsonl" | jq -r .result)" = timeout ]
  [ "$(jq -c . "$RUNNER/failures.json")" = '{"build:5":2}' ]
  cfg_set '.run.failures = 3'
  FAKE_CLAUDE_DO="printf '%s' '[$(story 5 in-review dev::ana)]' > '$FAKE_GL/issue-query.json'" run run_ dev --name ana
  [ "$status" -eq 0 ]
  [ "$(jq -c . "$RUNNER/failures.json")" = '{}' ]
}

@test "run.failures failures in a row: a person is asked, with the evidence, and the story is held back" {
  issues "[$(story 5 backlog dev::ana)]"
  mkdir -p "$RUNNER"; echo '{"build:5":1}' > "$RUNNER/failures.json"
  FAKE_CLAUDE_EXIT=3 run run_ dev --name ana
  [ "$status" -eq 1 ]
  grep -q 'POST projects/acme%2Fapp/issues .*labels=needs::human' "$FAKE_GL/calls.log"
  head -1 "$FAKE_GL/desc/1.md" | grep -qx '<!-- compasso:ask story=5 key=stuck-build-5 -->'
  grep -q 'build:5 failed 2 times in a row' "$FAKE_GL/desc/1.md"
  grep -q "$RUNNER/logs/" "$FAKE_GL/desc/1.md"
  [ "$(cat "$FAKE_GL/labels/5")" = needs::human ]
}

@test "the question is written in the project's language" {
  cfg_set '.language = "pt-BR"'
  issues "[$(story 5 backlog dev::ana)]"
  mkdir -p "$RUNNER"; echo '{"build:5":1}' > "$RUNNER/failures.json"
  FAKE_CLAUDE_EXIT=3 run run_ dev --name ana
  grep -q 'POST projects/acme%2Fapp/issues title=Compasso: build:5 não termina ' "$FAKE_GL/calls.log"
  grep -q 'build:5 falhou 2 vezes seguidas' "$FAKE_GL/desc/1.md"
  grep -q 'O runner pula este trabalho' "$FAKE_GL/desc/1.md"
}

@test "a job asked about is skipped, so the developer moves on to its next story" {
  issues "[$(story 5 backlog dev::ana),$(story 6 backlog dev::ana)]"
  mkdir -p "$RUNNER"; echo '{"build:5":2}' > "$RUNNER/failures.json"
  printf '%s' "[$(story 5 backlog dev::ana),$(story 6 backlog dev::ana),{\"iid\":20,\"title\":\"q\",\"labels\":[\"needs::human\"],\"description\":\"<!-- compasso:ask story=5 key=stuck-build-5 -->\",\"web_url\":\"u\"}]" > "$FAKE_GL/issue-query.json"
  run run_ dev --name ana
  grep -q '"key":"build:6"' "$FAKE_CLAUDE_LOG"
}

@test "once the person closes the question, the job's count is cleared and it runs again" {
  issues "[$(story 5 backlog dev::ana),$(story 6 backlog dev::ana)]"
  mkdir -p "$RUNNER"; echo '{"build:5":2,"review:30":2}' > "$RUNNER/failures.json"
  run run_ dev --name ana
  grep -q '"key":"build:5"' "$FAKE_CLAUDE_LOG"
  [ "$(jq -c . "$RUNNER/failures.json")" = '{"build:5":1}' ]
}

@test "an answered question is unblocked by the runner itself, without a model" {
  issues "[$(story 5 backlog dev::ana needs::human)]"
  as lead
  run run_ lead
  [ "$status" -eq 0 ]
  [ ! -s "$FAKE_CLAUDE_LOG" ]
  grep -q 'PUT projects/acme%2Fapp/issues/5 remove_labels=needs::human' "$FAKE_GL/calls.log"
  [ "$(tail -1 "$RUNNER/events.jsonl" | jq -c '{job, result}')" = '{"job":"unblock","result":"done"}' ]
}

@test "an assignment is made by the runner itself, to the developer with the fewest ready stories" {
  issues "[$(story 5 backlog dev::ana),$(story 9 backlog)]"
  mkdir -p "$FAKE_GL/issues"; echo '{"iid":9,"id":1009,"title":"t9","state":"opened","labels":["type::story","compasso::backlog"]}' > "$FAKE_GL/issues/9.json"
  as lead
  run run_ lead
  [ "$status" -eq 0 ]
  [ ! -s "$FAKE_CLAUDE_LOG" ]
  grep -q 'PUT projects/acme%2Fapp/issues/9 add_labels=dev::rui,compasso::backlog' "$FAKE_GL/calls.log"
  [ "$(tail -1 "$RUNNER/events.jsonl" | jq -c '{job, result}')" = '{"job":"assign","result":"done"}' ]
}

@test "a red main is handled by the runner itself: a revert whose pipeline failed asks a person" {
  issues '[]'
  echo '[{"iid":31,"source_branch":"fix/main-abc","draft":false,"labels":["compasso::fix-main"],"description":"","sha":"h","web_url":"u","author":{"username":"a"}}]' > "$FAKE_GL/mr-query.json"
  echo '[{"id":3,"ref":"fix/main-abc","sha":"h","status":"failed"},{"id":2,"ref":"main","sha":"m2","status":"failed","web_url":"p2"}]' > "$FAKE_GL/pipelines.json"
  as lead
  run run_ lead
  [ ! -s "$FAKE_CLAUDE_LOG" ]
  grep -q 'key=red-main-m2 -->' "$FAKE_GL/desc/1.md"
  grep -q 'its revert !31 failed its pipeline too' "$FAKE_GL/desc/1.md"
  [ "$(tail -1 "$RUNNER/events.jsonl" | jq -r .job)" = red-main ]
}

@test "harden: the lead audits the whole code once; the next runs go on with the rest" {
  cfg_set '.stage = "harden"'
  issues '[]'
  as lead
  run run_ lead
  [ "$status" -eq 0 ]
  [ "$(cat "$FAKE_CLAUDE_LOG")" = '-p /compasso:lead {"job":"audit","iids":[],"key":"audit"} --output-format json --permission-mode bypassPermissions' ]
  [ -f "$RUNNER/audited" ]
  : > "$FAKE_CLAUDE_LOG"
  run run_ lead
  [ "$output" = "run: lead - nothing to do" ]
  [ ! -s "$FAKE_CLAUDE_LOG" ]
}

@test "harden: an audit that fails is not recorded, and runs again" {
  cfg_set '.stage = "harden"'
  issues '[]'
  as lead
  FAKE_CLAUDE_EXIT=3 run run_ lead
  [ "$status" -eq 1 ]
  [ ! -f "$RUNNER/audited" ]
}

@test "one run at a time per role and name: a second one exits at once; a stale lock is taken over" {
  issues "[$(story 5 backlog dev::ana)]"
  mkdir -p "$RUNNER/dev-ana.lock"; sleep 30 3>&- & holder=$!; echo "$holder" > "$RUNNER/dev-ana.lock/pid"
  run run_ dev --name ana
  kill "$holder"
  [ "$status" -eq 0 ]
  [[ "$output" == "run: dev ana - busy: another run holds the lock" ]] || false
  [ ! -s "$FAKE_CLAUDE_LOG" ]
  echo 999999 > "$RUNNER/dev-ana.lock/pid"
  run run_ dev --name ana
  [ -s "$FAKE_CLAUDE_LOG" ]
  [ ! -e "$RUNNER/dev-ana.lock" ]
}

@test "codex: the same job through codex exec" {
  cfg_set '.harnesses = ["codex"]'
  mkdir -p "$BATS_TEST_TMPDIR/bin"; printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "%s"\n' "$FAKE_CLAUDE_LOG" > "$BATS_TEST_TMPDIR/bin/codex"; chmod +x "$BATS_TEST_TMPDIR/bin/codex"
  issues "[$(story 5 backlog dev::ana)]"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run run_ dev --name ana
  [ "$(cat "$FAKE_CLAUDE_LOG")" = 'exec --json --dangerously-bypass-approvals-and-sandbox $compasso-build {"job":"build","iids":[5],"key":"build:5"}' ]
}

@test "a developer needs its name, and a role is lead or dev" {
  run run_ dev
  [ "$status" -eq 1 ]
  [[ "$output" == *"run: dev needs --name"* ]] || false
  run run_ tester
  [ "$status" -eq 1 ]
  [[ "$output" == *"usage: run.sh lead|dev"* ]] || false
}

@test "in a team project a run is the checkout's persona, with its own tracker account: an agent never acts as a person" {
  issues "[$(story 5 backlog dev::ana)]"
  run run_ lead
  [ "$status" -eq 1 ]
  [[ "$output" == *"run: this checkout is developer ana; run.sh lead runs in the tech lead's checkout"* ]] || false
  run run_ dev --name rui
  [ "$status" -eq 1 ]
  [[ "$output" == *"run: this checkout is developer ana; run.sh dev --name rui runs in rui's checkout"* ]] || false
  "$ROOT/bin/persona.sh" set --repo "$REPO" --persona developer --name rui >/dev/null
  for f in "$COMPASSO_HOME"/persona/*; do grep -v -e '^account=' -e '^email=' "$f" > "$f.new"; mv "$f.new" "$f"; done
  run run_ dev --name rui
  [ "$status" -eq 1 ]
  [[ "$output" == *"run: rui has no tracker account of its own, and an agent never acts as a person"* ]] || false
  [ ! -s "$FAKE_CLAUDE_LOG" ]
}

@test "production: no prompts either, but only the allowed tools run - the repo's commands, git, the tracker CLI, Compasso" {
  cfg_set '.stage = "production" | .commands.test = "npm test" | .commands.lint = "" | .run.allow = ["Bash(make deploy-check)"]'
  issues "[$(story 5 backlog dev::ana)]"
  run run_ dev --name ana
  log="$(cat "$FAKE_CLAUDE_LOG")"
  [[ "$log" == '-p /compasso:build {"job":"build","iids":[5],"key":"build:5"} --output-format json --permission-mode dontAsk --allowedTools '* ]] || false
  for t in Read Edit Write Glob Grep Agent 'Bash(git *)' 'Bash(glab *)' 'Bash(bash */compasso/*)' 'Bash(npm test*)' 'Bash(make deploy-check)'; do
    [[ ",${log#*--allowedTools }," == *",$t,"* ]] || false
  done
  [[ "$log" != *"bypassPermissions"* ]] || false
  [[ "$log" != *'Bash(*)'* ]] || false
}

@test "production on codex: the workspace-write sandbox, with the network for git and the tracker" {
  cfg_set '.stage = "production" | .harnesses = ["codex"]'
  mkdir -p "$BATS_TEST_TMPDIR/bin"; printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "%s"\n' "$FAKE_CLAUDE_LOG" > "$BATS_TEST_TMPDIR/bin/codex"; chmod +x "$BATS_TEST_TMPDIR/bin/codex"
  issues "[$(story 5 backlog dev::ana)]"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run run_ dev --name ana
  [ "$(cat "$FAKE_CLAUDE_LOG")" = 'exec --json --sandbox workspace-write -c sandbox_workspace_write.network_access=true $compasso-build {"job":"build","iids":[5],"key":"build:5"}' ]
}

@test "each job records its stories and what the session reported it used; nothing is guessed when it reports none" {
  issues "[$(story 5 backlog dev::ana)]"
  FAKE_CLAUDE_DO="echo 'some text'; echo '{\"type\":\"result\",\"num_turns\":7,\"total_cost_usd\":0.42,\"usage\":{\"input_tokens\":10,\"cache_creation_input_tokens\":20,\"cache_read_input_tokens\":30,\"output_tokens\":40},\"modelUsage\":{\"claude-haiku\":{\"costUSD\":0.02},\"claude-opus\":{\"costUSD\":0.4}}}'" run run_ dev --name ana
  [ "$(tail -1 "$RUNNER/events.jsonl" | jq -c '{iids, tokens, cost_usd, turns, model}')" = '{"iids":[5],"tokens":100,"cost_usd":0.42,"turns":7,"model":"claude-opus"}' ]
  run run_ dev --name ana
  [ "$(tail -1 "$RUNNER/events.jsonl" | jq -c 'has("tokens"), has("cost_usd")' | tr '\n' ' ')" = 'false false ' ]
}

@test "codex: the session's tokens come from its turn.completed events" {
  cfg_set '.harnesses = ["codex"]'
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/usr/bin/env bash\necho "{\\"type\\":\\"turn.completed\\",\\"usage\\":{\\"input_tokens\\":100,\\"cached_input_tokens\\":50,\\"output_tokens\\":5}}"\necho "{\\"type\\":\\"turn.completed\\",\\"usage\\":{\\"input_tokens\\":10,\\"output_tokens\\":1}}"\n' > "$BATS_TEST_TMPDIR/bin/codex"; chmod +x "$BATS_TEST_TMPDIR/bin/codex"
  issues "[$(story 5 backlog dev::ana)]"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run run_ dev --name ana
  [ "$(tail -1 "$RUNNER/events.jsonl" | jq -c '{tokens, turns}')" = '{"tokens":116,"turns":2}' ]
}

# a checkout of a shared origin, as on an agent's machine; another clone merges to main
with_origin() {
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
  ORIGIN="$BATS_TEST_TMPDIR/origin.git"; git init -q --bare -b main "$ORIGIN"
  git -C "$REPO" checkout -q -b main; git -C "$REPO" add .compasso/project.yaml; git -C "$REPO" commit -q -m init
  git -C "$REPO" remote add origin "$ORIGIN"; git -C "$REPO" push -q -u origin main
  OTHER="$BATS_TEST_TMPDIR/other"; git clone -q "$ORIGIN" "$OTHER"
}
merge_on_main() { yq -i "$1" "$OTHER/.compasso/project.yaml"; git -C "$OTHER" commit -q -am change; git -C "$OTHER" push -q origin main; }

@test "a change merged to main reaches the next run: the checkout comes back to main, up to date" {
  with_origin
  git -C "$REPO" checkout -q -b story/4-old
  merge_on_main '.stage = "production"'
  issues "[$(story 5 backlog dev::ana)]"
  run run_ dev --name ana
  [ "$(git -C "$REPO" rev-parse --abbrev-ref HEAD)" = main ]
  [ "$(git -C "$REPO" rev-parse HEAD)" = "$(git -C "$OTHER" rev-parse HEAD)" ]
  [[ "$(cat "$FAKE_CLAUDE_LOG")" == *"--permission-mode dontAsk"* ]] || false
}

@test "uncommitted changes are never touched: the checkout stays where it is and says so" {
  with_origin
  git -C "$REPO" checkout -q -b story/4-old
  merge_on_main '.stage = "production"'
  echo '# wip' >> "$REPO/.compasso/project.yaml"
  issues "[$(story 5 backlog dev::ana)]"
  run run_ dev --name ana
  [[ "$output" == *"uncommitted changes in this checkout; it stays on story/4-old instead of main"* ]] || false
  [ "$(git -C "$REPO" rev-parse --abbrev-ref HEAD)" = story/4-old ]
  [ "$(tail -1 "$REPO/.compasso/project.yaml")" = '# wip' ]
  [[ "$(cat "$FAKE_CLAUDE_LOG")" == *"--permission-mode bypassPermissions"* ]] || false
}
