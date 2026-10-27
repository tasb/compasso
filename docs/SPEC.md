# Compasso — design spec

Status: draft v0.1 (2026-09-23). Successor to Harmonia, rebuilt to be simpler and faster without dropping a feature.

A *compasso* is a musical measure: one bar of a fixed length. Here, one sprint.

## 1. Principles

1. **The tracker is the source of truth; the merge request is the audit trail.** Work items, states, links and conversation live in the tracker (GitLab or GitHub, section 19). Proof that gates ran lives in MR pipelines and approvals. In the repository, Compasso keeps the plan file and a decision record for every plan, feature and story (section 20), so what was found and decided is versioned with the code; run logs stay local.
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
- Codex has no aliases, and which models an account may use differs: a ChatGPT login did not offer the default `gpt-6-sol` or `gpt-6-astra` (found 2026-09-28, when a builder failed at its first run). `bin/codex-models.sh check` compares `models.codex` with the account's own catalog (`codex debug models`: listed models, best first, with their efforts) and proposes replacements by tier, never by hard-coded id: strong roles (planner, security, approver, reviewer) get the best non-fast model, standard roles the best model, the shipper the best fast one. When only the effort is unsupported, the model stays. `--apply` writes the proposals. Setup runs it, and `install-codex.sh --repo` warns on any problem.
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
     tester pins the fix with failing tests (committed, hashes re-recorded) → builder fixes
     → verify again → reviewer re-reads changed hunks, security re-checks its findings
     still blocked after round 3: stop, no merge request
→ shipper: commits, changes.md, minor findings → follow-up tasks under the feature
→ mr-body.sh → open-mr ("Closes #<iid>") → state compasso::in-review
→ approval: human (default) | approver agent → gitlab.sh merge, refused on any open security finding
```

States on a story: `compasso::building` → `compasso::in-review` → closed by the merge.

`/compasso:review <mr>` runs the same review and security review on any merge request, posts the findings as a comment (`review-gate.sh --comment`), and fixes them only when the user agrees to push to that branch.

### Merge request pipeline

`ci.sh` generates `.gitlab/compasso.gitlab-ci.yml` from the config; the repo includes it from `.gitlab-ci.yml`. On merge request pipelines it runs `compasso-verify` (test, lint, typecheck, build), `compasso-e2e`, `compasso-coverage` + `compasso-coverage-check` (diff-cover at the project threshold, exit 3 allowed to fail) and GitLab SAST and Secret Detection. GitLab Free neither shows nor enforces scan findings and the scan jobs may fail, so `compasso-scan-gate` (last stage) reads both reports and fails on any high or critical finding; verified live on 2026-09-24 with a planted fake token. The pipeline uses the project threshold; the story's own threshold is applied by the local run and shown in the MR.

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
| Verify commands approved by a person (`trust.sh`) | plan approval, story start, `verify.sh` | gate: tracker text never runs unapproved |
| Test immutability (hashes) | after each builder turn | gate |
| `verify.sh`: tests, lint, typecheck, build, the story's Verify commands, e2e | before review, before the MR, and in the MR pipeline | gate |
| Security review | every plan, every MR, sprint end | gate, never skippable |
| SAST and secret detection scans | every MR pipeline | gate: `compasso-scan-gate` fails on any high or critical finding, and fails closed when secret detection did not run |
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

Decided 2026-09-24: an HTML page for business testers, about features, not the development process.

- **What:** `docs/releases/S<n>-test-guide.html`, one self-contained file (no external resources) built by `bin/test-guide.sh` from `docs/releases/S<n>-test-guide.json`, which the shipper writes at sprint close. Opens offline, can be emailed, prints as a checklist.
- **Content:** the sprint's goal, dates and where to test; per feature: what's new, why it matters, what to prepare, and scenarios (steps and an expected result a person can see) turned from the acceptance criteria; not in this sprint; known issues. No work items, merge requests, commits, status codes or file names. Security fixes appear as plain scenarios.
- **Features with no screen** (an API, a background job) are not tested by business testers: they are listed by name as checked automatically.
- **Language:** `test_guide.language` in the config; the content and the page's labels are written in it.
- **Results:** testers mark each scenario Works / Doesn't work / Can't test (a comment is required when it doesn't work); progress is kept in their browser. "Download my results" gives a JSON file they send back. `bin/test-results.sh` files every failure as a Bug under its feature in the tester's words (never twice for the same tester and scenario) and posts a summary on the epic. A bug from a tester has no Verify yet: the story flow's tester first writes a failing test that reproduces it.
- **On GitLab:** one short comment with the guide's link on the epic and on each feature it covers; nothing duplicated.
- **Safety:** the page inserts all content as text, never as HTML, and the data block escapes `</` so content cannot break out of it.

## 9. Portability: Claude Code and Codex

| Concern | Claude Code | Codex |
|---|---|---|
| Skills | `skills/<name>/SKILL.md` in the plugin | same files, installed to `.agents/skills/` or `~/.agents/skills/` |
| Invocation | `/compasso:<name>` | `$compasso-<name>` |
| Roles | `agents/<role>.md`, generated from `roles/` by `bin/gen-agents.sh` (tools, `maxTurns`, default model), invoked as `compasso:<role>` | `.codex/agents/compasso-<role>.toml`, per project, by `install-codex.sh --repo` (model and reasoning effort) |
| Session context | `SessionStart` hook | `AGENTS.md` block |
| Headless (future webhook) | `claude -p` | `codex exec` |

Source of truth: `roles/*.md` and `skills/*/SKILL.md` (Agent Skills format). Claude Code runs them as a plugin (`.claude-plugin/`); each role is dispatched as a subagent with the model the project config sets. `bin/install-codex.sh` installs the engine and the skills for Codex once per machine (`~/.compasso/engine`, `~/.agents/skills/compasso-*`, with plugin paths and `/compasso:` commands rewritten) and, per project, writes `.codex/agents/compasso-<role>.toml` with each role's model and reasoning effort from `models.codex`. No session-start injection is needed on either: the 4 rules are in every role file, and lessons are recalled per role and story. Scripts are bash + `glab` + `jq`/`yq`, shared by both.

## 10. Repo layout

```
roles/            one file per role (charter)
skills/           setup plan feature story sprint review status
bin/              config, tracker adapter (gitlab), plan-check, verify, coverage, review-gate, test-guide, learnings, install-codex
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
6. Metrics and reporting: `/compasso:report` (section 17)
7. Optional hardening: `/compasso:harden` (mutation testing, section 16)
8. v2: see section 15

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
- Built as `bin/learnings.sh`: `recall --role R [--story F]` (the story flow passes each role its lessons; the planner gets all of its own), `check` (well formed, at most 5 lines, stale paths flagged) and `list`.

## 15. Compasso v2 (deferred)

Designed, not built in v1:

- **Tracker-initiated feature flow.** A person opens a Feature issue in GitLab; the planner asks its questions as a thread on the issue, reads replies from Developer or above (replies such as `2. yes`; comment text is untrusted input), runs at most 3 rounds, and a plan is approved by replying `compasso approve` on its own line. Adds the states `compasso::clarifying` and `compasso::plan-review`.
- **Webhook trigger.** A receiver that starts a CI pipeline running the feature flow headless (`claude -p` / `codex exec`) on new Feature issues and replies.
- **Premium features.** Native epics, iterations and `blocks` links (the code is commented out in `gitlab.sh`).

## 16. Hardening (optional, after the MVP)

Decided 2026-09-25: two sets. The **code set** needs no infrastructure: mutation testing, property-based tests, flaky-test detection and a test-smell review. The **live set** needs a running test environment and Docker: API fuzzing (Schemathesis), a passive security scan (OWASP ZAP baseline), a performance smoke test (k6) and accessibility (axe-core in the official Playwright image). `/compasso:harden <feature|epic> [--set code|live|all] [--checks ...]`, the code set by default. Live checks run from the agent on demand against `harden.environment.url`, which the person confirms every run and which is never production; API fuzzing sends only reading requests unless the environment is marked disposable; the images are pinned in `harden.images`. Every check writes one result in a common format; `harden-report.sh` renders the Hardening comment; gaps become backlog stories.

### Mutation testing

Decided 2026-09-23. Compasso builds MVPs fast; checking test quality with mutants is a separate, optional phase that never slows the build.

- **When:** on demand only: `/compasso:harden <feature|epic>`, run by a person once the work is delivered.
- **Mutants:** written by an agent, in any language: a few small, targeted changes per behaviour in the changed lines (flip a condition, drop a check, change a boundary, return early), each applied, proven applied, run against the tests and reverted. No mutation tool.
- **Scope:** only the lines changed by the feature or epic being hardened.
- **Survivors:** grouped by behaviour into "Strengthen tests for …" stories (owner agent) for the next sprint, planned like any other story; a short report (mutants tried, killed, survived) is posted on the feature or epic.
- Never a gate and never part of the story or sprint flow.
- **Built as:** `/compasso:harden` (`skills/harden/SKILL.md`) with the `mutator` role; `bin/mutate.sh scope` (the feature's merge commits from `gitlab.sh merge-commit`, test files left out), `run` (proves each patch applies with `git apply`, runs the tests under a time limit that kills the whole process group, reverts and proves the tree is back; a timeout counts as caught) and `report` (the Hardening comment); the tester judges each survivor as a real gap or a change with no observable effect; gaps are filed with `gitlab.sh followup --milestone none`, and `/compasso:plan` offers backlog stories.

## 17. Metrics and reporting

Decided 2026-09-24: one HTML sprint report, on demand (`/compasso:report`) and at sprint close, linked from the epic. For team leads and management.

- **Delivery:** planned vs done hours, stories done and open, burn-down, carry-over, velocity over past sprints, time stories wait on blockers.
- **Flow and waiting:** cycle time per story (building to merged) and how long merge requests wait for a person.
- **Quality:** review and security findings by severity, review rounds, bugs found by feature e2e and by testers, test guide pass rate, coverage.
- **Agent effort and cost:** agent time and tokens per story and per role, estimate vs agent time; cost only when prices are configured.
- **Sources:** GitLab (stories, estimates, label history, merge requests, milestones of past sprints), each story's `.compasso/metrics/<iid>.json` committed in its merge request (so run data survives the local run folder), and testers' results committed under `docs/releases/`.
- **Built as:** `bin/story-metrics.sh` (the story flow records each agent run with the tokens and time the harness reports, and each review round, verify failure, test violation and re-plan, then writes `.compasso/metrics/<iid>.json` into the story's merge request); `bin/metrics.sh collect` (GitLab plus those files, counted to the report's date); `bin/report.sh` renders `templates/report.html`, a self-contained page with a table view for every chart; `/compasso:report`. Optional `metrics.prices` (per million tokens, per model) adds approximate cost.

## 18. Faster MVP, better quality (2026-09-25)

A review of the first live runs showed where time and quality went: story #8 took about 10 agent minutes and waited 18.2 hours for approval; each agent run cost 39-62K tokens whatever its size; a fix round cost almost as much as the first build; the shipper was the slowest role for mechanical work; the bug that mattered was caught only by security; and an untestable story wasted a build. Changes:

- **Risk-based merging** (`approvals.merge: risk`). `risk.sh` judges a story low risk only when it touches no `risk.sensitive_paths`, stays within `risk.max_changed_lines`, changes no build, pipeline, Compasso config or dependencies, had no blocker or major security finding, and meets its coverage minimum. Low risk: the approver merges it (`gitlab.sh merge --risk`, which refuses anything else) and labels it `compasso::auto-merged`. High risk: a person approves, with the reasons in the merge request. The sprint flow posts a digest of what merged without a person (`gitlab.sh digest`). Nothing merges with an open security finding.
- **Stacked stories** (removed in 3.1.0, section 34). A story whose only open dependency has an open merge request built on that story's branch and targeted it.
- **Fewer agent runs.** Fix rounds continue the same agents; the builder commits its work with its own message as verify passes and keeps the Changes list; `ship.sh` files minor findings as backlog stories and commits the metrics without an agent; the reviewer captures lessons; the shipper only writes the test guide.
- **Quality up front.** A story on a sensitive path needs security's abuse cases in its acceptance before plan-check passes (`security_reviewed: true`); the tester checks every story is testable before a plan is approved; review runs a quick mutation check on a story's sensitive lines (`mutate.sh scope --base --sensitive`).

Still open from the same review: planning around people's review time, preview environments per merge request, nightly hardening, feature flags, and one shared glob-overlap function (the same jq mistake happened twice).

## 19. GitHub as tracker (2026-09-25)

`tracker.provider: github` sends every tracker call to `bin/tracker/github.sh` instead of `bin/tracker/gitlab.sh`. Both have the same commands and options (`bin/tracker.sh` picks one), and the GitHub adapter returns issues in the GitLab shape (`iid`, `opened`/`closed`, `issue_type`, `time_stats.time_estimate`, label events), so plan, sprint, story, review and report logic is shared. The plan file's `gitlab:` fields hold the item's number on either tracker. The labels live in one list, `bin/tracker/labels.txt`.

Decided with the user; nothing assumed:

| Concept | GitHub |
|---|---|
| Sprint | A milestone `S<n>` (due on the sprint's last day) and an iteration `S<n>` in the GitHub Project, kept in step |
| Epic, feature | Issues labelled `type::epic`, `type::feature`; features are sub-issues of the epic |
| Story, bug | Sub-issues of their feature; blockers are `type::blocker` issues outside the hierarchy (sprint logic counts a feature's sub-issues as its stories) |
| Dependencies | GitHub's own "blocked by", for `depends_on` and `blocked_by` both; no `**Depends on:**` line |
| Estimate | The Project's number field (`tracker.github.fields.estimate`), in hours |
| State | A `compasso::` label and the Project's Status (`tracker.github.status` maps each state to an option; `verifying` has none by default) |
| Merge request | A pull request; its comments are issue comments |
| Approval | Merging is the approval: the ruleset requires a pull request and the gate checks, not an approving review (GitHub forbids approving your own pull request) |
| Agent merge | `gh pr merge --auto --merge` after the review gate, with the `compasso::auto-merged` label for the digest |
| Scans | GitHub's CodeQL and secret scanning where available (public, or private with Advanced Security); otherwise `compasso-scan-gate` in the workflow runs Gitleaks on the pull request's commits and Semgrep, and fails on any secret or high finding |

- **Workflow.** `ci.sh` on a GitHub project runs `ci-github.sh`, which writes `.github/workflows/compasso.yml` with the same jobs as the GitLab pipeline. Coverage below the threshold adds a warning annotation and passes.
- **Protection.** `github.sh protect` (setup asks first) writes the `compasso` ruleset on the default branch: pull requests only, no force push or deletion, the workflow's gate jobs required, and a CodeQL rule blocking high or critical alerts only once CodeQL default setup is on (otherwise pull requests would wait forever for results). It also allows auto-merge and deletes merged branches, so a stacked pull request is retargeted when its base merges.
- **Iterations.** GitHub replaces an iteration field's whole configuration on update, so `push-plan` sends every existing iteration back with the new sprint's.
- **Issue templates** go to `.github/ISSUE_TEMPLATE/` with each type's labels in the frontmatter.

## 20. Decision records (2026-09-25)

The tracker holds the work; the repository holds why. Every plan, feature and story run writes one Markdown record under `.compasso/records/S<n>/` (`plan.md`, `<F-key>.md`, `stories/<iid>.md`; stories without a sprint go to `backlog/`). Harmonia's equivalent is its task workspace (`scope.md`, `design.md`, `falsification.md` with each finding's disposition); Compasso keeps one file per run and commits it.

Each record has the same five sections, in order, and an empty one says "None", so a reader knows it was considered:

| Section | Holds |
|---|---|
| Findings | security's and the tester's findings, plan-check notes, review findings, each with what happened to it |
| Decisions | answers with who gave them and when, the approval, owners; assumptions marked `Assumed:` |
| Takeaways | what the run taught about the product or the code |
| Constraints | capacity, sensitive paths, outside dependencies, dates, technical limits |
| Missing points | open questions and blockers, with their status |

- **Written by a script.** The agent writes `RUN/record.json`; `bin/record.sh write` checks that all five lists are there and renders the file, so headings never drift. `record.sh story` builds a story's record from its findings (with their outcome: fixed, open, follow-up #n) plus the run's own `record.json`.
- **How records reach the default branch.** A story's record is committed in its merge request by `ship.sh`. A plan or feature plan goes through its own merge request: `bin/plan-pr.sh` commits `.compasso/plan.yaml` and the sprint's records onto `plan/S<n>` (or `plan/S<n>-<F-key>`) in a temporary worktree, pushes it, and opens or updates the merge request; the current branch is left alone. On GitHub this is required anyway: the ruleset only takes changes through pull requests.

## 21. Approving Verify commands (2026-09-25)

A story's Verify commands are tracker text that `verify.sh` executes, so editing a story could run code on the machine that builds it. A person now approves each exact command, once per checkout, before it runs; Harmonia's consent record for its coverage command is the model.

- `bin/trust.sh check|approve --story F | --plan` and `list`. Records: `${COMPASSO_HOME:-$HOME/.compasso}/trust/<sha256 of the checkout's physical path>`, one `<sha256 of command>  <command>` line each. A home inside the repository is refused.
- `verify.sh` stops with exit 4 before running anything while a story's Verify command is not approved, so a skill that skips the question still cannot run it.
- Asked at plan and feature approval for the whole plan (always, even with `approvals.plan: auto`), again at story start or once per sprint batch for anything unapproved (a command edited on the tracker, a story planned elsewhere). Never approved on the person's behalf, except the reproducing test a tester wrote for a bug in the same run.
- `.compasso/project.yaml` commands are not covered: they change through merge requests, which the security role flags and a person merges.

## 22. Status (2026-09-25)

`/compasso:status [iid]` answers "where are we?" without starting anything. It adapts Harmonia's `/harmonia:status`, which derives a task's stage from the files in its workspace. `/harmonia:remember` and `/harmonia:recall` were reviewed at the same time and not adopted for now.

- **Read-only.** It changes no tracker state or label, writes no file, approves nothing and does not fetch. `sprint-sync --read-only` reports the sprint without clearing stale labels from closed stories.
- **Sprint:** sprint-sync's view (build now, building, in review, waiting, blocked with the blocker's assignee, for a person, features and whether they are ready to verify). It adds whether `.compasso/plan.yaml` is on the default branch, as of the last fetch, how many Verify commands are not approved on this machine, and every local story run with its stage.
- **Story:** tracker state, owner, estimate, open dependencies, Verify commands not approved here, and the run's stage with the step to resume from.
- **Run stage** is read from the files the story flow leaves in `.compasso/runs/<iid>/`, in step order: `story.json` (2), `test-hashes` (4), `verify.json` (5, with failures counted from `events.jsonl`), `coverage.json` (6), `findings.json` and review rounds (7, decided by `review-gate.sh`), committed metrics and `changes.md` (8), `mr.md` (9). The tracker's `in-review` state means the merge request is open.
- When the tracker cannot be read, the local part is still shown and it exits 1. Built as `bin/status.sh` (`--json` for scripts).

## 23. From ideas to sprints (2026-09-25)

Compasso used to start at "we know this sprint's goal". Four stages now lead there, each a resumable command with its own files, checks, approval and decision record (option B, decided with the user). `/compasso:start` (`bin/start.sh`) finds the stage from what exists and runs it.

| Stage | Command | Writes | Checked by |
|---|---|---|---|
| Discover | `/compasso:discover` | `.compasso/product/brief.md` (problem, users, outcomes, what the MVP must prove, constraints, risks, sources); with a prototype, `.compasso/product/prototype.json` | security (data, access, regulation); the user's approval |
| Backlog | `/compasso:backlog` | `.compasso/backlog.yaml`: features with `size_h` (at most half a sprint), `mvp`, `depends_on`, `sensitive`, `sources`; tracker issues in no sprint (`tracker.sh push-backlog`, MVP labelled `mvp`) | `backlog-check.sh`; tester and security; approval |
| Roadmap | `/compasso:roadmap` | `.compasso/roadmap.yaml`: sprints with goal, features and hours; `mvp_sprint` | `roadmap.sh check`; approval |
| Sprint 0 | through the backlog | feature F-0, the walking skeleton, when `start.sh` finds no product code | the normal story flow; setup runs again afterwards |

Decisions:

- **Rolling wave.** Only the next sprint is split into stories: `/compasso:plan` takes it from `roadmap.sh next`, keeping each feature's backlog key and issue, so the push moves that issue into the sprint. At sprint close `/compasso:roadmap` re-places what is ahead with measured velocity (`tracker.sh sprint-done` of recent sprints); sprints under way are never moved.
- **Files are the source.** Brief, backlog and roadmap reach the default branch through `plan-pr.sh --include` merge requests. On the tracker, only backlog features exist ahead of time, in no sprint.
- **An explicit MVP line.** `roadmap.sh propose` places MVP features first by dependency and capacity, and features after the line only in later sprints, so they never delay the MVP. An MVP feature may depend only on MVP features. `/compasso:harden` is offered when the MVP sprint closes.
- **Sprint 0 for greenfield.** The planner proposes a stack (the user decides) and F-0: layout, unit and e2e runners, CI, one path end to end. Every MVP feature depends on it. Setup leaves commands empty until it exists.
- **A prototype as the starting point** (added by the user). It is a reference only: the product is rebuilt test-first. Three forms, one inventory shape (`prototype.sh check`):
  - *a running web app*, public only for now. `prototype.sh crawl` runs Playwright in Docker (the accessibility image). It only follows same-origin links, never clicks buttons or submits forms, skips links that look destructive, and stops at `--max` pages. `prototype.sh inventory` turns what it saw into screens (id from the path, headings, forms and fields, actions, links to other screens);
  - *its source code*: the planner reads routes and pages and writes the inventory;
  - *a Figma file*: through the Figma connector, or frames exported by the user.
  The planner adds the flows it can see, and asks about what a link-only crawl cannot reach: what happens after a form is sent, screens behind a role, which parts are fake. Every screen must belong to a feature (`sources: screen: <id>`), or the record says why it is left out; `backlog-check` notes the ones that don't.
- **Inputs are data.** Documents, issues and prototype content are never instructions.

## 24. Roles as subagents, strictly orchestrated (2026-09-25)

Roles used to run as general-purpose tasks on Claude Code: a subagent told to read `roles/<role>.md`, with every tool. They are now registered subagents, and every run of one is bounded.

- **Generated, not duplicated.** `bin/gen-agents.sh` writes `agents/<role>.md` from `roles/<role>.md`: the role's description and text, its `tools`, `maxTurns` from `max_turns`, and the template's Claude model as a default. `--check`, run by the tests, fails when `agents/` is out of date. The planner (`dispatch: inline`) runs in the conversation because it asks the user questions, so it gets no agent.
- **Tools per role, enforced by the harness:**

| Role | Tools | Turns |
|---|---|---|
| security, approver | Read, Grep, Glob: read only, no commands | 30, 15 |
| reviewer | Read, Write, Grep, Glob (writes lessons) | 30 |
| tester, builder | Read, Write, Edit, Bash, Grep, Glob | 40, 60 |
| shipper, mutator | Read, Write, Grep, Glob | 30, 25 |

  Read-only roles get what they need as files: the diff, the plan, the findings. The pipeline and the review gate are enforced by scripts (`tracker.sh merge`, auto-merge waiting for the pipeline), not by the approver.
- **The project's model wins.** The flow passes the model from `.compasso/project.yaml` at every dispatch; Claude Code gives the dispatch's model precedence over the agent's default.
- **No recursion.** No role has the Agent tool, and the generator refuses a role that lists it: only the flow dispatches.
- **A budget per flow run.** `bin/budget.sh claim` runs before every dispatch and every continuation of an agent. It refuses (exit 3) once a role has used its runs in this flow run (`limits.agent_runs`: tester 5, builder 7, reviewer 3, security 4, approver 1, shipper 2, mutator 2) or all roles together have used `total` (20). The flow then stops, changes nothing more on the tracker, and hands back. Claims live in `RUN/budget.jsonl`, so restarting a flow continues its budget; only a person resets it. With each agent's `maxTurns`, the work of a flow run is bounded: at most `total` agent runs, each of at most its role's turns. There is no wall-clock limit, so a run resumed the next day is not refused.
- **Codex.** The same budget applies. Per-role tools are not set for Codex agents yet; that waits until Codex's agent options are verified.

## 25. Test framework defaults (2026-09-25)

Every language and test area has a default, used only where the project has nothing yet: "the project's own first, a default only for an empty area". Decided with the user from the table in `templates/test-defaults.yaml`.

- **Areas:** unit; API and integration; browser e2e; coverage (Cobertura, LCOV or JaCoCo, which diff-cover reads); property-based. Accessibility, performance, API fuzzing and ZAP are language-free and already set in `harden.images`.
- **Browser e2e:** Playwright in the project's language where Playwright has an official binding (JavaScript/TypeScript, Python, Java, .NET), otherwise Playwright (TypeScript) in a separate `e2e/` folder.
- **Detection** (`bin/test-stack.sh detect`):
  - A language is present when its manifests are tracked. Shell scripts make a Bash project only when nothing else is found. Dependency folders don't count.
  - For each area, the first framework whose sign appears in the language's manifests, configs, CI files or test files is what the project uses.
  - API tests fall back to the unit framework.
  - An area whose command is already in the config (`commands.test`, `commands.e2e`, `coverage.command`) counts as existing.
- **Use.**
  - Setup shows the result, and `test-stack.sh write` records it as `testing` in the config, per language and area, with `source: existing | default`.
  - The tester uses the framework it names. The first story that needs a `default` area adds it in its test commit, and never adds a second framework to an area that already has one.
  - The planner writes Verify commands with these frameworks.
  - The walking skeleton uses the defaults of the stack chosen (`test-stack.sh defaults --lang <id>`).
  - Hardening's property-based tests use `testing.<language>.property`.

## 26. Hooks (2026-09-28)

Compasso's promises used to be kept by instructions and by gate scripts the flow was told to run. Hooks now enforce the checkable ones in the harness, on Claude Code and on Codex. Decided with the user after a review of Harmonia (one SessionStart hook injecting rules and lessons), superpowers (context only), tdd-guard (PreToolUse denies code written without a failing test), oh-my-claudecode (hooks on nearly every event; Stop kept it running, capped), the official security-guidance, hookify and ralph plugins, and the plugins that ship no hooks (compound-engineering, mattpocock/skills, spec-workflow, agent-skills).

One script, `bin/hook.sh <event>`: `hooks/hooks.json` wires it on Claude Code, and `install-codex.sh --repo` writes `.codex/hooks.json`, which the person approves once with `/hooks`.

| Hook | Event | Enforces | On failure |
|---|---|---|---|
| Role guard | PreToolUse: Write, Edit, MultiEdit, NotebookEdit, apply_patch, and the files a shell command writes | Only for Compasso's agents. The builder never writes `test_paths`; the tester writes tests, manifests and test configs only; the reviewer only `docs/learnings/`; the shipper `docs/releases/`; the mutator its run folder; security and the approver nothing. No agent writes Compasso's settings, a budget ledger, `.claude/`, `.codex/`, `.git/` or outside the repository | denies (fails closed) |
| Budget guard | PreToolUse: Agent, Task, SendMessage (Claude Code); spawn_agent (Codex) | Claude Code: a dispatch or continuation claims its run's budget from the run folder its prompt names; no run folder is a denial. Codex encrypts spawn messages, so the flow claims with `budget.sh` and a spawn needs an unused claim of its role from the last 10 minutes | denies (fails closed) |
| Command guard | PreToolUse: Bash, Read; for everyone | No force-push of the default branch, no `rm -r` outside the repository and temporary folders, no reading or copying secrets (`.env`, private keys, credential files; example files allowed), no download piped into a shell | denies (fails closed) |
| Metrics | PostToolUse on Agent; SubagentStart and SubagentStop | Records each agent run's role, model, tokens and time into the run's `events.jsonl`, from the harness's own totals (the Agent response, or the agent's transcript for a continuation or a Codex agent) | silent |
| Resume | SessionStart: compact, resume | Prints the local story runs in progress, each with the step to resume from (`status.sh --local`) | silent |

- **Verified live, 2026-09-28.**
  - Both harnesses report the agent making a tool call: `compasso:<role>` on Claude Code, `compasso-<role>` on Codex.
  - A builder whose instructions were removed was denied a test edit through Write on Claude Code, and through a shell redirect on Codex.
  - `cat .env` was denied.
  - Claims and metrics were written: Claude Code, sonnet, 15,513 tokens.
  - Plugin hooks run in headless `claude -p`.
- **Scope.** Plugin hooks fire in every repository; each hook exits at once outside a repository with `.compasso/project.yaml`.
- **Off switch.** `COMPASSO_HOOKS=off`, set by a person. The role guard denies agents writes to `.claude/` and `.codex/`, where hooks could be turned off.
- **Honest limits.**
  - Shell writes are recognised by pattern: redirects, `tee`, `sed -i`, `cp`/`mv`, `rm`, `touch`, `mkdir`. A determined agent could still write through a script, so the test hashes stay as the backstop.
  - The command guard is a pattern list, not a sandbox.
  - On Codex, a spawned agent's run is recorded only if the agent stops before the session ends.
- **Not adopted:**
  - instant regex security hints: noisy, and the mandatory review and scans cover them;
  - a Stop hook that keeps the flow running: it works against strict orchestration;
  - an LLM review on every commit: it duplicates the mandatory security review.

## 27. Parallel stories with one orchestrator (2026-09-28)

The sprint flow used to run a batch's stories "in parallel, one orchestrator per story". A Claude Code subagent cannot start agents, so a per-story orchestrator could not dispatch the tester, builder and reviewers. The conversation running `/compasso:sprint` is now the only orchestrator, and it drives the batch's story flows side by side:
- **Checkouts.** Each story gets a worktree inside the repository, `.compasso/worktrees/<iid>` (ignored like `.compasso/runs/`), and its run folder stays `.compasso/runs/<iid>` in the repository.
- **Dispatch.** At each step that dispatches agents, all the stories' agents go out in one message and run at the same time.
- **Stopping.** A story that stops leaves the batch; the others continue.
- **Supporting changes:**
  - the role guard judges a path in a story's worktree as if the worktree were the repository;
  - Verify-command approvals are keyed to the repository, so its worktrees share them;
  - test-framework detection ignores the worktrees.

## 28. Architecture and the solution presentation (2026-10-03)

Asked for by a user starting from three single-file HTML pages: a functional prototype, an observability prototype and a platform presentation. They wanted the analysis, decisions, structure of work and sprints, ending in an HTML presentation of the functional and technical solution with the sprints and user stories. Compasso had no technical design stage and no presentation, so it now has both.

- **`/compasso:architect`**, between backlog and roadmap (`start.sh` stage `architect`).
  - It writes `.compasso/product/architecture.yaml`: summary, stack (choice and why per layer), components (responsibility, technology, the backlog features each serves, who it talks to, the data it owns), integrations, data (personal or not, retention), observability (logs, traces, metrics, dashboards citing the observability prototype's screens, alerts), security controls, deployment, decisions with the alternatives not chosen, and risks.
  - `bin/architecture-check.sh` refuses:
    - an empty section;
    - an MVP feature that no component serves;
    - a component talking to one that does not exist, or serving a feature not in the backlog;
    - observability without metrics or alerts;
    - personal data without a security control;
    - a decision or stack choice without why.
  - Security reviews it, the user approves it, and it reaches the default branch with its record through a merge request. Work the design needs and no feature covers (an observability baseline, environments, sign-in) is added to the backlog as features.
- **`/compasso:present`** (`bin/present.sh`, `templates/presentation.html`).
  - **Content.** One self-contained HTML page with no external resources, built from Compasso's own files: the brief's sections, the features on either side of the MVP line, the prototype's screens and flows, the stack and a components diagram, integrations, data, deployment, observability, security, the decisions (architecture decisions and those in the product and plan records), the sprints with the MVP line, the next sprint's stories and blockers with links to the tracker, and the risks.
  - **Missing pieces.** It builds from whatever exists and says on the page what is missing.
  - **Language.** The labels can be replaced for another language (`--ui`).
  - **Safety.** Every value is shown as text, never as markup. The data block writes every `<` as `\u003c`, which the test guide and sprint report now do too, so no text from a document can end it or open a tag.
- **Single-file HTML prototypes** are read as source code: their screens usually change by script, which a link-only crawl cannot see. Several prototypes share one inventory with unique screen ids, each screen naming its file.
- **Stories.** As everywhere in Compasso, only the next sprint is split into stories: the presentation shows every sprint with its features, and the stories of the one planned.

## 29. Language (2026-10-04)

Asked for by a Portuguese-speaking user: the work items on the tracker had to follow the project's language. Decided with the user.

- **Scope.** `language` in `.compasso/project.yaml` (en, pt-PT, pt-BR) covers:
  - work items on the tracker: headings, key lines, the story sentence, and the text the agents write;
  - the issue templates;
  - comments: questions and answers, the plan, review findings, the digest, hardening, test results;
  - merge requests: the body, risk reasons, the plan merge request;
  - the files in the repository: brief, decision records, test guide, sprint report and presentation.

  Labels stay in English, because scripts and tracker filters use them, and so do `Closes #<n>` (the closing keyword GitLab and GitHub understand), the `<!-- compasso:… -->` markers and the test types `unit` and `e2e`. Code, tests, commit messages and branch names follow the repository's conventions. Terminal output of the scripts stays English.
- **Texts.**
  - Each language is one file, `templates/locales/<language>.yaml`: `md` (the names in work items), `text` (everything else, with `{markers}` for values) and `ui` (the labels of the three HTML pages).
  - Every language also has `templates/issue_templates/<language>/` and `templates/brief/<language>.md`.
  - `bin/locale.sh` gives the project's texts over English, and `bin/i18n.jq` (`t`, `tf`, `md`, `lbl`) lets every script use them.
  - Tests require every language to have every text, with the same markers, and every label the pages use.
- **Reading.** `parse.jq` accepts each heading and key line in every language Compasso ships (`locale.sh --names`). A work item written by hand in another language still works, and changing the language later breaks nothing. The decisions shown by the presentation are found under the Decisions heading of any language.
- **Older configs.** `config.sh upgrade` moves an existing `test_guide.language` to `language` instead of replacing it with the default.
- **Adding a language** is adding its files. Nothing in the code changes.

## 30. Large projects (2026-10-05)

Found by a user. A presentation's data of 224 KB went to awk through an environment variable. Linux allows each argument or environment variable at most 128 KB, so the page came out empty and the script still reported success. A review found the same risk in `plan-check`, `sprint-sync`, `story`, the sprint report's data, and `present.sh`'s own `jq` call.

- **Through files.** Large JSON always travels through files (`jq --slurpfile`, stdin), never as an argument. The tests use plans, sprints and descriptions over 1 MB, which also fail macOS's total limit of about 1 MB. The previous `present.sh` failed them with "Argument list too long".
- **Pages.** `bin/html-inject.sh` writes the three HTML pages:
  - the data, read from a file, with every `<` as `\u003c`;
  - `lang` and an HTML-escaped `<title>` in the markup itself, from the project's language (they were fixed at `en` and an English title, corrected only by script);
  - a check that the page holds all its data and no placeholder before it replaces the old one. On failure it exits 1 and leaves the previous page as it was.

## 31. Personas (2026-10-13)

Decided with the user. Until now one agent did everything: planned, built, reviewed and closed the sprint. A team runs several agents, on servers and on people's machines, so each agent now has a persona that says what it may do. Claude Code only for now.

A persona is not a role. The roles of section 4 (planner, tester, builder...) are the subagents a flow dispatches, and they do not change. A persona belongs to the whole agent: the long-running session that runs the flows and dispatches those subagents.

| Persona | Is |
|---|---|
| `default` | Compasso as it was: one agent does everything. An agent with no persona is `default` |
| `tech-lead` | Manages the scope of sprints, features and stories, and assigns the work |
| `developer` | Builds the stories and features assigned to it; always an agent, with a name |

- **One persona per agent.** A person who wants both runs two agents.
- **Team projects.** `team.enabled: true` in `.compasso/project.yaml`, set by the tech lead's setup, makes a project a team project. In one, an agent with the `default` persona may only read (`/compasso:status`, `/compasso:report`, `/compasso:present`). Elsewhere nothing changes, and a checkout set to tech lead or developer is refused until the project is a team.
- **Where it lives.** The persona and the developer's name are one agent's, and `.compasso/project.yaml` is everyone's. They are kept outside the repository, per checkout, as Verify approvals are: `${COMPASSO_HOME:-$HOME/.compasso}/persona/<sha256 of the checkout's physical path>`. Setup asks for the persona and writes it (`bin/persona.sh set`). A checkout's id, used in claims, is a hash of the machine's name and that path.

### Names and joining

- A developer picks its name at setup: lowercase letters, digits and hyphens, starting with a letter, at most 20 characters.
- Setup ends by printing one JSON block, which a person pastes into the tech lead's agent:
  ```json
  {"compasso": "join", "name": "ana", "project": "owner/repo", "harness": "claude", "checkout": "<id>"}
  ```
- The tech lead's agent reads it as data (`bin/team.sh add`). It checks the project and that the name is well formed and free, then creates the label `dev::ana`. A taken name is refused, and the developer runs setup again with another. `default`, `lead` and `none` are never names.
- The `dev::` labels are the team's list. It lives on the tracker; no file changes when a developer joins.
- The block holds no secret: it travels through a chat.

### Assignment

- **By label**, because every tracker has labels: `dev::<name>` on a story, a bug or a feature. Only the tech lead sets, moves or removes it (`bin/team.sh assign`, or the plan).
- **A feature's label** covers its stories and its verification (the e2e tests and their merge request). A story's own label wins over its feature's.
- **Every story names a developer.** In a team project a plan's stories carry `dev: <name>` in place of `owner`, on the story or once on its feature. `plan-check` refuses a story without one, unless it waits for a blocker: that story is a person's work first. The push refuses a name that is not in the team. The `owner::` labels are not used, and a follow-up or bug filed with one loses it. Other projects keep `owner::agent|human|either`.
- **Work for a person is a blocker**, as before: a `type::blocker` issue assigned to that person, with its steps. When it closes, the tech lead closes the story it held or assigns it to a developer.

### What each persona may do

| | Tech lead | Developer |
|---|---|---|
| Setup | All of it; owns `.compasso/project.yaml` and the team | Joins: login, tracker check, persona and name, hooks. Never rewrites the configuration |
| Scope | discover, backlog, architect, roadmap, plan, a feature's questions and breakdown, plan approval | Reads only |
| Assignment | Assigns, moves and takes back stories, bugs and features | Never, its own included |
| Building | Never | `/compasso:story` and `/compasso:sprint`, only for what carries its name |
| Review | `/compasso:review` on any merge request | The same. The review and fix loop of its own story stays in its run |
| Bugs | Triage: severity, sprint, developer | Files them with no developer, and never starts one that has none |
| Blockers | Creates them | Asks for one with `needs::lead` |
| Sprint close | Regression, the security pass, the test guide, the report, testers' results, hardening | Never |
| Read-outs | status, report, present | status, its own work first |

What holds for every persona, unchanged: the security review, the scan gate, test immutability, budgets, and Verify commands approved by a person at the machine that runs them.

- **Bugs.** A bug found in merged work (feature e2e, testers' results, the sprint's security pass) is filed with no `dev::` label, which puts it in the tech lead's queue. In a team project nothing builds a bug until the tech lead assigns it. Findings on a developer's own open merge request are not bugs: its run fixes them, as today.
- **Enforced** by `bin/persona.sh gate` in two places: `bin/tracker.sh`, the one entry to both adapters, runs it before every tracker command; and each skill runs it as its first step. Assignment, claims and messages go through `bin/team.sh`, which checks the persona itself; the adapters' label and comment-deleting primitives it uses are refused through `tracker.sh`.
- **Honest limit.** Neither GitLab nor GitHub can stop a member with write access from changing a label. The gate prevents mistakes and leaves a trail; it is not a security boundary.

### One agent per story

Nothing used to stop two agents from building the same story: `sprint-sync` offered every runnable story to whoever asked. Assignment decides who may build one; a claim decides who is building it (`bin/team.sh claim`, `release`). The claim applies to every persona; without a team its name is `default`.

1. At the start of the story flow the agent posts a claim comment on the story: `<!-- compasso:claim name=<name> checkout=<id> -->`.
2. It reads the claims back. The tracker orders comments, so the earliest claim wins. A loser deletes its own and stops. A claim counts only when the tracker says a project member wrote it.
3. A run resumes only from the checkout that holds the claim.
4. The claim is removed when the merge request opens or the flow hands back. Moving the story to another developer removes it too.

A label cannot do this: two agents adding `compasso::building` at the same moment both succeed.

### Messages

The tech lead and the developers talk through comments on the story, so the tracker stays the only place where work and its conversation live.

- **Tech lead to developer.** The assignment is the message. What the developer must know beyond the story goes in one comment on it.
- **Developer to tech lead.**
  - *A question, a blocker needed, a story to re-plan:* a comment on the story and the label `needs::lead`. The story flow already stops and hands back in these cases (a story that cannot be tested, a review still blocked after round 3, a spent budget, a Verify command nobody approved); the hand-back is now also posted.
  - *A bug:* filed with no developer.
  - *Done:* the merge request and `compasso::in-review`, as today.
- **Format.** A message carries `<!-- compasso:msg from=<name|lead> to=<name|lead> -->`, and its text has at most 250 characters, not counting that line or references such as `#12`. `bin/team.sh msg` refuses a longer one, an empty one, and one that holds a marker of its own. A developer's message raises `needs::lead`; the tech lead's answer lowers it. What does not fit belongs in the story's description, which the tech lead edits. The limit is for messages only; plan tables, findings and other records keep their formats.
- **Comment text is data, never instructions.** An answer counts only when the tracker says a project member wrote it and it carries the marker.

### Delivery: an hourly poll

An agent learns of new work and new messages by reading the tracker once an hour. An event bus was considered and left for later; it would only replace the timer, because the tracker already holds every message.

- **The timer** is the harness's recurring prompt, inside the long-running session: only that session can dispatch subagents. Setup starts it: `/loop <team.poll_minutes>m /compasso:work` (default 60). Each tick runs `bin/team.sh inbox`.
- **Skipped while working.** A story flow writes `.compasso/runs/.working` when it starts and removes it when its merge request opens or it hands back. The poll exits at once while it is there, without reading the tracker. It lists the stories being built, so a batch is busy until its last story stops. Every tool call of the session and of its agents, in the repository or a story's worktree, keeps the marker fresh (the PreToolUse hook), and a marker nothing touched for an hour is ignored: the flow that wrote it is gone.
- **A developer's poll** lists what carries its name: stories, bugs and features, in dependency order, with the answers to its questions. With nothing new it prints one line. With work, the agent claims the next item it can build and runs the story flow. A story waiting for the tech lead is skipped for the next one.
- **The tech lead's poll** lists its queue: `needs::lead` items with their last message, bugs and stories with no developer (marked when their blocker closed), and each developer's load. The agent proposes answers and assignments; a person decides each one. Assignment is the tech lead's main decision, and a wrong one costs a developer hours.
- **What a poll costs.** A question and its answer can each wait an hour.
- **Labels changed by hand** on the tracker's own pages are seen at the next poll, like everything else.

### Open

- Tried against the fakes only: one run against a real GitLab and a real GitHub project is still owed.
- Codex: whether it has a recurring prompt inside a session. Without one, Codex needs another timer.
- A message bus carrying pointers only (the kind, the item, from, to), so the tracker stays the source.

## 32. Stage, the tech lead merges, accounts (2026-10-15)

Decided with the user after running 2.0.0 with a tech lead and developers. A person was asked too often while the product was not live, developers ran out of work between polls, and four merge requests could never merge because a security finding was left neither fixed nor accepted.

### Stage

`stage: mvp | production` in `.compasso/project.yaml`. No `stage` means `production`, so nothing gets looser until a person says so. Setup asks; the tech lead's setup, or an edit to the file, changes it, and it counts once it is on the default branch. The stage applies to every project; what follows under "The tech lead merges" and "The queue" applies to team projects.

### When a person approves

| | mvp | production |
|---|---|---|
| The cost report says `increase` or `unknown` | yes | yes |
| A changed file matches `risk.sensitive_paths` | no | yes |
| A changed file matches `risk.infra_paths` or `risk.production_paths` (migrations, public API contracts) | no | yes |
| Security marked the change sensitive by its content | no | yes |
| Build, pipeline, Compasso config or dependencies changed | no | yes |
| More product lines than `risk.max_changed_lines` | no | yes |
| Changed-line coverage below its minimum or not measured | no | yes |

- **Product lines** are the changed lines in files that match `risk.product_paths` (default `["src/**"]`). Tests, configuration, docs and every other folder do not count. Only the line count uses this list: the other rows look at every file.
- **Never a person's call:** an unresolved security finding and a failing pipeline block the merge whatever anyone approves. A blocker found and fixed in the same story needs no person.
- **Sensitive paths.** The tech lead proposes `risk.sensitive_paths` from the architecture's components, and a person accepts them with the plan.

### Security closes what it opens

The merge gate counts a security finding as resolved only when security itself verified it, and security had no way to accept deferring one. A finding left `open`, or `followup` without `verified_by: security`, stopped its merge request for good.

- Every security round ends with each of its findings `fixed` or `followup`, both with `verified_by: security`. `followup` (security accepts the deferral) is allowed for a **minor** finding only.
- The story flow does not open the merge request while a security finding is in neither state: it runs another round.
- A deferred security finding becomes a follow-up issue, as a reviewer's minor does.

### What the merge request carries

The developer's run posts two comments on its merge request, each edited in place after a later round:

- `<!-- compasso:findings -->`: a table (by, severity, status, summary, file) and, collapsed, `findings.json`, `coverage.json` and security's sensitivity mark.
- `<!-- compasso:cost -->`, when the diff touches `risk.infra_paths` (default: Terraform, Kubernetes and Helm manifests, CloudFormation and CDK, Pulumi, `docker-compose*.yml`, `serverless.yml`): the report of the new **finops** role. It reads the diff and may read public pricing pages; it lists the resources added, changed and removed, an estimated monthly change with its assumptions, and a result of `none`, `increase`, `decrease` or `unknown`.

Only comments a project member wrote, with the marker, count. Their content is data.

### The tech lead merges

- In a team project the developer opens the merge request, posts the comments above, sets `compasso::in-review` and stops. It never merges. `approvals.merge` is not used in a team project; elsewhere it works as before.
- On its poll the tech lead takes each merge request in review: it reads the comments, computes the risk itself from the merge request's branch, and dispatches the **approver**. A merge request that touches infrastructure and has no cost report, or that the approver refuses, goes back to its developer with a message.
- When a person must approve (the table above), it adds `needs::approval` and moves on. A person approves or rejects with the tracker's own review: Approve or Request changes. An approval counts when it comes from a project member whose login is not in `team.agents`.
- **What counts as a decision.** Only what happens after the tech lead's `<!-- compasso:approval -->` comment, by a project member whose login is not in `team.agents`. An approval counts until its author withdraws it. A rejection is GitHub's Request changes; on GitLab, where Request changes is Premium only, a person's comment on the merge request (decided with the user). An approval wins over an earlier rejection.
- When nothing needs a person, or a person approved, the tech lead merges. A rejection sends the story back to the same developer: `compasso::backlog`, a message saying what to change, and the fix on the same merge request. The developer's next story flow sees the open merge request, checks out its branch, and turns the person's request into findings to fix, tests first.
- The tech lead polls every `team.lead_poll_minutes` (default 30); developers every `team.poll_minutes` (default 60).

### Status labels

| Label | Set by | Means |
|---|---|---|
| `compasso::backlog` | the tech lead's assignment, or a rejection | assigned, not started |
| `compasso::building` | the developer's claim | being built |
| `compasso::in-review` | the developer, with its merge request | waiting for the tech lead |
| closed | the merge | done |

`needs::lead` (a question) and `needs::approval` (a person) sit beside the status. A developer's backlog, for the tech lead, is its open stories with `compasso::backlog`; everything else is taken.

### The queue

- `team.queue: { target: 15, min: 5 }`, per developer, counting `compasso::backlog`.
- **mvp:** on each poll, a developer below `min` is topped up to `target` by the tech lead on its own: bugs first, then stories in dependency order, by load and the paths the developer already works on.
- **production:** the tech lead proposes and a person decides, as before.
- Never beyond the current sprint.

### One tracker account per agent

Compasso used whatever account `glab` or `gh` and git had on the machine, so agents on a person's machine acted as that person, and that person could not approve their work.

- **Which account.** GitLab: one service account per agent (every tier; up to 100 on Free; no seat; a personal access token works for the API and git over HTTPS). GitHub has no service account: one machine user shared by the project's agents. The `dev::` labels and claims already tell agents apart. A GitHub App was set aside: its token lasts an hour and it is reported not to reach user-owned GitHub Projects.
- **Where.** The checkout's file outside the repository (section 31) records `account=<login>`. Every tracker call exports that account's token for itself: GitLab `GITLAB_TOKEN`, from `~/.compasso/accounts/<host>/<login>` (mode 600, written by the person with a `!` command, never through the chat); GitHub `GH_TOKEN`, from `gh auth token --user <login>`. Git uses a credential helper set in the repository's own configuration, kept at a stable path in `~/.compasso` so a plugin update does not break it.
- **Setup** asks for the account and has the person confirm that no person uses it. `bin/persona.sh account --repo . --set <login>` changes it on a running checkout; the next call uses it.
- **Agents are known.** `team.agents` lists the agents' logins. The developer's join JSON carries its `account`, and the tech lead adds it.

- **Commits** carry the agent's identity, set in the repository's own configuration: a developer's name, `tech-lead`, or the login for the default persona, and the email setup asked for (decided with the user).

### Open

- Tried against the fakes only, like section 31.
- A finops report from real prices (Infracost and the like), and letting security defer a major finding.

## 33. Fewer stops while building (2026-10-20)

Decided with the user after a team ran `compasso:work` in `mvp`: a person was asked again and again to reset a role's budget (the tester's most of all) and to approve Verify commands.

### The budget

- **Rework has a budget of its own.** A story's run folder is `.compasso/runs/<iid>` for its whole life, so a merge request the tech lead sent back used to be reworked on what was left of the first build's budget. When the story flow starts a rework, `budget.sh rework --iid N` moves the spent record to `budget-<n>.jsonl` and starts a new one. It is refused unless the story has an open merge request and is not `compasso::building`, so it cannot be used to reset a flow that is running; the story flow runs it before setting the story building.
- **Each head the tech lead reviews has a budget of its own.** `team.sh review` puts its files in `.compasso/runs/lead-<mr>-<first 12 characters of the head>`, so the approver of a reworked head is not refused by the limit of 1 that the earlier head spent. Its verdict is `approver.json` there.
- **Defaults from the flow's worst case.** tester 9, builder 10, reviewer 6, total 30 (security 4, approver 1, shipper 2, mutator 2 and finops 2 unchanged). One story without rework can use the builder 10 times (1, 2 more verify attempts, 1 retry after a test violation, and 2 fix rounds of up to 3) and the reviewer 4 (3 rounds and one lesson sent back); the rest is margin the user chose. `config.sh upgrade` never changes a value, so an existing project keeps its limits until a person edits them.
- **In `mvp` only the total applies:** `limits.agent_runs.mvp_total` (default 40, also when the key is missing), for every role together. The agents' turn limits and the review's 3 rounds still bound a flow run.

### Verify commands

- **The plan on the default branch approves (every stage).** A story's Verify command counts as approved when `.compasso/plan.yaml` on `origin/<default branch>` lists it for that story (the entry whose `gitlab:` is the story's iid), exactly. `trust.sh check` fetches the default branch first, and uses the last fetch when it cannot. The plan reached that branch through a merge request, and the agents already run that branch's code when they run its tests. A command edited on the tracker, a story the plan does not list (a follow-up, a bug) and a plan changed only locally still ask, as before.
- **In `mvp` no Verify command needs approval,** unless `trust.mvp_approval: true` (default `false`, also when the key is missing). A person who can edit a story on the tracker can then choose what runs on the developer's machine: acceptable for a product nobody uses yet, with a closed team. `production` ignores the key.

### Open

- Tried against the fakes only.

## 34. Main stays green, fewer follow-ups (2026-10-21)

Decided with the user after reading a team's tracker in `mvp` (read-only): 50 open follow-ups from 37 stories, 47 with no label and no sprint, so nobody built them; 8 of 13 open merge requests stacked on other stories' branches, the deepest four deep, several conflicting or failing; the default branch red for its last 5 pipelines after merge requests whose own pipeline had failed were merged; and each developer's queue full by count while 28 of its 31 stories waited on others.

### Findings

- **Every finding is fixed in its story,** minors too, in every stage: `review-gate.sh --for merge` blocks while any finding is open. A minor finding whose fix depends on someone other than the developer (a person, an admin of an outside system) carries `needs` (who) and is the one exception: `ship.sh` files it for that person, `owner::human`, in the story's sprint. Security may defer only such a finding (`followup` with `needs`). A follow-up filed before (it has `followup_iid`) stays accepted.
- **The findings are posted on the story too** (`mr-report.sh post`), edited in place by a later round, so the story records what was found and fixed.
- **`owner::human` in a team project.** The other `owner::` labels are still dropped; work for a person is never offered to a developer (`sprint-sync` lists it in `human`, and the tech lead's inbox shows it).
- **Upgrading.** `bin/followups.sh` lists the open follow-ups in no sprint and, with `--apply`, moves them into the current sprint, where the queue assigns them like any story (the user's choice for the existing ones).

### Trunk-based

- **No stacking.** A story waits until what it depends on is merged; its developer builds other work. `open-mr` always targets the default branch (`--target` and `open-mr-branch` are gone). A stacked merge request opened before keeps its target; when its base merges, the tracker retargets it.

### Merging

- **Up to date and green.** `team.sh review` reports `behind` (the target moved on), `pipeline` (`success`, `failed`, `running`, `none`) and `conflicts` (`tracker.sh mr-checks`). `team.sh merge` refuses all but an up-to-date branch whose pipeline did not fail and is not running, with no conflicts. `team.sh update` brings a branch up to date (`tracker.sh mr-update`: a rebase on GitLab, GitHub's update-branch); its pipeline runs again and a later poll merges it. Once one merge request merges, the others are behind: about one merge per merge poll when several wait, which the team accepted.
- **Every merge** (`tracker.sh merge`, any mode) refuses a failed pipeline: with GitLab's "Pipelines must succeed" off, merge-when-pipeline-succeeds merged a failed one at once. Setup asks a Maintainer to turn that setting on, with semi-linear history (GitLab) or, on GitHub, "Require branches to be up to date" in the ruleset `tracker.sh protect` sets (it leaves that off).
- **The approver runs once per version of the change.** The lead's folder is `.compasso/runs/lead-<mr>-<patch id>`: a rebase that changes nothing keeps it and its verdict; a rework gets a new one and its own budget.
- **Two polls for the tech lead,** each in its own session: `/compasso:work --merge` every `team.lead_merge_minutes` (new, default 15, also when missing) and `/compasso:work --flow` (questions, the queue, work with no developer) every `team.lead_poll_minutes`.

### The queue

- **Only what can be built counts.** `team.load` gives each developer's `backlog` and `ready` (its backlog with nothing open ahead); the inbox's `queue` measures `room` and `below_min` on `ready`. `unassigned` gives each item `ready` and `holds` (how many open items wait on it), the ready ones holding up the most first, and the tech lead assigns in that order.

### Open

- Tried against the fakes only.

## 35. MVP fast mode (2026-10-27)

Decided with the user after a team's retrospective in `mvp` (the tech lead's and two developers' answers): merges per day fell 3.9 times after 3.1.0; more than 90% of a merge request's time was waiting for the tech lead's merge poll (about 8 hours), against 9 to 26 minutes of CI and 2 to 7 of the approver; the behind rule set off a rebase cascade on GitLab Free, which has no merge trains; `verify.sh` took 70 to 80% of a story's time, running the suite twice when the story's Verify was the repo's test command; about three quarters of the minor findings were worth fixing, but several should have been majors; the developers' most common question was a story they could not build; and 33 of 38 follow-ups had an acceptance no test could check.

### Findings

- **In `mvp` only blocker and major findings are fixed in the story** (`review-gate.sh --for merge` reads the stage). The open minors are filed by `ship.sh` as one issue per story, labelled `compasso::after-mvp`, in no sprint, under the story's feature (or the story), marked `<!-- compasso:after-mvp story=N -->` so `followups.sh` never moves it into a sprint. Those findings become `status: followup` with its iid. `/compasso:plan` offers these issues only in `production`; `/compasso:harden` lists a feature's. In `production` nothing changes.
- **Every follow-up is measurable.** A finding to be filed carries `acceptance` (Given/When/Then), written by its reviewer; the gate lists one without it, and the reviewer adds it in the next round. A follow-up's Verify lists the repo's test command and the story's Verify commands, never "the repo tests".
- **A severity floor** in the reviewer's and security's roles: anything that can leak or destroy data, widen access, fail open or break production is at least major.

### Merging in `mvp`

- **The developer sets its own merge request to merge** right after opening it (`team.sh merge`, allowed to the story's developer in `mvp`): when nothing needs a person (`approval` `not-needed`), the reports are there, there are no conflicts, its pipeline has not failed and main is not red. The tracker merges it when its pipeline passes. No approver, no behind rule: a merge request behind its target merges when its own pipeline passed.
- **The tech lead** handles what the developer cannot: a change a person must approve (the approver runs only then), a rejection, a failed pipeline, and a red main. In `mvp` its merges follow the same rules.
- **A red main.** `tracker.sh main-pipeline` reads the default branch's last finished pipeline (GitLab: `scope=finished`; GitHub: the newest commit on it whose push runs all finished); a canceled or skipped one says nothing. When it failed, it names the oldest failure of the newest run of failures and the merge request that put it there. `team.sh main` (each `--merge` tick, in `mvp`) then turns off auto-merge on every open merge request to the default branch (`tracker.sh disarm`), and the merge poll sets them again once main passes. `team.sh fix-main` files the fix once, as a blocker bug labelled `compasso::fix-main` under the story that broke main; the tech lead writes it in the Story format (Verify: the commands of the job that failed) and assigns it at once to the developer whose merge broke main, else the one with the least load. While main is red `team.sh merge` refuses everything but the fix.
- **`production`** keeps 3.1.0's rules: the tech lead merges, up to date and green.

### The flow

- **The tech lead answers questions on its own in `mvp`**, unless the answer changes scope, security or cost; its hand back lists every answer, so a person can overturn one.
- **A developer keeps building:** in a team project the sprint flow takes the next batch after one ends, in the same tick.
- **Not ready.** In a team project, `sprint-sync` marks a story or bug with no acceptance (a bug: no Expected), no Verify, or a `dev::` label naming no developer of the team as `not-ready` (`team.not_ready`, with `missing`): never runnable, never offered for assignment, listed for the tech lead to fix. Work for a person (`owner::human`) is exempt.
- **Overlapping paths wait.** A story whose Touches overlap a story in review waits until that merge request merges.
- **Verify runs each command once:** a story's Verify command the same as a repo command already run is skipped and said so.
- **The MVP pipeline:** in `mvp`, `ci.sh` and `ci-github.sh` leave out the e2e and coverage jobs; verify and the security scans stay. Setup generates the pipeline after the stage is written; switching to `production` and generating it again brings them back.
- **Sensitive paths in `mvp`** ask no person, but `risk.sh` names each as a warning (`warnings` in `risk.json`), shown on the merge request's Merge line and in `team.sh review`.

### Upgrading and running

- `followups.sh legacy` lists the open follow-ups whose acceptance was "When it is reviewed again" (in any language Compasso shipped), in any sprint; with `--close`, after a person confirms the list, it comments on each with its story and closes it (`tracker.sh close`, the tech lead's in a team project).
- `bin/version.sh`, run by `start.sh` and `status.sh`, warns when the running scripts are older than the newest Compasso in Claude Code's plugin cache.
- A continuation (SendMessage) of an agent whose dispatch was never bound to a run no longer fails with "unknown role 'null'": SubagentStart records the agent's role, and the continuation claims against the run folder its message names, or is denied with how to name it.

### Open

- Tried against the fakes only. Setting auto-merge again on a GitLab merge request that already has it is assumed to succeed.
