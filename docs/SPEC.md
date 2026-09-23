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
| Epic | One per sprint; total estimate ≤ team capacity | Milestone + `type::epic` issue (native epic + iteration later) | Milestone + `type::epic` issue |
| Feature | ≤ half a sprint (≤ 40h at 2-week sprints) | Issue (child of epic), `type::feature` | Issue, `type::feature`, assigned to the milestone |
| User story | ≤ 8h hard limit, ~4h target | Child task of the feature | Child task of the feature |

Premium features are designed but switched off: every tier is pushed the Free way until the Premium path can be tested on a Premium project. The Premium columns below describe that future path.

- Sprint length defaults to **2 weeks** (10 working days); `setup` asks, the user overrides.
- Estimates are in **hours**.
- A story has an owner label: `owner::agent`, `owner::human` or `owner::either`. Humans and agents share a sprint.

### Dependencies

The planner must identify three kinds:

| Kind | Meaning | Premium | Free |
|---|---|---|---|
| hard | B cannot start before A is done | `blocks` / `is blocked by` link | `**Depends on:** #iid` line in the story |
| soft | A and B touch overlapping paths, so they run serially | derived from `touches:` | derived from `touches:` |
| external | waits on something outside the plan | a blocker task + `**Blocked by:** #iid` + `blocked` label | same |

`plan-check` refuses a plan with: an unknown dependency id, a cycle, a dependency on a later sprint, a story over the hard limit, a feature over half a sprint, or an epic over capacity. It prints the critical path and the parallel waves.

### The plan file

`.compasso/plan.yaml` in the product repo is the only local planning artifact; the template is `templates/plan.yaml`. Feature hours are the sum of their stories. `gitlab` fields are written by the push, after each item, so a re-run updates instead of duplicating and a failed run resumes.

```yaml
epic:
  key: E-1
  goal: Customers can see and download their invoices without contacting support.
  sprint: { number: 20, start: "2026-10-05", end: "2026-10-16" }   # sprint 20 = "S20"
  coverage: 85                          # optional
  risks: [PDF service is owned by another team]
  gitlab: { milestone: 501, issue: 12 }
blockers:
  - key: B-1
    title: PDF service credentials
    assignee: ana                       # GitLab username of a project member; required
    steps:
      - Ask the PDF team for API credentials for the invoices service
      - Store them as the masked CI variable PDF_API_KEY
    gitlab: 9
features:
  - key: F-1
    title: Invoice history
    goal: Customers see their last 24 months of invoices, newest first.
    scope: [Invoice list, Filter by year]
    acceptance: ["Given 3 invoices, When I open Billing, Then I see 3 rows, newest first"]
    decisions: []
    gitlab: 6
    stories:
      - key: S-1
        title: Invoice list API
        as: a customer
        want: an invoice list API
        so_that: the Billing page can show my history
        acceptance: ["Given 3 invoices, When GET /invoices, Then 200 with 3 items, newest first"]
        verify: ["npm test -- billing/api"]
        tests: [unit, e2e]
        touches: ["src/billing/api/**"]
        depends_on: []                  # story keys, or "#iid" for existing items
        owner: agent                    # agent | human | either
        estimate_h: 4
        blocked_by: [B-1]               # blockers this story waits for
        coverage: 90                    # optional
        gitlab: 8
```

### Pushing to GitLab

`gitlab.sh push-plan` runs only on a plan that passes `plan-check`, then writes, in this order:

1. The milestone `S<number>` for the sprint (found by title, else created with the sprint dates).
2. Each feature as an issue labelled `type::feature`.
3. Each blocker as a task labelled `type::blocker` and `priority::urgent`, assigned to its person, who must be a project member.
4. Each story as a task, in dependency order, attached to its feature, with its estimate in hours, its `owner::` label, and `blocked` when it has blockers. Dependencies are the `**Depends on:**` line.
5. The blockers again, now listing the stories they hold up.
6. The epic as an issue labelled `type::epic` and titled `S<number>: <goal>`, last, because it lists the features with their hours.

Premium (native group epics, iterations, `blocks` links) is commented out in `gitlab.sh` and not available: it needs a Premium project to build and test against.

### Work item formats

Rules for every description:

1. Never repeat what GitLab stores in a field: title, estimate, milestone, parent, assignee, child tasks.
2. What people filter on is a label: `owner::agent|human|either`, `severity::blocker|major|minor`.
3. Fixed section order. Omit an empty optional section; never write "N/A".
4. Describe only what to do. Bullets, one idea each, at most 20 words. No introductions, no restating the title.
   Key lines (`**Goal:**`, `**Tests:**`, `**Depends on:**`...) each sit on their own line: Compasso ends each one but the last with `\` (a line break in GitLab); the issue templates separate them with blank lines so an optional one can be deleted cleanly.
5. Items Compasso writes carry one hidden line for idempotent pushes: `<!-- compasso:key=S-1 -->`.

The formats ship as GitLab issue templates in `templates/issue_templates/`; `setup` installs them into the product repo's `.gitlab/issue_templates/`.

**Epic** — required: Goal, Features.

```markdown
**Goal:** Customers can see and download their invoices without contacting support.\
**Sprint:** 2026-10-05 → 2026-10-16\
**Capacity:** 80h\
**Planned:** 72h

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

**User story** — required: the As/I want/so that line, Acceptance, Verify, Tests. `Blocked by` links to the blocker tasks and, like `Coverage`, appears only when set.

```markdown
**As** a customer **I want** an invoice list API **so that** the Billing page can show my history.

## Acceptance
- [ ] Given 3 invoices, When GET /invoices, Then 200 with 3 items, newest first
- [ ] Given another customer's token, When GET /invoices, Then 403

## Verify
- `npm test -- billing/api`
- `npx playwright test billing/list`

**Tests:** unit, e2e\
**Touches:** `src/billing/api/**`\
**Depends on:** #440\
**Blocked by:** #452
```

**Blocker** — a task for one person, always assigned, labelled `type::blocker` and `priority::urgent`. Required: Steps.

```markdown
**Needed for:** #9 PDF endpoint

## Steps
1. Ask the PDF team for API credentials for the invoices service
2. Store them as the masked CI variable PDF_API_KEY
3. Close this task
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

Same rules as work items. Templates: `templates/comments/qa.md`, `templates/comments/plan.md`, `templates/mr-body.md`.

- **Questions and answers** (one per question round in the feature flow): each question with the answer given in the agent, who answered and when. The answers also become the feature's `## Decisions`.
- **Plan** (when the plan is approved): one table row per story with hours, owner and dependencies, the security result, and who approved it.
- **Merge request**: `Closes #<story>`, then Changes, How to test (the story's Verify commands), and Review (reviewer, security, coverage).

## 3. Commands

Claude Code names shown; on Codex the same skills are invoked as `$compasso-<name>`.

| Command | Purpose |
|---|---|
| `/compasso:setup` | Connect GitLab (mandatory), detect tier, capture verify, e2e and coverage commands, sprint length, capacity, model roles, approval modes. Writes `.compasso/project.yaml`. |
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

### 5.1 Feature flow (in the agent)

`/compasso:feature <iid>` for a Feature issue that exists, or `/compasso:feature "<idea>"` to create one. The conversation happens in the agent; GitLab gets the record.

```
read the feature and the code
→ questions in the chat: at most 5 per round, each answerable in one line, with options;
  at most 3 rounds, then plan and list open points as assumptions
→ answers become ## Decisions bullets (who, when) and one Questions and answers comment per round
→ add the feature to the current sprint's epic (capacity checked) and split it into stories and blockers
→ plan-check → mandatory security review of the plan
→ approval in the chat (approvals.plan: human), or automatic when security found nothing (auto)
→ push the stories; a Plan comment records the breakdown, the security result and who approved
→ compasso::building: story flows in dependency waves
→ compasso::verifying: feature e2e + full suite; each failure becomes a Bug fixed through the story flow
→ compasso::done: the feature's section of the test guide is written
```

States on a feature: `compasso::new` (not planned yet) → `compasso::building` → `compasso::verifying` → `compasso::done`. On the Free tier scoped labels are not exclusive, so every state change removes the previous `compasso::` label explicitly.

### 5.2 Story flow

`/compasso:story <iid>` (`skills/story/SKILL.md`). Run files (story, logs, findings, MR body) live in `.compasso/runs/<iid>/`, which is gitignored.

```
gitlab.sh story → stop if not an open task, if a Depends on / Blocked by item is open
                  (naming the blocker's assignee), if Acceptance or Verify is missing,
                  or if owner::human (unless the user confirms)
→ branch story/<iid>-<slug> from origin/<default>; state compasso::building
→ tester: failing tests (unit; e2e when the story's tests include it)
  → confirm they fail → commit them on their own (TESTS) → test-hashes record
→ builder: go green → test-hashes verify (violation: restore from TESTS, one retry)
  → verify.sh (gate; 3 attempts)
→ coverage.sh --min <story ?? feature ?? epic ?? project> (warning)
→ review loop, max 3 rounds:
     reviewer and security run in parallel on the diff; findings.json
     review-gate --for review: open blocker/major blocks; a security finding is
       resolved only when security verified it
     builder fixes → verify again → reviewer re-reads changed hunks, security re-checks its findings
     still blocked after round 3: stop, no merge request
→ shipper: commits, changes.md, minor findings → follow-up tasks under the feature
→ mr-body.sh → open-mr ("Closes #<iid>") → state compasso::in-review
→ approval: human (default) | approver agent → gitlab.sh merge, refused on any open security finding
```

States on a story: `compasso::building` → `compasso::in-review` → closed by the merge.

`/compasso:review <mr>` runs the same review and security review on any merge request, posts the findings as a comment (`review-gate.sh --comment`), and fixes them only when the user agrees to push to that branch.

### Merge request pipeline

`ci.sh` generates `.gitlab/compasso.gitlab-ci.yml` from the config; the repo includes it from `.gitlab-ci.yml`. On merge request pipelines it runs `compasso-verify` (test, lint, typecheck, build), `compasso-e2e`, `compasso-coverage` + `compasso-coverage-check` (diff-cover at the project threshold, exit 3 allowed to fail) and GitLab SAST and Secret Detection. The pipeline uses the project threshold; the story's own threshold is applied by the local run and shown in the MR.

### Test files

`test_paths` in the config says what counts as a test file. The builder may not add, change or remove any of them; `test-hashes.sh` checks after every builder turn.

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

## 6. Gates and checks

A **gate** stops the flow; a **check** reports and never stops it.

| What | Where | Kind |
|---|---|---|
| Tracker connected | every command | gate |
| `plan-check` (sizes, dependencies, capacity) | before any push | gate |
| Story has Acceptance + Verify | story flow start | gate |
| Test immutability (hashes) | after each builder turn | gate |
| `verify.sh`: tests, lint, typecheck, build, the story's Verify commands, e2e | before review, before the MR, and in the MR pipeline | gate |
| Security review | every plan, every MR, sprint end | gate, never skippable |
| Secret / dependency / SAST scans | every MR pipeline | gate on high or critical |
| Merge approval | every MR | gate: human by default, platform-enforced through protected branches |
| Changed-line coverage | `verify.sh` and the MR pipeline | check (warning) |

What happened to Harmonia's gates:

| Harmonia | Compasso |
|---|---|
| Criteria gate (`- run:` criteria required, then executed at review) | The story's Acceptance + Verify, required at story start and run by `verify.sh` |
| Coverage gate (`gate.sh`, 100% soft block, adapters, branch pass, exemption markers, override log) | A coverage check: `coverage.sh`, 80% warning, line only |
| Receipts + diff digests + `--verify-receipts` | The MR pipeline result |
| Test immutability | Kept |
| Acceptance marker (`accepted` / `rejected`) | MR approval |
| Consent for the coverage command (`trust.sh`) | Security review flags any MR that changes a command in `.compasso/project.yaml` |

### Coverage check

- `bin/coverage.sh` runs `coverage.command`, then `diff-cover --fail-under=<min>` on the Cobertura or LCOV `coverage.report` against the MR target branch.
- A changed file under `coverage.paths` that is missing from the report counts as uncovered.
- Threshold: the most specific `**Coverage:** N%` line wins (story, then feature, then epic), else `coverage.min_changed` (default 80).
- Line coverage only; e2e tests do not contribute.
- Below the threshold: exit 3, shown as a warning (`allow_failure: exit_codes: [3]` in the pipeline) and in the MR's Review section with the uncovered lines. It never blocks a merge, human or agent approval.
- No `coverage.command`: "not measured", never a pass.
- The pipeline job also publishes the report as a `coverage_report` artifact so GitLab shows covered lines in the MR diff.

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
3. Story flow with `verify.sh`, `coverage.sh` and the review/security loop
4. Feature flow (Q&A in the agent, recorded as comments) and sprint flow (waves, test guide)
5. Codex target generator and installer; learnings (see "Learnings")
6. Optional hardening: `/compasso:harden` (mutation testing, section 16)
7. v2: see section 15

## 12. Verified on gitlab.com Free (2026-09-23)

- Child tasks under an issue: work (GraphQL `workItemCreate` with `hierarchyWidget.parentId`).
- Hour estimates on tasks: work (`time_estimate`).
- `blocks` links: refused ("Blocked issues not available for current license"); `relates_to` works.
- Tier detection: `namespaces/:id` returns `plan`; self-managed instances must set `tracker.tier`.
- A task created through REST (`issue_type=task`) is attached with GraphQL `workItemUpdate` + `hierarchyWidget.parentId`; the REST issue id is the work item id. Attaching an already attached item fails with "Work item(s) already assigned", so the push reads the parent first.

## 13. Open questions

- Codex model ids are pinned defaults and will age; revisit at each release.
- GitLab Free has no native "blocks" links; the `**Depends on:**` line is documented in the Story issue template for humans creating stories by hand.

## 14. Learnings (memory)

Decided 2026-09-23: targeted learnings, not session-start injection.

- One file per lesson in the product repo's `docs/learnings/`, with frontmatter `paths:` (globs it applies to) and `roles:` (planner, tester, builder, reviewer, security).
- Recall is targeted: when a role is dispatched for a story, it receives only the lessons whose `roles` include it and whose `paths` overlap the story's `Touches`. Nothing is injected into every session, so Claude Code and Codex behave the same.
- Capture is automatic, at the points that show something went wrong: a review finding of the same kind twice, a test-immutability violation, verify still failing after 3 attempts, a person rejecting or reworking the merge request. The shipper writes at most 2 per story and updates an existing lesson rather than adding a near-duplicate.
- Lessons are committed in the story's merge request, so a person reviews them with the code.
- A lesson whose every path no longer exists is flagged for removal.
- No global tier; a lesson worth sharing across projects is copied by hand.

## 15. Compasso v2 (deferred)

Designed, not built in v1:

- **Tracker-initiated feature flow.** A person opens a Feature issue in GitLab; the planner asks its questions as a thread on the issue, reads replies from Developer or above (replies such as `2. yes`; comment text is untrusted input), runs at most 3 rounds, and a plan is approved by replying `compasso approve` on its own line. Adds the states `compasso::clarifying` and `compasso::plan-review`.
- **Webhook trigger.** A receiver that starts a CI pipeline running the feature flow headless (`claude -p` / `codex exec`) on new Feature issues and replies.
- **Premium features.** Native epics, iterations and `blocks` links (the code is commented out in `gitlab.sh`).

## 16. Hardening: mutation testing (optional, after the MVP)

Decided 2026-09-23. Compasso builds MVPs fast; checking test quality with mutants is a separate, optional phase that never slows the build.

- **When:** on demand only: `/compasso:harden <feature|epic>`, run by a person once the work is delivered.
- **Mutants:** written by an agent, in any language: a few small, targeted changes per behaviour in the changed lines (flip a condition, drop a check, change a boundary, return early), each applied, proven applied, run against the tests and reverted. No mutation tool.
- **Scope:** only the lines changed by the feature or epic being hardened.
- **Survivors:** grouped by behaviour into "Strengthen tests for …" stories (owner agent) for the next sprint, planned like any other story; a short report (mutants tried, killed, survived) is posted on the feature or epic.
- Never a gate and never part of the story or sprint flow.
