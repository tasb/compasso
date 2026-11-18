#!/usr/bin/env bash
# The crontab line that starts bin/run.sh on this machine, for this checkout's persona.
#
#   cron.sh --repo R
#
# It copies bin/compasso-run to ${COMPASSO_HOME:-$HOME/.compasso}/bin (a path no plugin update moves) and
# prints the line: the tech lead every run.lead_minutes, a developer every run.dev_minutes, with this shell's
# PATH (cron's own has no glab, gh, jq, yq or claude) and the output in .compasso/runs/runner/cron.log.
# It never edits the crontab: a person adds the line (crontab -e).
# Exit: 0 | 1 not a team checkout (tech lead or developer), or minutes cron cannot repeat
set -u
case "${1:-}" in -h|--help) sed -n '2,/^set -u/s/^# \{0,1\}//p' "$0"; exit 0 ;; esac   # the header above is the help

BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="."
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    *) echo "cron: unknown argument '$1'" >&2; exit 1 ;;
  esac
done
REPO="$(cd "$REPO" 2>/dev/null && pwd)" || { echo "cron: no repository at --repo" >&2; exit 1; }
cfg() { "$BIN/config.sh" get --repo "$REPO" "$1"; }
me="$("$BIN/persona.sh" show --repo "$REPO" --json)" || exit 1
case "$(jq -r .persona <<<"$me")" in
  tech-lead) args="lead" m="$(cfg '.run.lead_minutes // 15')" ;;
  developer) args="dev --name $(jq -r .name <<<"$me")" m="$(cfg '.run.dev_minutes // 10')" ;;
  *) echo "cron: the runner works for a team: run setup and choose tech lead or developer for this checkout" >&2; exit 1 ;;
esac
if [ "$m" -lt 60 ]; then when="*/$m * * * *"
elif [ $((m % 60)) -eq 0 ] && [ "$m" -le 1440 ]; then when="0 */$((m / 60)) * * *"
else echo "cron: $m minutes cannot be repeated by cron: use fewer than 60, or whole hours" >&2; exit 1; fi

HOME_DIR="${COMPASSO_HOME:-$HOME/.compasso}"
mkdir -p "$HOME_DIR/bin" "$REPO/.compasso/runs/runner" && cp "$BIN/compasso-run" "$HOME_DIR/bin/" && chmod 755 "$HOME_DIR/bin/compasso-run" || exit 1
printf "%s PATH='%s' '%s' %s --repo '%s' >> '%s' 2>&1\n" "$when" "$PATH" "$HOME_DIR/bin/compasso-run" "$args" "$REPO" "$REPO/.compasso/runs/runner/cron.log"
