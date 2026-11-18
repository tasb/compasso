#!/usr/bin/env bash
# The tech lead's actions, one call each: the lead decides (skills/lead), these act the same way every time.
#
#   lead.sh merge    --repo R --mr N                     merge when its pipeline succeeds. A conflict sends it back to
#                                                        rebase, which is not a review round; a failed pipeline is refused.
#   lead.sh rework   --repo R --mr N --story S --body-file F   send it back with F, the blockers. One round: blockers found
#                                                        again after a rework go to a person instead (bin/human.sh), and S waits.
#   lead.sh later    --repo R --body-file F              add F to the after-MVP list: what the review saw that is not a blocker
#   lead.sh hardening --repo R                           the open hardening feature (opened once), for the stories drained from
#                                                        the after-MVP list in the harden stage -> {iid, web_url}
#   lead.sh story    --repo R --feature N --title T --from S.json   write a story of feature N on the tracker, in its sprint
#                                                        (S: as, want, so_that, acceptance, verify, tests - unit and/or e2e -
#                                                        and optionally touches, depends_on ["#12"]); refused when incomplete
#   lead.sh deliver  --repo R --feature N --title T --from F.json   ask people to test feature N on staging (F has need,
#                                                        why, steps and meanwhile; staging.url becomes the first step), then
#                                                        N is done and closed
#   lead.sh red-main --repo R [--failed-fix N]           revert the commit that turned the default branch red, as a
#                                                        compasso::fix-main merge request that merges itself; the stories it
#                                                        closed reopen. A revert that conflicts, or a fix N whose pipeline
#                                                        failed, goes to a person. bin/run.sh runs it, without a model.
#
# A blocker is: acceptance not met, data loss, a leaked secret, or the default branch breaking. Nothing else sends work back.
# Exit: 0 done (asking a person counts) | 1 usage, refused, or a tracker or git failure
set -u
case "${1:-}" in -h|--help) sed -n '2,/^set -u/s/^# \{0,1\}//p' "$0"; exit 0 ;; esac   # the header above is the help

BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CMD="${1:-}"; shift || true
REPO="." MR="" STORY="" BODY="" FEATURE="" TITLE="" FROM="" FIX=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --mr) MR="$2"; shift 2 ;;
    --story) STORY="$2"; shift 2 ;;
    --body-file) BODY="$2"; shift 2 ;;
    --feature) FEATURE="$2"; shift 2 ;;
    --title) TITLE="$2"; shift 2 ;;
    --from) FROM="$2"; shift 2 ;;
    --failed-fix) FIX="$2"; shift 2 ;;
    *) echo "lead: unknown argument '$1'" >&2; exit 1 ;;
  esac
done
need() { local v; for v in "$@"; do [ -n "${!v}" ] || { echo "lead: $CMD needs --$(echo "$v" | tr 'A-Z_' 'a-z-' | sed 's/^body$/body-file/')" >&2; exit 1; }; done; }
trk() { local c="$1"; shift; "$BIN/tracker.sh" "$c" --repo "$REPO" "$@"; }
TMP="$(mktemp -d)"; WT=""
cleanup() { [ -z "$WT" ] || git -C "$REPO" worktree remove --force "$WT" >/dev/null 2>&1; rm -rf "$TMP"; }
trap cleanup EXIT
LOC=""
say() { # key [vars-json]: a text in the project's language
  local v="${2:-}"; [ -n "$v" ] || v='{}'
  [ -n "$LOC" ] || LOC="$("$BIN/locale.sh" --repo "$REPO")" || exit 1
  jq -rn -L "$BIN" --argjson L "$LOC" --arg k "$1" --argjson v "$v" 'include "i18n"; tf($k; $v)'
}

case "$CMD" in
  merge)
    need MR
    c="$(trk mr-checks --mr "$MR")" || exit 1
    if [ "$(jq -r .conflicts <<<"$c")" = true ]; then
      branch="$(trk mr-info --mr "$MR" | jq -r .target_branch)" || exit 1
      say rework_conflict "$(jq -cn --arg mr "$MR" --arg branch "$branch" '$ARGS.named')" > "$TMP/c.md"
      trk comment --mr "$MR" --body-file "$TMP/c.md" >/dev/null && trk mr-label --mr "$MR" --add compasso::rework >/dev/null || exit 1
      echo "lead: !$MR conflicts with $branch - sent back to rebase"; exit 0
    fi
    trk mr-merge --mr "$MR" ;;   # refuses a failed pipeline

  rework)
    need MR STORY BODY
    [ -f "$BODY" ] || { echo "lead: no body file $BODY" >&2; exit 1; }
    rounds="$(trk comments --mr "$MR" | jq '[.[] | select(.body | contains("<!-- compasso:rework -->"))] | length')" || exit 1
    { cat "$BODY"; printf '\n\n%s\n\n<!-- compasso:rework -->\n' "$(say rework_footer)"; } > "$TMP/rework.md"
    trk comment --mr "$MR" --body-file "$TMP/rework.md" >/dev/null || exit 1
    if [ "$rounds" -eq 0 ]; then
      trk mr-label --mr "$MR" --add compasso::rework >/dev/null || exit 1
      echo "lead: !$MR sent back for rework"; exit 0
    fi
    url="$(trk mr-info --mr "$MR" | jq -r .web_url)" || exit 1
    v="$(jq -cn --arg mr "$MR" --arg url "$url" '$ARGS.named')"
    jq -n -L "$BIN" --argjson L "$("$BIN/locale.sh" --repo "$REPO")" --argjson v "$v" 'include "i18n"; {
      need: tf("rework_twice_need"; $v), why: [tf("rework_twice_why"; $v)],
      steps: [tf("rework_twice_step_read"; $v), t("rework_twice_step_decide")], meanwhile: t("rework_twice_meanwhile")}' > "$TMP/q.json" || exit 1
    "$BIN/human.sh" ask --repo "$REPO" --key "rework-$MR" --story "$STORY" --title "$(say rework_twice_title "$v")" --from "$TMP/q.json" >/dev/null || exit 1
    echo "lead: !$MR had blockers again after its rework - a person decides; #$STORY waits" ;;

  later)
    need BODY
    trk after-mvp --title "$(say later_title)" --body-file "$BODY" ;;

  hardening)
    trk harden-feature --title "$(say hardening_title)" ;;

  story)
    need FEATURE TITLE FROM
    for k in as want so_that acceptance verify tests; do
      jq -e --arg k "$k" '.[$k] | if type == "array" then length > 0 and all(.[]; type == "string" and . != "")
        else type == "string" and . != "" end' "$FROM" >/dev/null 2>&1 || { echo "lead: the story needs $k" >&2; exit 1; }
    done
    jq -e '.tests | all(.[]; IN("unit", "e2e"))' "$FROM" >/dev/null || { echo "lead: the story needs tests that are unit or e2e" >&2; exit 1; }
    trk add-story --parent "$FEATURE" --title "$TITLE" --from "$FROM" ;;

  deliver)
    need FEATURE TITLE FROM
    url="$("$BIN/config.sh" get --repo "$REPO" '.staging.url // ""')"
    jq --arg url "$url" --arg open "$(say deliver_open "$(jq -cn --arg url "$url" '$ARGS.named')")" \
      'if $url == "" then . else .steps = [$open] + (.steps // []) end' "$FROM" > "$TMP/q.json" 2>/dev/null ||
      { echo "lead: $FROM is not JSON" >&2; exit 1; }
    a="$("$BIN/human.sh" ask --repo "$REPO" --key "deliver-$FEATURE" --title "$TITLE" --from "$TMP/q.json")" || exit 1
    say deliver_done "$(jq -c '{ask: .iid}' <<<"$a")" > "$TMP/done.md"
    trk set-state --iid "$FEATURE" --state done >/dev/null && trk close --iid "$FEATURE" --body-file "$TMP/done.md" >/dev/null || exit 1
    echo "lead: feature #$FEATURE delivered - people test it in #$(jq -r .iid <<<"$a")" ;;

  red-main)
    mp="$(trk main-pipeline)" || exit 1
    [ "$(jq -r .pipeline <<<"$mp")" = failed ] || { echo "lead: the default branch is not red"; exit 0; }
    sha="$(jq -r '.broken_by.sha // .sha' <<<"$mp")"; short="$(printf '%s' "$sha" | cut -c1-8)"
    branch="$(git -C "$REPO" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')"; [ -n "$branch" ] || branch=main
    v="$(jq -cn --arg sha "$short" --arg branch "$branch" --arg url "$(jq -r '.web_url // ""' <<<"$mp")" --arg fix "$FIX" '$ARGS.named')"
    ask_person() { # need-key
      jq -n -L "$BIN" --argjson L "$("$BIN/locale.sh" --repo "$REPO")" --argjson v "$v" --arg need "$1" 'include "i18n"; {
        need: tf($need; $v), why: [tf("red_why"; $v)], steps: [tf("red_step_fix"; $v), t("red_step_merge")], meanwhile: t("red_meanwhile")}' > "$TMP/q.json" &&
      "$BIN/human.sh" ask --repo "$REPO" --key "red-main-$short" --title "$(say red_ask_title "$v")" --from "$TMP/q.json" >/dev/null || exit 1
    }
    if [ -n "$FIX" ]; then ask_person red_failed_need; echo "lead: the revert !$FIX failed too - a person fixes $branch"; exit 0; fi
    git -C "$REPO" fetch -q origin "$branch" || { echo "lead: cannot fetch $branch" >&2; exit 1; }
    fix="fix/main-$short"; WT="$TMP/wt"
    git -C "$REPO" worktree add -q -B "$fix" "$WT" "origin/$branch" >/dev/null 2>&1 || { WT=""; echo "lead: cannot check out $branch to revert $short" >&2; exit 1; }
    if ! git -C "$WT" revert --no-edit -m 1 "$sha" >/dev/null 2>&1; then   # -m 1: a merge commit goes back to its first parent; git ignores it otherwise
      git -C "$WT" revert --abort >/dev/null 2>&1
      ask_person red_conflict_need; echo "lead: reverting $short conflicts - a person fixes $branch"; exit 0
    fi
    git -C "$WT" push -q -f origin "HEAD:refs/heads/$fix" || { echo "lead: cannot push $fix" >&2; exit 1; }
    say red_body "$v" > "$TMP/body.md"
    new="$(trk open-mr --branch "$fix" --title "$(say red_title "$v")" --body-file "$TMP/body.md" | jq -r '.iid // empty')"
    [ -n "$new" ] || exit 1
    trk mr-label --mr "$new" --add compasso::fix-main >/dev/null && trk mr-merge --mr "$new" >/dev/null || exit 1
    v="$(jq -c --arg fix "$new" '.fix = $fix' <<<"$v")"; say red_story "$v" > "$TMP/story.md"
    for s in $(jq -r '.broken_by.closes // [] | .[]' <<<"$mp"); do
      trk reopen --iid "$s" >/dev/null && trk set-state --iid "$s" --state backlog >/dev/null &&
        trk comment --iid "$s" --body-file "$TMP/story.md" >/dev/null || exit 1
    done
    echo "lead: $short reverted in !$new, which merges when its pipeline succeeds" ;;

  *) echo "usage: lead.sh merge|rework|later|hardening|story|deliver|red-main --repo R ... (lead.sh --help)" >&2; exit 1 ;;
esac
