#!/usr/bin/env bats
load helper

setup() { setup_repo; }

@test "the project's language, over English; English without a config" {
  [ "$("$ROOT/bin/locale.sh" --repo "$REPO" | jq -r '[.lang, .md.acceptance] | join("|")')" = "en|Acceptance" ]
  cfg_set '.language = "pt-PT"'
  [ "$("$ROOT/bin/locale.sh" --repo "$REPO" | jq -r '[.lang, .md.acceptance, .text.qa_title[2:22]] | join("|")')" = "pt-PT|Critérios de aceitação|Perguntas e resposta" ]
  [ "$("$ROOT/bin/locale.sh" --repo "$BATS_TEST_TMPDIR/none" | jq -r .lang)" = en ]
  run "$ROOT/bin/locale.sh" --lang xx
  [ "$status" -eq 1 ]
}

@test "every language has every text English has (nothing silently falls back)" {
  en="$(yq -o=json . "$ROOT/templates/locales/en.yaml" | jq -c '[paths(scalars)] | map(map(tostring) | join(".")) | map(select(startswith("name") | not)) | sort')"
  for f in "$ROOT"/templates/locales/*.yaml; do
    k="$(yq -o=json . "$f" | jq -c '[paths(scalars)] | map(map(tostring) | join(".")) | map(select(startswith("name") | not)) | sort')"
    missing="$(jq -nr --argjson a "$en" --argjson b "$k" '$a - $b | join(", ")')"
    [ -z "$missing" ] || { echo "$(basename "$f") lacks: $missing"; false; }
  done
}

@test "every text keeps the {markers} English has, so no value is lost" {
  for f in "$ROOT"/templates/locales/pt-*.yaml; do
    bad="$(jq -nr --argjson en "$(yq -o=json .text "$ROOT/templates/locales/en.yaml")" --argjson l "$(yq -o=json .text "$f")" '
      [$en | to_entries[] | select(.value | type == "string") | .key as $k | ([.value | scan("\\{[a-z]+\\}")] | sort) as $m
       | select(([$l[$k] | scan("\\{[a-z]+\\}")] | sort) != $m) | $k] | join(", ")')"
    [ -z "$bad" ] || { echo "$(basename "$f"): $bad"; false; }
  done
}

@test "names lists each work-item name in every language, for reading" {
  [ "$("$ROOT/bin/locale.sh" --names | jq -c '.scope')" = '["Escopo","Scope","Âmbito"]' ]
}

@test "every label the three pages use exists in English (and so, by the test above, in every language)" {
  used() { grep -oE "$2" "$ROOT/templates/$1" | sed -E "s/$3/\1/" | sort -u; }
  have() { yq -r ".ui.$1 | keys | .[]" "$ROOT/templates/locales/en.yaml" | sort -u; }
  [ -z "$(comm -23 <(used report.html "(u|fmt)\('[a-zA-Z]+'" ".*'([a-zA-Z]+)'") <(have report))" ]
  [ -z "$(comm -23 <(used presentation.html 'ui\.[a-zA-Z]+' 'ui\.([a-zA-Z]+)') <(have presentation))" ]
  [ -z "$(comm -23 <(used test-guide.html 'ui\.[a-zA-Z]+' 'ui\.([a-zA-Z]+)') <(have guide))" ]
}
