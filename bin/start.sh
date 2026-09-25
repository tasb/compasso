#!/usr/bin/env bash
# Where a product stands on the way from ideas to built sprints, and the command that moves
# it forward. Read-only.
#
#   start.sh --repo R [--json]
#
# Stages, in order: setup (no .compasso/project.yaml) -> discover (no product brief) ->
# backlog (no .compasso/backlog.yaml) -> roadmap (no .compasso/roadmap.yaml) -> plan (the
# roadmap's next sprint is not planned) -> build (a sprint is planned). Also says whether the
# repository has no product code yet (greenfield), which needs a walking skeleton first.
# Exit: 0 | 2 usage
set -u

BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="." JSON=0
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --json) JSON=1; shift ;;
    *) echo "start: unknown argument '$1'" >&2; exit 2 ;;
  esac
done
C="$REPO/.compasso"

# greenfield: nothing tracked or on disk besides docs, CI, config and Compasso's own files
code="$( { git -C "$REPO" ls-files 2>/dev/null; ( cd "$REPO" && find . -type f -not -path './.git/*' 2>/dev/null | sed 's#^\./##' ); } |
  grep -vE '^(\.compasso/|\.github/|\.gitlab/|\.gitlab-ci\.yml$|\.codex/|\.claude/|docs/|README|LICENSE|CHANGELOG|CONTRIBUTING|SECURITY|\.gitignore$|\.gitattributes$|\.editorconfig$)' | head -1)"
greenfield=false; [ -z "$code" ] && greenfield=true

plan_n=""; [ -f "$C/plan.yaml" ] && plan_n="$(yq -r '.epic.sprint.number // ""' "$C/plan.yaml")"
if [ ! -f "$C/project.yaml" ]; then
  stage=setup next="/compasso:setup" why="the repository is not connected to a tracker yet"
elif [ ! -f "$C/product/brief.md" ] && [ ! -f "$C/backlog.yaml" ]; then
  stage=discover next="/compasso:discover" why="there is no product brief: start from your ideas, a document, tracker issues or a prototype"
elif [ ! -f "$C/backlog.yaml" ]; then
  stage=backlog next="/compasso:backlog" why="the brief is written; the features and the MVP line are not"
elif [ ! -f "$C/roadmap.yaml" ]; then
  stage=roadmap next="/compasso:roadmap" why="the backlog is ready; it is not placed into sprints yet"
elif [ -z "$plan_n" ]; then
  first="$("$BIN/roadmap.sh" next --repo "$REPO" 2>/dev/null | jq -r '.number // empty')"
  stage=plan next="/compasso:plan" why="sprint S${first:-?} is next in the roadmap: split it into stories"
else
  stage=build next="/compasso:sprint" why="sprint S$plan_n is planned: build it (/compasso:status shows where it stands); at its close, /compasso:roadmap refines what is ahead and /compasso:plan plans the next sprint"
fi

if [ "$JSON" -eq 1 ]; then
  jq -n --arg s "$stage" --arg n "$next" --arg w "$why" --argjson g "$greenfield" '{stage: $s, next: $n, why: $w, greenfield: $g}'
else
  echo "Stage: $stage - $why"
  echo "Next: $next"
  [ "$greenfield" = true ] && echo "No product code yet: the first sprint builds a walking skeleton (feature F-0), and setup runs again once it has test commands."
fi
exit 0
