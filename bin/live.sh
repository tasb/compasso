#!/usr/bin/env bash
# The live hardening checks, against a running test environment, each in its Docker image.
#
#   live.sh run   zap|fuzz|perf|a11y --repo R --confirm-url URL --out DIR
#   live.sh parse zap|fuzz|perf|a11y --repo R --out DIR     the tool's report -> DIR/<check>.result.json
#
# The target is harden.environment.url in .compasso/project.yaml, and --confirm-url
# must repeat it: a person confirms, every run, which environment is hit. Never point
# it at production. API fuzzing sends only reading requests (GET, HEAD) unless the
# environment is marked disposable. From inside Docker, localhost is reached as
# host.docker.internal.
#   zap   ZAP baseline: passive only, never attacks. Gaps: medium and high alerts.
#   fuzz  Schemathesis on the OpenAPI schema. Gaps: operations with failing checks.
#   perf  k6 smoke test on the configured GET endpoints. Gaps: limits exceeded.
#   a11y  axe-core in the official Playwright image on the configured pages. Gaps: serious and critical.
# Exit: 0 the check ran (findings are results, not errors) | 1 it could not run | 2 usage
set -u

BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CMD="${1:-}"; CHECK="${2:-}"; shift 2 2>/dev/null || true
REPO="." CONFIRM="" OUT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --confirm-url) CONFIRM="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    *) echo "live: unknown argument '$1'" >&2; exit 2 ;;
  esac
done
case "$CMD:$CHECK" in run:zap|run:fuzz|run:perf|run:a11y|parse:zap|parse:fuzz|parse:perf|parse:a11y) ;;
  *) echo "usage: live.sh run|parse zap|fuzz|perf|a11y --repo R [--confirm-url URL] --out DIR" >&2; exit 2 ;; esac
[ -n "$OUT" ] || { echo "live: --out is required" >&2; exit 2; }
"$BIN/config.sh" validate --repo "$REPO" >/dev/null || exit 1
cfg() { "$BIN/config.sh" get --repo "$REPO" "$1"; }
mkdir -p "$OUT" || exit 1
RESULT="$OUT/$CHECK.result.json"
not_run() { jq -n --arg c "$CHECK" --arg t "$(title)" --arg r "$1" '{check: $c, title: $t, ran: false, reason: $r}' > "$RESULT"; echo "live: $CHECK not run - $1"; exit 1; }
title() { case "$CHECK" in zap) echo "Security scan (ZAP)" ;; fuzz) echo "API fuzzing" ;; perf) echo "Performance" ;; a11y) echo "Accessibility" ;; esac; }

# ---------- parse: the tool's report -> the common result ----------
parse() {
  case "$CHECK" in
    zap)
      [ -f "$OUT/zap.json" ] || not_run "ZAP wrote no report"
      jq '[.site[]?.alerts[]?] as $a
        | def risk: {"3": "high", "2": "medium", "1": "low", "0": "informational"}[.riskcode | tostring];
        {check: "zap", title: "Security scan (ZAP)", ran: true,
         counts: (["high", "medium", "low", "informational"] | map(. as $r | {label: $r, n: ([$a[] | select(risk == $r)] | length)})),
         gaps: [$a[] | select((.riskcode | tonumber) >= 2)
                | {summary: "\(.name) (\(risk), \((.instances // []) | length) places)"}]}' "$OUT/zap.json" > "$RESULT" ;;
    fuzz)
      [ -f "$OUT/junit.xml" ] || not_run "Schemathesis wrote no report"
      command -v xmllint >/dev/null || not_run "xmllint is not installed, so the Schemathesis report cannot be read"
      cases="$(xmllint --xpath 'count(//testcase)' "$OUT/junit.xml" 2>/dev/null || echo 0)"
      failed="$(xmllint --xpath '//testcase[failure or error]/@name' "$OUT/junit.xml" 2>/dev/null | sed -E 's/ name="([^"]*)"/\1\n/g' | sed '/^$/d')"
      jq -n --argjson cases "${cases%.*}" --arg failed "$failed" '
        ($failed | split("\n") | map(select(. != ""))) as $f
        | {check: "fuzz", title: "API fuzzing", ran: true,
           counts: [{label: "operations", n: $cases}, {label: "failing", n: ($f | length)}],
           gaps: [$f[] | {summary: "\(.) fails on generated input"}]}' > "$RESULT" ;;
    perf)
      [ -f "$OUT/k6.json" ] || not_run "k6 wrote no summary"
      jq --argjson p95 "$(cfg .harden.limits.p95_ms)" --argjson er "$(cfg .harden.limits.error_rate)" '
        (.metrics.http_req_duration["p(95)"] // 0) as $d | (.metrics.http_req_failed.value // .metrics.http_req_failed.rate // 0) as $f
        | {check: "perf", title: "Performance", ran: true,
           counts: [{label: "requests", n: (.metrics.http_reqs.count // 0)}, {label: "ms at p95", n: ($d | round)},
                    {label: "% failed", n: ($f * 1000 | round / 10)}],
           gaps: ([if $d > $p95 then {summary: "95% of requests take up to \($d | round) ms, over the \($p95) ms limit"} else empty end]
                + [if $f > $er then {summary: "\($f * 1000 | round / 10)% of requests fail, over the \($er * 100)% limit"} else empty end])}' \
        "$OUT/k6.json" > "$RESULT" ;;
    a11y)
      [ -f "$OUT/a11y.json" ] || not_run "the accessibility scan wrote no report"
      jq '[.[] | .page as $p | .violations[] | . + {page: $p}] as $v
        | {check: "a11y", title: "Accessibility", ran: true,
           counts: [{label: "pages", n: length},
                    {label: "serious or critical", n: ([$v[] | select(.impact == "serious" or .impact == "critical")] | length)},
                    {label: "moderate or minor", n: ([$v[] | select(.impact == "moderate" or .impact == "minor")] | length)}],
           gaps: [$v[] | select(.impact == "serious" or .impact == "critical")
                  | {summary: "\(.page): \(.help) (\(.impact), \(.nodes) elements)"}]}' "$OUT/a11y.json" > "$RESULT" ;;
  esac
  jq -r '"live: \(.title): " + ([.counts[] | "\(.n) \(.label)"] | join(" · "))' "$RESULT"
}

if [ "$CMD" = parse ]; then parse; exit 0; fi

# ---------- run ----------
URL="$(cfg .harden.environment.url)"
[ -n "$URL" ] || { echo "live: set harden.environment.url to a running test environment first" >&2; exit 1; }
[ "$CONFIRM" = "$URL" ] || { echo "live: --confirm-url must repeat harden.environment.url ($URL): confirm which environment is hit" >&2; exit 1; }
command -v docker >/dev/null && docker info >/dev/null 2>&1 || { echo "live: Docker is not running; start it and try again" >&2; exit 1; }
CURL="$(printf '%s' "$URL" | sed -E 's#^(https?://)(localhost|127\.0\.0\.1)([:/]|$)#\1host.docker.internal\3#')"
IMAGE="$(cfg ".harden.images.$CHECK")"
mkdir -p "$OUT" && chmod 777 "$OUT"

case "$CHECK" in
  zap)
    docker run --rm -v "$OUT:/zap/wrk:rw" "$IMAGE" zap-baseline.py -t "$CURL" -J zap.json -I > "$OUT/zap.log" 2>&1 ;;
  fuzz)
    schema="$(cfg .harden.environment.openapi)"
    [ -n "$schema" ] || { echo "live: set harden.environment.openapi to fuzz the API" >&2; exit 1; }
    mount=""
    case "$schema" in
      http://*|https://*) schema="$(printf '%s' "$schema" | sed -E 's#^(https?://)(localhost|127\.0\.0\.1)([:/]|$)#\1host.docker.internal\3#')" ;;
      *) [ -f "$REPO/$schema" ] || { echo "live: no schema at $schema" >&2; exit 1; }
         mount="-v $(cd "$REPO" && pwd):/repo:ro"; schema="/repo/$schema" ;;
    esac
    methods="--include-method GET --include-method HEAD"
    [ "$(cfg .harden.environment.disposable)" = true ] && methods=""
    # shellcheck disable=SC2086
    docker run --rm -v "$OUT:/out" $mount "$IMAGE" run "$schema" --url "$CURL" $methods \
      --report junit --report-junit-path /out/junit.xml > "$OUT/fuzz.log" 2>&1 ;;
  perf)
    endpoints="$(yq -o=json '.harden.environment.endpoints // []' "$REPO/.compasso/project.yaml")"
    [ "$(jq length <<<"$endpoints")" -gt 0 ] || { echo "live: set harden.environment.endpoints for the performance test" >&2; exit 1; }
    jq -rn --arg base "$CURL" --argjson e "$endpoints" --argjson p95 "$(cfg .harden.limits.p95_ms)" --argjson er "$(cfg .harden.limits.error_rate)" '
      "import http from \"k6/http\";",
      "export const options = { vus: 5, duration: \"30s\", thresholds: { http_req_duration: [\"p(95)<\($p95)\"], http_req_failed: [\"rate<\($er)\"] } };",
      "const paths = \($e | tojson);",
      "export default function () { for (const p of paths) http.get(\($base | tojson) + p); }"' > "$OUT/k6.js"
    docker run --rm -v "$OUT:/out" "$IMAGE" run --quiet --summary-export=/out/k6.json /out/k6.js > "$OUT/perf.log" 2>&1 ;;
  a11y)
    pages="$(yq -o=json '.harden.environment.pages // []' "$REPO/.compasso/project.yaml")"
    [ "$(jq length <<<"$pages")" -gt 0 ] || { echo "live: set harden.environment.pages for the accessibility check" >&2; exit 1; }
    version="$(printf '%s' "$IMAGE" | sed -nE 's#.*:v([0-9]+\.[0-9]+\.[0-9]+).*#\1#p')"
    [ -n "$version" ] || { echo "live: harden.images.a11y must be a Playwright image tagged vX.Y.Z" >&2; exit 1; }
    cat > "$OUT/a11y.mjs" <<'EOF'
import { chromium } from 'playwright';
import AxeBuilder from '@axe-core/playwright';
import { writeFileSync } from 'node:fs';
const [base, ...pages] = process.argv.slice(2);
const browser = await chromium.launch();
const out = [];
for (const page of pages) {
  const p = await browser.newPage();
  await p.goto(base + page, { waitUntil: 'networkidle' });
  const r = await new AxeBuilder({ page: p }).withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa', 'wcag22aa']).analyze();
  out.push({ page, violations: r.violations.map((v) => ({ id: v.id, impact: v.impact, help: v.help, nodes: v.nodes.length })) });
  await p.close();
}
await browser.close();
writeFileSync('/out/a11y.json', JSON.stringify(out, null, 2));
EOF
    # shellcheck disable=SC2046
    docker run --rm --ipc=host -v "$OUT:/out" -w /tmp/a11y "$IMAGE" bash -c \
      "npm init -y >/dev/null && npm i --silent playwright@$version @axe-core/playwright >/dev/null && cp /out/a11y.mjs . && node a11y.mjs \"\$0\" \"\$@\"" \
      "$CURL" $(jq -r '.[]' <<<"$pages") > "$OUT/a11y.log" 2>&1 ;;
esac
parse
