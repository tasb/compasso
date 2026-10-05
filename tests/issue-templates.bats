#!/usr/bin/env bats
load helper

setup() { REPO="$BATS_TEST_TMPDIR/repo"; mkdir -p "$REPO"; }
it() { "$ROOT/bin/issue-templates.sh" --repo "$REPO"; }

@test "installs one template per work-item type" {
  run it
  [ "$status" -eq 0 ]
  [[ "$output" == *"5 added, 0 unchanged"* ]] || false
  for t in Epic Feature Story Bug Blocker; do
    cmp -s "$ROOT/templates/issue_templates/en/$t.md" "$REPO/.gitlab/issue_templates/$t.md"
  done
}

@test "a second run changes nothing" {
  it >/dev/null
  run it
  [[ "$output" == *"0 added, 5 unchanged"* ]] || false
}

@test "a template the team edited is kept and reported" {
  mkdir -p "$REPO/.gitlab/issue_templates"
  echo "our own feature format" > "$REPO/.gitlab/issue_templates/Feature.md"
  run it
  [ "$status" -eq 0 ]
  [[ "$output" == *"4 added, 0 unchanged"* ]] || false
  [[ "$output" == *"kept the repo's own version of: Feature.md"* ]] || false
  [ "$(cat "$REPO/.gitlab/issue_templates/Feature.md")" = "our own feature format" ]
}

@test "templates label what the tracker filters on" {
  grep -qF '/label ~"type::feature" ~"compasso::new"' "$ROOT/templates/issue_templates/en/Feature.md"
  grep -qF '/label ~"type::bug"' "$ROOT/templates/issue_templates/en/Bug.md"
  grep -qF '/label ~"type::epic"' "$ROOT/templates/issue_templates/en/Epic.md"
}

@test "every label a template applies is one ensure-labels creates" {
  for l in $(cat "$ROOT"/templates/issue_templates/*/*.md | grep -o '~"[^"]*"' | tr -d '~"' | sort -u); do
    grep -q "^$l|" "$ROOT/bin/tracker/labels.txt"
  done
}

@test "the blocker template is urgent and asks for a person" {
  grep -qF '/label ~"type::blocker" ~"priority::urgent"' "$ROOT/templates/issue_templates/en/Blocker.md"
  grep -q '^/assign ' "$ROOT/templates/issue_templates/en/Blocker.md"
}

@test "on GitHub: .github/ISSUE_TEMPLATE, each type's labels, no Depends on line" {
  "$ROOT/bin/config.sh" init --repo "$REPO" --project acme/app >/dev/null
  yq -i '.tracker.provider = "github"' "$REPO/.compasso/project.yaml"
  run it
  [ "$status" -eq 0 ]
  [[ "$output" == *"5 added, 0 unchanged"* ]] || false
  [ ! -e "$REPO/.gitlab" ]
  D="$REPO/.github/ISSUE_TEMPLATE"
  [ "$(yq --front-matter=extract '.labels' "$D/blocker.md")" = "type::blocker, priority::urgent" ]
  [ "$(yq --front-matter=extract '.title' "$D/epic.md")" = "S<sprint>: " ]
  [ "$(grep -c 'Depends on' "$D/story.md" || true)" -eq 0 ]
  grep -q 'Blocked by' "$D/story.md"
  run it
  [[ "$output" == *"0 added, 5 unchanged"* ]] || false
}

@test "in the project's language: Portuguese templates, read back by Compasso; GitHub drops Depends on in any language" {
  "$ROOT/bin/config.sh" init --repo "$REPO" --project acme/app >/dev/null
  yq -i '.language = "pt-PT"' "$REPO/.compasso/project.yaml"
  it >/dev/null
  grep -qx '## Critérios de aceitação' "$REPO/.gitlab/issue_templates/Story.md"
  sed -e 's/<!--[^>]*-->//g' "$REPO/.gitlab/issue_templates/Story.md" | jq -Rs --argjson N "$("$ROOT/bin/locale.sh" --names)" -f "$ROOT/bin/parse.jq" > "$BATS_TEST_TMPDIR/p.json"
  [ "$(jq -c '[(.acceptance | length), (.verify | length)]' "$BATS_TEST_TMPDIR/p.json")" = '[1,1]' ]
  rm -rf "$REPO/.gitlab"; yq -i '.tracker.provider = "github" | .language = "pt-BR"' "$REPO/.compasso/project.yaml"
  it >/dev/null
  [ "$(grep -c 'Depende de' "$REPO/.github/ISSUE_TEMPLATE/story.md" || true)" -eq 0 ]
  grep -q 'Blocked by' "$REPO/.github/ISSUE_TEMPLATE/story.md"
  grep -qx '## Escopo' "$REPO/.github/ISSUE_TEMPLATE/feature.md"
}

@test "every language ships the same templates with the same labels and commands" {
  for l in "$ROOT"/templates/issue_templates/*/; do
    [ "$(ls "$l" | tr '\n' ' ')" = "$(ls "$ROOT/templates/issue_templates/en" | tr '\n' ' ')" ]
    for f in "$l"*.md; do
      [ "$(grep '^/' "$f")" = "$(grep '^/' "$ROOT/templates/issue_templates/en/$(basename "$f")" | sed 's/<!--.*-->//')" ] || [ "$(grep '^/' "$f" | sed 's/<!--.*-->//')" = "$(grep '^/' "$ROOT/templates/issue_templates/en/$(basename "$f")" | sed 's/<!--.*-->//')" ]
    done
  done
}
