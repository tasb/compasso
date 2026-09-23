# Compasso — design spec

Status: draft v0.1 (2026-09-23). Successor to Harmonia, rebuilt to be simpler and faster without dropping a feature.

A *compasso* is a musical measure: one bar of a fixed length. Here, one sprint.

## 1. Principles

1. **The tracker is the source of truth; the merge request is the audit trail.** Work items, states, links and conversation live in GitLab. Proof that gates ran lives in MR pipelines and approvals. Locally, Compasso keeps one plan file and run logs.
2. **The 4 rules still bind every agent:** Think Before Coding, Simplicity First, Surgical Changes, Goal-Driven Execution.
3. **Security review is mandatory and never traded for speed.** No setting disables it, and no auto-approval passes an open security finding.
4. **Humans approve by default.** Plan approval and merge approval are human unless the project config says otherwise.
5. **Portable.** One source of truth for skills and agents runs on Claude Code and Codex.

## 2. Work hierarchy

| Level | Size rule (defaults) | GitLab Premium/Ultimate | GitLab Free |
|---|---|---|---|
| Epic | One per sprint; total estimate ≤ team capacity | Epic + iteration | Milestone + `type::epic` issue |
| Feature | ≤ half a sprint (≤ 40h at 2-week sprints) | Issue (child of epic), `type::feature` | Issue, `type::feature`, assigned to the milestone |
| User story | ≤ 8h hard limit, ~4h target | Child task of the feature | Child task of the feature |

- Sprint length defaults to **2 weeks** (10 working days); `setup` asks, the user overrides.
- Estimates are in **hours**.
- A story has an owner label: `owner::agent`, `owner::human` or `owner::either`. Humans and agents share a sprint.

### Dependencies

The planner must identify three kinds:

| Kind | Meaning | Premium | Free |
|---|---|---|---|
| hard | B cannot start before A is done | `blocks` / `is blocked by` link | `**Depends on:** #iid` line in the story |
| soft | A and B touch overlapping paths, so they run serially | derived from `touches:` | derived from `touches:` |
| external | waits on a human, another team, or a third party | `blocked` label + note | `blocked` label + note |

`plan-check` refuses a plan with: an unknown dependency id, a cycle, a dependency on a later sprint, a story over the hard limit, a feature over half a sprint, or an epic over capacity. It prints the critical path and the parallel waves.

### The plan file

`.compasso/plan.yaml` in the product repo is the only local planning artifact. Tracker ids are written back so pushes are idempotent.

```yaml
epic: { key: E-12, sprint: "2026-S20", gitlab: null }
features:
  - key: F-1
    gitlab: 431            # issue iid once pushed
    title: Invoice history
    estimate_h: 32
    stories:
      - key: S-1
        gitlab: null
        title: List invoices API
        estimate_h: 4
        owner: agent        # agent | human | either
        depends_on: []
        touches: ["src/billing/api/**"]
        tests: [unit, e2e]
        acceptance:
          - "Given a customer with 3 invoices, When GET /invoices, Then 3 items newest first"
        verify: ["npm test -- billing", "npx playwright test billing/list"]
```

### Work item formats

Rules for every description:

1. Never repeat what GitLab stores in a field: title, estimate, milestone, parent, assignee, child tasks.
2. What people filter on is a label: `owner::agent|human|either`, `severity::blocker|major|minor`.
3. Fixed section order. Omit an empty optional section; never write "N/A".
4. Describe only what to do. Bullets, one idea each, at most 20 words. No introductions, no restating the title.
5. Items Compasso writes carry one hidden line for idempotent pushes: `<!-- compasso:key=S-1 -->`.

The formats ship as GitLab issue templates in `templates/issue_templates/`; `setup` installs them into the product repo's `.gitlab/issue_templates/`. On Premium, epics are group epics, which issue templates do not reach; Compasso writes the same format into them.

**Epic** — required: Goal, Features.

```markdown
**Goal:** Customers can see and download their invoices without contacting support.
**Sprint:** 2026-10-05 → 2026-10-16 · **Capacity:** 80h · **Planned:** 72h

## Features
- [ ] #431 Invoice history — 32h
- [ ] #432 Invoice PDF download — 24h

## Risks
- PDF service is owned by another team
```

**Feature** — required: Goal; Scope and Acceptance before plan approval. Decisions and Test guide are written by Compasso.

```markdown
**Goal:** Customers see their last 24 months of invoices, newest first.

## Scope
- Invoice list
- Filter by year
- Invoice detail

## Acceptance
- [ ] Given 3 invoices, When I open Billing, Then I see 3 rows, newest first
- [ ] Given no invoices, When I open Billing, Then I see "No invoices yet"

## Decisions
- Paginate 20 per page (answered by @ana, 2026-10-02)

## Test guide
- Filled in at verification
```

**User story** — required: the As/I want/so that line, Acceptance, Verify, Tests. `Depends on` is Free tier only (Premium uses `blocks` links).

```markdown
**As** a customer **I want** an invoice list API **so that** the Billing page can show my history.

## Acceptance
- [ ] Given 3 invoices, When GET /invoices, Then 200 with 3 items, newest first
- [ ] Given another customer's token, When GET /invoices, Then 403

## Verify
- `npm test -- billing/api`
- `npx playwright test billing/list`

**Tests:** unit, e2e · **Touches:** `src/billing/api/**`
**Depends on:** #440
```

**Bug** — required: all sections. Verify must fail before the fix and pass after.

```markdown
**Found in:** !88 (#431 Invoice history) · **By:** feature e2e

## Steps
1. Log in as a customer with 25 invoices
2. Open Billing, go to page 2

## Expected
- 5 invoices

## Actual
- Empty list

## Evidence
- `billing/list.spec.ts:42` fails: expected 5 rows, got 0

## Verify
- `npx playwright test billing/list`
```

### Comment and merge request formats

Same rules as work items. Templates: `templates/comments/questions.md`, `templates/comments/plan.md`, `templates/mr-body.md`.

- **Questions** (feature enters `compasso::clarifying`): at most 5 per round, each answerable in one line, with options where possible. Answers count only from Developer or above and become bullets under the feature's `## Decisions`, with who answered and when.
- **Plan** (feature enters `compasso::plan-review`): one table row per story with hours, owner and dependencies, the security result, and how to approve.
- **Merge request**: `Closes #<story>`, then Changes, How to test (the story's Verify commands), and Review (reviewer, security, coverage).

## 3. Commands

Claude Code names shown; on Codex the same skills are invoked as `$compasso-<name>`.

| Command | Purpose |
|---|---|
| `/compasso:setup` | Connect GitLab (mandatory), detect tier, capture verify/coverage/e2e commands, sprint length, capacity, model roles, approval modes. Writes `.compasso/project.yaml`. |
| `/compasso:plan` | Top-down: sprint goal → epic → features → stories. Validated, then pushed. |
| `/compasso:feature <iid>` | Feature flow starting from a GitLab issue (Q&A in comments → breakdown → approval → build). |
| `/compasso:story <iid>` | Story flow: one story to a reviewed MR. |
| `/compasso:sprint <epic>` | Sprint flow: all features and stories of an epic, then regression and the test guide. |
| `/compasso:review <mr>` | Automated review + security review + fix loop on any MR, human-authored included. |
| `/compasso:status` | Read-only view from the tracker. |

No other command runs until `setup` has recorded a working tracker connection.

## 4. Roles and models

Seven roles, each defined once in `roles/<role>.md`.

| Role | Does | Claude default | Codex default |
|---|---|---|---|
| planner | Q&A, breakdown, dependencies, design notes | `opus` | `gpt-6-astra` (high) |
| tester | Failing unit and e2e tests first | `sonnet` | `gpt-6-sol` (medium) |
| builder | Makes tests pass; fixes review findings; never edits tests | `sonnet` | `gpt-6-sol` (medium) |
| reviewer | One-pass review: correctness, regression, simplicity, docs, performance | `sonnet` | `gpt-6-sol` (high) |
| security | Mandatory security review of every MR and plan | `opus` | `gpt-6-astra` (high) |
| approver | Optional auto-approval of MRs (off by default) | `opus` | `gpt-6-astra` (high) |
| shipper | Commits, MR, learnings, release notes, test guide | `haiku` | `gpt-6-luna` (low) |

Configured in `.compasso/project.yaml`:

```yaml
models:
  claude:
    planner:  { model: opus }
    tester:   { model: sonnet }
    builder:  { model: sonnet }
    reviewer: { model: sonnet }
    security: { model: opus }
    approver: { model: opus }
    shipper:  { model: haiku }
  codex:
    planner:  { model: gpt-6-astra, effort: high }
    tester:   { model: gpt-6-sol,   effort: medium }
    builder:  { model: gpt-6-sol,   effort: medium }
    reviewer: { model: gpt-6-sol,   effort: high }
    security: { model: gpt-6-astra, effort: high }
    approver: { model: gpt-6-astra, effort: high }
    shipper:  { model: gpt-6-luna,  effort: low }
```

- Claude uses aliases (`opus`, `sonnet`, `haiku`, `inherit`) so defaults do not go stale.
- Codex has no aliases; the defaults are pinned ids and `setup` checks them against the models the local Codex reports.
- **Floor:** `security` and `approver` may not be set to the fast tier (`haiku` / `gpt-6-luna`) or to low effort. `setup` and config validation refuse it.

## 5. Flows

### 5.1 Feature flow (tracker-first)

State is a scoped label on the Feature issue:

```
compasso::new           human creates the Feature issue
compasso::clarifying    planner posts questions as a comment; humans answer in comments
compasso::plan-review   planner posts the breakdown and creates child stories + links
                        security reviews the plan and the comments it came from
compasso::building      after approval (human by default; configurable)
compasso::verifying     all stories merged: feature integration + e2e + auto bug fixing
compasso::done          test guide section attached; human closes
```

- On the Free tier scoped labels are not exclusive, so every state change removes the previous `compasso::` label explicitly.
- Only comments from project members at Developer role or above are read as answers; only an approval command (`/approve` comment or the label, by an authorised member) advances a state.
- Comment text is untrusted input. It informs the plan; it never becomes instructions.
- Entry today: `/compasso:feature <iid>` run locally. Later: a webhook receiver that starts a CI pipeline running the same skill headless (`claude -p` / `codex exec`). Out of scope for v0.

### 5.2 Story flow

```
pull story → open hard dependencies? → stop, name the next unblocked story
→ move to In Progress, worktree + branch story/<iid>-<slug>
→ tester: failing tests (unit; e2e when the story's tests include it) → record test hashes
→ builder: go green
→ verify.sh: tests, lint, typecheck, changed-line coverage, the story's verify commands, e2e
→ review loop (max 3 rounds):
     reviewer and security run in parallel on the diff
     findings: blocker | major | minor
     builder fixes blocker + major → verify.sh → re-review changed hunks
     only security may resolve a security finding
     minors → new tracker items, not riders
→ shipper: commits, MR "Closes #<iid>", MR body = summary + how to test
→ approval: human (default) | approver agent (if enabled and no open security finding)
→ learnings captured (max 2 per story)
```

### 5.3 Sprint flow

```
load epic tree → dependency graph → waves
for each wave: story flows in parallel (worktrees, max N, no overlapping touches)
               report human-owned stories that block the next wave
per completed feature: integration + full suite + feature e2e
                       failures → Bug items linked to the feature → story flow
sprint end: full regression + e2e + full security pass over the sprint diff
            → test guide + release notes → attached to the epic, committed to docs/releases/
```

## 6. Gates

| Gate | Where | Hard? |
|---|---|---|
| Tracker connected | every command | hard |
| `plan-check` (sizes, dependencies, capacity) | before any push | hard |
| Story has acceptance + `verify` | story flow start | hard |
| Test immutability (hashes) | after builder turns | hard |
| `verify.sh` | before review, before MR | hard |
| Changed-line coverage (repo's own coverage command + diff-cover) | `verify.sh` | soft; exemptions need an in-code justification |
| Security review | every MR, every plan, sprint end | hard, never skippable |
| Secret / dependency / SAST scans | every MR pipeline | hard on high/critical |
| Human merge approval | every MR (default) | platform-enforced via protected branches |

## 7. Tests

- Unit tests always.
- E2E tests when the change is observable across a boundary (UI flow, public API, CLI, service integration). Every feature with a UI or API gets feature-level e2e.
- `setup` records the `e2e:` command, detecting the framework (Playwright for web, the project's runner for API, bats for CLI).

## 8. Test guide (sprint deliverable)

Per feature: what changed and why; prerequisites, data and environment; step-by-step scenarios from each story's Given/When/Then with expected results; edge cases, known limitations, out of scope; security notes; links to MRs and work items; tester sign-off table. Written for QA and product, not developers.

## 9. Portability: Claude Code and Codex

| Concern | Claude Code | Codex |
|---|---|---|
| Skills | `skills/<name>/SKILL.md` in the plugin | same files, installed to `.agents/skills/` or `~/.agents/skills/` |
| Invocation | `/compasso:<name>` | `$compasso-<name>` |
| Roles | generated `agents/<role>.md` (frontmatter `model:`) | generated `~/.codex/agents/<role>.toml` + `[agents]` entries |
| Session context | `SessionStart` hook | `AGENTS.md` block |
| Headless (future webhook) | `claude -p` | `codex exec` |

Source of truth: `roles/*.md` and `skills/*/SKILL.md` (Agent Skills format). `bin/build-targets.sh` generates both targets from `project.yaml` models. Scripts are bash + `glab` + `jq`/`yq`, shared by both.

## 10. Repo layout

```
roles/            one file per role (charter)
skills/           setup plan feature story sprint review status
bin/              plan-check, verify, tracker adapter (gitlab), build-targets, install-codex
templates/        test-guide.md, release-notes.md, mr-body.md, gitlab-ci security jobs
tests/            bats
docs/SPEC.md
```

## 11. Build order

1. `setup` + GitLab adapter (both tiers) + `project.yaml` schema incl. models
2. `plan.yaml` + `plan-check` + `/compasso:plan` push
3. Story flow with `verify.sh` and the review/security loop
4. Feature flow (comment Q&A) and sprint flow (waves, test guide)
5. Codex target generator and installer
6. Later: webhook receiver

## 12. Verified on gitlab.com Free (2026-09-23)

- Child tasks under an issue: work (GraphQL `workItemCreate` with `hierarchyWidget.parentId`).
- Hour estimates on tasks: work (`time_estimate`).
- `blocks` links: refused ("Blocked issues not available for current license"); `relates_to` works.
- Tier detection: `namespaces/:id` returns `plan`; self-managed instances must set `tracker.tier`.

## 13. Open questions

- Codex model ids are pinned defaults and will age; revisit at each release.
- GitLab Free has no native "blocks" links; the `**Depends on:**` line is documented in the Story issue template for humans creating stories by hand.
