#!/usr/bin/env bash
# Warn when these scripts are an older Compasso than the newest one installed: Claude Code keeps every
# version it installed (<cache>/<marketplace>/compasso/<version>/), and a skill can run from an old one.
#
#   version.sh     prints the warning on stderr, or nothing; bin/start.sh and bin/status.sh run it
#
# The cache is ~/.claude/plugins/cache, or $COMPASSO_PLUGIN_CACHE.
# Exit: 0 always
set -u
case "${1:-}" in -h|--help) sed -n '2,/^set -u/s/^# \{0,1\}//p' "$0"; exit 0 ;; esac   # the header above is the help

BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CACHE="${COMPASSO_PLUGIN_CACHE:-$HOME/.claude/plugins/cache}"
running="$(jq -r '.version // empty' "$BIN/../.claude-plugin/plugin.json" 2>/dev/null)"
[ -n "$running" ] && [ -d "$CACHE" ] || exit 0
newer() { # a b: is version a newer than b, part by part as numbers
  local IFS=. a b i
  read -r -a a <<<"$1"; read -r -a b <<<"$2"
  for i in 0 1 2; do
    [ "${a[$i]:-0}" -gt "${b[$i]:-0}" ] 2>/dev/null && return 0
    [ "${a[$i]:-0}" -lt "${b[$i]:-0}" ] 2>/dev/null && return 1
  done
  return 1
}
newest="$running"
for f in "$CACHE"/*/compasso/*/.claude-plugin/plugin.json; do
  [ -f "$f" ] || continue
  v="$(jq -r '.version // empty' "$f" 2>/dev/null)"
  [ -n "$v" ] && newer "$v" "$newest" && newest="$v"
done
[ "$newest" = "$running" ] ||
  echo "compasso: these scripts are version $running, but $newest is installed - restart the session so every Compasso skill runs $newest" >&2
exit 0
