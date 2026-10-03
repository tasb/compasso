#!/usr/bin/env bats
load helper

@test "the plugin's version has its own section in the changelog" {
  v="$(jq -r .version "$ROOT/.claude-plugin/plugin.json")"
  [[ "$v" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || false
  grep -qE "^## $v( |$)" "$ROOT/CHANGELOG.md"
}
