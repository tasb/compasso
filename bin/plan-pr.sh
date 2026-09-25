#!/usr/bin/env bash
# Send the approved plan and its records to the default branch through a merge request.
#
#   plan-pr.sh --repo R --title T [--branch B]
#   plan-pr.sh --repo R --title T --branch B --include PATH [--include PATH ...]
#
# Commits .compasso/plan.yaml and .compasso/records/S<n>/ as they are in the working tree onto
# B (default plan/S<n>), based on the remote's default branch - or on B's own remote branch
# when a plan merge request is already open, so a re-plan updates it - using a temporary
# worktree, so the current branch and working tree are left alone. With --include, it sends
# those paths instead (files or folders, e.g. the product brief, backlog and roadmap). Then opens or updates
# the merge request (a pull request on GitHub). Prints its {iid, web_url}.
# Exit: 0 | 1 git or tracker failure | 2 usage or nothing to send
set -u

BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="." TITLE="" BRANCH="" INCLUDES=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --title) TITLE="$2"; shift 2 ;;
    --branch) BRANCH="$2"; shift 2 ;;
    --include) INCLUDES="$INCLUDES
$2"; shift 2 ;;
    *) echo "plan-pr: unknown argument '$1'" >&2; exit 2 ;;
  esac
done
[ -n "$TITLE" ] || { echo "plan-pr: needs --title" >&2; exit 2; }
REPO="$(cd "$REPO" && pwd)"
PLAN="$REPO/.compasso/plan.yaml"
if [ -n "$INCLUDES" ]; then
  [ -n "$BRANCH" ] || { echo "plan-pr: --include needs --branch" >&2; exit 2; }
  PATHS="$(printf '%s\n' "$INCLUDES" | sed '/^$/d')"
else
  [ -f "$PLAN" ] || { echo "plan-pr: no .compasso/plan.yaml" >&2; exit 2; }
  S="S$(yq -r '.epic.sprint.number' "$PLAN")"
  [ -n "$BRANCH" ] || BRANCH="plan/$S"
  PATHS=".compasso/plan.yaml
.compasso/records/$S"
fi
while IFS= read -r p; do
  case "$p" in /*|*..*) echo "plan-pr: $p must be a path inside the repository" >&2; exit 2 ;; esac
done <<EOF
$PATHS
EOF

git -C "$REPO" fetch -q origin || { echo "plan-pr: git fetch failed" >&2; exit 1; }
default="$(git -C "$REPO" ls-remote --symref origin HEAD | sed -n 's#^ref: refs/heads/\([^[:space:]]*\).*#\1#p')"
[ -n "$default" ] || { echo "plan-pr: cannot tell the remote's default branch" >&2; exit 1; }
base="origin/$default"
git -C "$REPO" rev-parse -q --verify "origin/$BRANCH" >/dev/null && base="origin/$BRANCH"

WT="$(mktemp -d)"; trap 'git -C "$REPO" worktree remove --force "$WT" >/dev/null 2>&1; rm -rf "$WT"' EXIT
git -C "$REPO" worktree add -q -B "$BRANCH" "$WT" "$base" || { echo "plan-pr: cannot create a worktree for $BRANCH" >&2; exit 1; }
while IFS= read -r p; do
  [ -e "$REPO/$p" ] || continue
  rm -rf "${WT:?}/$p"; mkdir -p "$(dirname "$WT/$p")"; cp -R "$REPO/$p" "$WT/$p"
  git -C "$WT" add -A "$p"
done <<EOF
$PATHS
EOF
if git -C "$WT" diff --cached --quiet >/dev/null; then
  echo "plan-pr: the plan and records on $BRANCH are already up to date" >&2
else
  git -C "$WT" commit -q -m "$TITLE" || { echo "plan-pr: commit failed" >&2; exit 1; }
fi
out="$(git -C "$WT" push -q -u origin "$BRANCH" 2>&1)" || { printf '%s\n' "$out" >&2; echo "plan-pr: push of $BRANCH failed" >&2; exit 1; }

body="$WT/.plan-pr-body.md"
{
  if [ -n "$INCLUDES" ]; then echo "$TITLE."; else echo "The approved plan for $S and what was found and decided while planning it."; fi
  echo
  while IFS= read -r p; do
    if [ -d "$WT/$p" ]; then (cd "$WT" && find "$p" -type f | sort | sed 's/^/- `/; s/$/`/')
    elif [ -e "$WT/$p" ]; then echo "- \`$p\`"; fi
  done <<EOF
$PATHS
EOF
  echo
  echo "Merging this keeps these files in the repository, where the next steps read them."
} > "$body"
"$BIN/tracker.sh" open-mr --repo "$REPO" --branch "$BRANCH" --title "$TITLE" --body-file "$body" --target "$default"
