#!/usr/bin/env bats
load helper

setup() {
  setup_repo
  PLAN="$REPO/.compasso/plan.yaml"
  cp "$ROOT/tests/fixtures/plan.yaml" "$PLAN"
  export FAKE_GL="$BATS_TEST_TMPDIR/gl"
  export PATH="$ROOT/tests/fake:$PATH"
}
push() { "$ROOT/bin/tracker/gitlab.sh" push-plan --repo "$REPO"; }
calls() { grep -c -- "$1" "$FAKE_GL/calls.log" || true; }
iid_of() { K="$1" yq -r '(.features[] | select(.key == strenv(K)) | .gitlab), (.blockers[] | select(.key == strenv(K)) | .gitlab), (.features[].stories[] | select(.key == strenv(K)) | .gitlab)' "$PLAN"; }

@test "a plan that fails plan-check is not pushed" {
  yq -i '.features[0].stories[0].estimate_h = 9' "$PLAN"
  run push
  [ "$status" -eq 1 ]
  [[ "$output" == *"does not pass plan-check"* ]] || false
  [ ! -e "$FAKE_GL/calls.log" ]
}

@test "creates a milestone, features, stories as tasks and the epic, and writes every id back" {
  run push
  [ "$status" -eq 0 ]
  [ "$(calls 'POST projects/acme%2Fapp/milestones')" -eq 1 ]
  [ "$(calls 'issue_type=issue labels=type::feature')" -eq 2 ]
  [ "$(calls 'issue_type=task labels=owner::')" -eq 4 ]
  [ "$(calls 'labels=type::epic')" -eq 1 ]
  [ "$(yq -r .epic.gitlab.milestone "$PLAN")" = 501 ]
  [ "$(yq -r .epic.gitlab.issue "$PLAN")" = 8 ]
  for k in F-1 F-2 B-1 S-1 S-2 S-3 S-4; do [ "$(iid_of $k)" != null ]; done
}

@test "stories are created after the stories they depend on" {
  push >/dev/null
  [ "$(iid_of S-1)" -lt "$(iid_of S-2)" ]
  [ "$(iid_of S-1)" -lt "$(iid_of S-3)" ]
}

@test "each story is attached to its own feature" {
  push >/dev/null
  [ "$(calls 'query=mutation')" -eq 4 ]
  grep -q "WorkItem/$((1000 + $(iid_of S-4)))" "$FAKE_GL/calls.log"
}

@test "estimates are set in hours, fractions as minutes" {
  yq -i '.features[0].stories[0].estimate_h = 4.5' "$PLAN"
  push >/dev/null
  grep -q "issues/$(iid_of S-1)/time_estimate?duration=4h30m" "$FAKE_GL/calls.log"
  grep -q "issues/$(iid_of S-4)/time_estimate?duration=8h$" "$FAKE_GL/calls.log"
}

@test "owner and blocked become labels" {
  push >/dev/null
  [ "$(cat "$FAKE_GL/labels/$(iid_of S-2)")" = "owner::human" ]
  [ "$(cat "$FAKE_GL/labels/$(iid_of S-4)")" = "owner::agent,blocked" ]
}

@test "the story description follows the approved format, with Depends on on Free" {
  push >/dev/null
  cat > "$BATS_TEST_TMPDIR/want" <<EOF
**As** a customer **I want** an invoice list page **so that** I can find an invoice quickly.

## Acceptance
- [ ] Given 3 invoices, When I open Billing, Then I see 3 rows

## Verify
- \`npx playwright test billing/list\`

**Tests:** unit, e2e\\
**Touches:** \`src/billing/ui/**\`\\
**Depends on:** #$(iid_of S-1)

<!-- compasso:key=S-2 -->
EOF
  diff "$BATS_TEST_TMPDIR/want" "$FAKE_GL/desc/$(iid_of S-2).md"
}

@test "optional story lines appear only when set" {
  push >/dev/null
  grep -qx '\*\*Coverage:\*\* 90%' "$FAKE_GL/desc/$(iid_of S-3).md"
  grep -qx '\*\*Depends on:\*\* #12\\' "$FAKE_GL/desc/$(iid_of S-4).md"
  grep -qx "\*\*Blocked by:\*\* #$(iid_of B-1)" "$FAKE_GL/desc/$(iid_of S-4).md"
  [ "$(grep -c 'Coverage\|Blocked\|Depends' "$FAKE_GL/desc/$(iid_of S-1).md")" -eq 0 ]
}

@test "the feature and epic descriptions follow the approved format" {
  push >/dev/null
  cat > "$BATS_TEST_TMPDIR/feature" <<'EOF'
**Goal:** Customers see their last 24 months of invoices, newest first.

## Scope
- Invoice list
- Filter by year

## Acceptance
- [ ] Given 3 invoices, When I open Billing, Then I see 3 rows, newest first

<!-- compasso:key=F-1 -->
EOF
  diff "$BATS_TEST_TMPDIR/feature" "$FAKE_GL/desc/$(iid_of F-1).md"
  cat > "$BATS_TEST_TMPDIR/epic" <<EOF
**Goal:** Customers can see and download their invoices without contacting support.\\
**Sprint:** 2026-10-05 → 2026-10-16\\
**Capacity:** 80h\\
**Planned:** 22h

## Features
- [ ] #$(iid_of F-1) Invoice history — 14h
- [ ] #$(iid_of F-2) Invoice PDF download — 8h

## Risks
- PDF service is owned by another team

<!-- compasso:key=E-1 -->
EOF
  diff "$BATS_TEST_TMPDIR/epic" "$FAKE_GL/desc/$(yq -r .epic.gitlab.issue "$PLAN").md"
}

@test "Premium is pushed the Free way until its features can be tested" {
  export FAKE_GL_PLAN=premium
  push >/dev/null
  grep -qx "\*\*Depends on:\*\* #$(iid_of S-1)" "$FAKE_GL/desc/$(iid_of S-2).md"
  [ "$(calls '/links')" -eq 0 ]
}

@test "a second push updates the same items instead of creating new ones" {
  push >/dev/null
  : > "$FAKE_GL/calls.log"
  yq -i '.features[0].stories[1].owner = "agent"' "$PLAN"
  run push
  [ "$status" -eq 0 ]
  [ "$(calls 'POST projects/acme%2Fapp/issues ')" -eq 0 ]
  [ "$(calls 'POST projects/acme%2Fapp/milestones')" -eq 0 ]
  [ "$(calls 'query=mutation')" -eq 0 ]
  grep -q "PUT projects/acme%2Fapp/issues/$(iid_of S-2) remove_labels=owner::human,owner::either,blocked" "$FAKE_GL/calls.log"
  grep -q "PUT projects/acme%2Fapp/issues/$(iid_of S-4) remove_labels=owner::human,owner::either$" "$FAKE_GL/calls.log"
}

@test "a failed push keeps the ids already written, so the re-run resumes" {
  export FAKE_GL_FAIL="POST projects/*/time_estimate?duration=6h"
  run push
  [ "$status" -eq 1 ]
  [[ "$output" == *"could not set the estimate of story S-2"* ]] || false
  [ "$(iid_of S-1)" != null ]
  [ "$(iid_of S-2)" != null ]
  unset FAKE_GL_FAIL
  : > "$FAKE_GL/calls.log"
  run push
  [ "$status" -eq 0 ]
  [ "$(calls 'issue_type=task')" -eq 1 ]
  [ "$(iid_of S-3)" != null ]
}

@test "a story whose attach step failed is not created twice on the re-run" {
  export FAKE_GL_FAIL="POST graphql"
  run push
  [ "$status" -eq 1 ]
  [[ "$output" == *"could not attach story S-1"* ]] || false
  [ "$(iid_of S-1)" != null ]
  unset FAKE_GL_FAIL
  : > "$FAKE_GL/calls.log"
  push >/dev/null
  [ "$(calls 'issue_type=task')" -eq 3 ]
  grep -q "WorkItem/$((1000 + $(iid_of S-1)))" "$FAKE_GL/calls.log"
}

@test "a story already under its feature is not attached again" {
  push >/dev/null
  [ "$(cat "$FAKE_GL/parent/$((1000 + $(iid_of S-3)))")" = "$((1000 + $(iid_of F-1)))" ]
  run push
  [ "$status" -eq 0 ]
  [[ "$output" != *"could not attach"* ]] || false
}

@test "the epic is titled with the short sprint name and the goal" {
  push >/dev/null
  grep -q "labels=type::epic" "$FAKE_GL/calls.log"
  grep "labels=type::epic" "$FAKE_GL/calls.log" | grep -q "title=S20: Customers can see and download their invoices without contacting support. "
}

@test "a blocker is an urgent task assigned to a person, with numbered steps and the stories it holds up" {
  push >/dev/null
  grep "issue_type=task labels=type::blocker,priority::urgent" "$FAKE_GL/calls.log" | grep -q "assignee_ids=77"
  cat > "$BATS_TEST_TMPDIR/blocker" <<EOF2
**Needed for:** #$(iid_of S-4) PDF endpoint

## Steps
1. Ask the PDF team for API credentials for the invoices service
2. Store them as the masked CI variable PDF_API_KEY
3. Close this task

<!-- compasso:key=B-1 -->
EOF2
  diff "$BATS_TEST_TMPDIR/blocker" "$FAKE_GL/desc/$(iid_of B-1).md"
}

@test "a blocker is created before the story that links to it" {
  push >/dev/null
  [ "$(iid_of B-1)" -lt "$(iid_of S-4)" ]
}

@test "a blocker assigned to an unknown user stops the push" {
  yq -i '.blockers[0].assignee = "ghost"' "$PLAN"
  run push
  [ "$status" -eq 1 ]
  [[ "$output" == *"no GitLab user 'ghost'"* ]] || false
  [ "$(calls 'labels=type::blocker')" -eq 0 ]
}

@test "a blocker assigned to someone outside the project stops the push" {
  yq -i '.blockers[0].assignee = "outsider"' "$PLAN"
  run push
  [ "$status" -eq 1 ]
  [[ "$output" == *"outsider is not a member of acme/app"* ]] || false
}

@test "milestone and epic are named after the sprint number" {
  push >/dev/null
  grep -q "POST projects/acme%2Fapp/milestones title=S20 start_date=2026-10-05 due_date=2026-10-16" "$FAKE_GL/calls.log"
}

@test "the push creates Compasso's labels before applying them" {
  push >/dev/null
  first_label="$(grep -n 'POST projects/acme%2Fapp/labels name=type::blocker' "$FAKE_GL/calls.log" | cut -d: -f1)"
  first_use="$(grep -n 'labels=type::blocker' "$FAKE_GL/calls.log" | head -1 | cut -d: -f1)"
  [ -n "$first_label" ] && [ "$first_label" -lt "$first_use" ]
}

@test "a feature's coverage goes on its own line under the goal" {
  yq -i '.features[0].coverage = 85' "$PLAN"
  push >/dev/null
  [ "$(head -2 "$FAKE_GL/desc/$(iid_of F-1).md")" = $'**Goal:** Customers see their last 24 months of invoices, newest first.\\\n**Coverage:** 85%' ]
}
