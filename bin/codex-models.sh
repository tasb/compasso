#!/usr/bin/env bash
# Check models.codex against the models this Codex account can use, and propose replacements.
#
#   codex-models.sh check --repo R [--catalog F] [--apply]
#
# The catalog comes from `codex debug models` (or F, a saved copy): the models this account may
# use, with the reasoning efforts each supports, best first. A role whose model is not in it, or
# whose effort that model does not support, is a problem. For each problem it proposes a model from
# the catalog by the role's tier, never a hard-coded id:
#   strong  (planner, security, approver, reviewer): the best model that is not a fast tier
#   standard (tester, builder, mutator):             the best model
#   fast    (shipper):                               the best fast-tier model, else the best model
# keeping the role's effort when that model supports it, else the model's default effort. When only
# the effort is unsupported, the model stays and the effort becomes the model's default.
# Fast tier is config.sh's rule (luna, mini, nano). --apply writes the proposals into models.codex.
# Exit: 0 every role's model is usable | 3 problems found (proposals printed; applied with --apply)
#       1 no catalog (Codex not installed or not logged in) or no usable model for a tier | 2 usage
set -u

BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CMD="${1:-}"; shift || true
REPO="." CATALOG="" APPLY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --catalog) CATALOG="$2"; shift 2 ;;
    --apply) APPLY=1; shift ;;
    *) echo "codex-models: unknown argument '$1'" >&2; exit 2 ;;
  esac
done
[ "$CMD" = check ] || { echo "usage: codex-models.sh check --repo R [--catalog F] [--apply]" >&2; exit 2; }
CFG="$REPO/.compasso/project.yaml"
[ -f "$CFG" ] || { echo "codex-models: no .compasso/project.yaml - run /compasso:setup" >&2; exit 2; }

if [ -n "$CATALOG" ]; then cat_json="$(cat "$CATALOG")"
else
  command -v codex >/dev/null || { echo "codex-models: Codex is not installed" >&2; exit 1; }
  cat_json="$(codex debug models 2>/dev/null)" || { echo "codex-models: 'codex debug models' failed - is Codex logged in? (codex login)" >&2; exit 1; }
fi
# usable models, best first: listed ones by priority, then hidden ones are ignored
models="$(jq -c '(.models // .) | map(select((.visibility // "list") == "list"))
  | sort_by(.priority // 999) | map({slug, efforts: [.supported_reasoning_levels[]?.effort], default: (.default_reasoning_level // "medium")})' <<<"$cat_json" 2>/dev/null)"
[ -n "$models" ] && [ "$(jq length <<<"$models")" -gt 0 ] || { echo "codex-models: the catalog lists no models" >&2; exit 1; }

fast() { case "$1" in *luna*|*mini*|*nano*) return 0 ;; esac; return 1; }
tier() { case "$1" in planner|security|approver|reviewer) echo strong ;; shipper) echo fast ;; *) echo standard ;; esac; }
pick() { # tier -> slug
  local s
  case "$1" in
    strong) for s in $(jq -r '.[].slug' <<<"$models"); do fast "$s" || { echo "$s"; return; }; done ;;
    fast) for s in $(jq -r '.[].slug' <<<"$models"); do fast "$s" && { echo "$s"; return; }; done; jq -r '.[0].slug' <<<"$models" ;;
    *) jq -r '.[0].slug' <<<"$models" ;;
  esac
}

problems=0 out=""
for role in $(yq -r '.models.codex | keys | .[]' "$CFG" 2>/dev/null); do
  m="$(R="$role" yq -r '.models.codex[strenv(R)].model // ""' "$CFG")"
  e="$(R="$role" yq -r '.models.codex[strenv(R)].effort // ""' "$CFG")"
  entry="$(jq -c --arg m "$m" '.[] | select(.slug == $m)' <<<"$models")"
  why=""
  if [ -z "$entry" ]; then why="'$m' is not available to this Codex account"
  elif [ -n "$e" ] && ! jq -e --arg e "$e" '.efforts | index($e)' <<<"$entry" >/dev/null; then why="'$m' does not support effort '$e'"; fi
  [ -n "$why" ] || continue
  problems=$((problems + 1))
  t="$(tier "$role")"
  if [ -n "$entry" ]; then s="$m"; else s="$(pick "$t")"; fi   # an unsupported effort keeps the model
  [ -n "$s" ] || { echo "codex-models: no usable $t model for $role in this account's catalog" >&2; exit 1; }
  ne="$(jq -r --arg s "$s" --arg e "$e" '.[] | select(.slug == $s) | if ($e != "" and (.efforts | index($e))) then $e else .default end' <<<"$models")"
  out="$out$role: $why -> $s (effort $ne, $t tier)"$'\n'
  if [ "$APPLY" -eq 1 ]; then
    R="$role" M="$s" E="$ne" yq -i '.models.codex[strenv(R)] = {"model": strenv(M), "effort": strenv(E)}' "$CFG" || exit 1
  fi
done

if [ "$problems" -eq 0 ]; then
  echo "codex-models: every role's model is available to this Codex account"
  exit 0
fi
printf '%s' "$out"
if [ "$APPLY" -eq 1 ]; then
  "$BIN/config.sh" validate --repo "$REPO" >/dev/null || { echo "codex-models: the applied models do not pass config validation" >&2; exit 1; }
  echo "codex-models: applied to models.codex in .compasso/project.yaml - re-run install-codex.sh --repo"
else
  echo "codex-models: run with --apply to use these (or edit models.codex yourself)"
fi
exit 3
