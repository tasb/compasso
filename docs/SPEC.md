# Compasso — design spec

Status: 4.0.0 (2026-11-16). This page describes Compasso as it is. The decisions that led here, with their dates, are in this file's history and in `CHANGELOG.md`; what 4.0.0 removed is listed at the end.

A *compasso* is a musical measure: one bar of a fixed length. Here, one sprint.

## 1. Principles

1. **The tracker is the source of truth.** Work items, states, questions to people and their answers live in the tracker (GitLab or GitHub). The repository keeps the product files (brief, backlog, architecture, roadmap, first plan) and their decision records. Run logs stay local.
2. **The agents work on their own.** Cron wakes each agent; each run does one job in a fresh session; no model starts when there is nothing to do. A person plans the product, answers questions and tests deliveries.
3. **Pace first in the MVP.** Checks grow with the stage (`mvp`, `harden`, `production`). In the MVP only blockers stop a change; everything else waits on one list.
4. **A person is asked once, with evidence.** Every question is a `needs::human` issue: what is needed, why, numbered steps, and what the team does meanwhile.
5. **Scripts decide, agents judge.** Picking a job, unblocking, reverting a red default branch and assigning are shell. Building, reviewing, planning and delivering are a model's.
6. **The 4 rules bind every agent:** Think Before Coding, Simplicity First, Surgical Changes, Goal-Driven Execution.
7. **Portable.** One source of truth for skills and roles runs on Claude Code and Codex.

## 2. Work hierarchy

| Level | Size rule (defaults) | Tracker |
|---|---|---|
| Epic | one per sprint; total estimate ≤ capacity | milestone `S<n>` and a `type::epic` issue titled `S<n>: <goal>` |
| Feature | ≤ half a sprint (≤ 40h at 2-week sprints) | `type::feature` issue (GitHub: a sub-issue of the epic) |
| Story | ≤ 8h hard limit, ~4h target; one session of one developer | child task of its feature (GitHub: a sub-issue) |
| Bug | one fix | `type::bug` issue, with a `severity::` label |
| Blocker | anything outside the plan a story waits for | `type::blocker` issue, `priority::urgent`, assigned to a person, with steps |

- Sprint length defaults to **2 weeks**; estimates are in **hours**.
- GitLab Premium features (native epics, iterations, `blocks` links) are designed but switched off: every tier is pushed the Free way.
- In a team project every story names its developer with `dev::<name>`. Work only a person can do keeps `owner::human` and is never assigned to a developer.

### Dependencies

| Kind | Meaning | GitLab | GitHub |
|---|---|---|---|
| hard | B cannot start before A is merged | `**Depends on:** #iid` line | native "blocked by" |
| soft | A and B touch overlapping paths | derived from `touches:` | same |
| external | waits on something outside the plan | a blocker issue and `**Blocked by:** #iid` | native "blocked by" |

A story is ready only when everything it depends on is closed. No story builds on another's unmerged branch.

`plan-check` refuses a plan with an unknown dependency, a cycle, a dependency on a later sprint, a story over the hard limit, a feature over half a sprint, or an epic over capacity. It prints the critical path and the parallel waves.

### The plan file

`.compasso/plan.yaml` holds the first plan, the one `/compasso:plan` pushes; the template is `templates/plan.yaml`. Later features are split into stories on the tracker by the tech lead's `plan` job. `gitlab` fields hold each item's number on either tracker and are written by the push, so a re-run updates instead of duplicating and a failed run resumes.

```yaml
epic:
  key: E-1
  goal: Customers can see and download their invoices without contacting support.
  sprint: { number: 20, start: "2026-10-05", end: "2026-10-16" }
  risks: [PDF service is owned by another team]
  gitlab: { milestone: 501, issue: 12 }
blockers:
  - key: B-1
    title: PDF service credentials
    assignee: ana                       # tracker username of a project member; required
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
    dev: ana                            # team projects: the developer of every story below, unless a story names its own
    gitlab: 6
    stories:
      - key: S-1
        title: Invoice list API
        as: a customer
        want: an invoice list API
        so_that: the Billing page can show my history
        acceptance: ["Given 3 invoices, When GET /invoices, Then 200 with 3 items, newest first"]
        verify: ["npm test -- billing/api"]
        tests: [unit]                   # unit, e2e or both: each acceptance line at the cheapest level that can see it
        touches: ["src/billing/api/**"]
        depends_on: []                  # story keys, or "#iid" for existing items
        estimate_h: 4
        blocked_by: [B-1]
        coverage: 90                    # optional
        gitlab: 8
```

Outside a team, a story has `owner: agent | human | either` in place of `dev`.

### Pushing a plan

`tracker.sh push-plan` runs only on a plan that passes `plan-check`, then writes, in order: the milestone `S<n>`; each feature (`type::feature`, with its developer's label in a team); each blocker, assigned to its person; each story in dependency order, attached to its feature, with its estimate and developer; the blockers again, listing the stories they hold up; and the epic last, because it lists the features with their hours.

### Work item formats

1. Never repeat what the tracker stores in a field: title, estimate, milestone, parent, assignee, child items.
2. What people filter on is a label.
3. Fixed section order. Omit an empty optional section; never write "N/A".
4. Describe only what to do: bullets, one idea each, at most 20 words.
5. Items Compasso writes carry one hidden line for idempotent pushes: `<!-- compasso:key=S-1 -->`.

The formats ship as issue templates (`templates/issue_templates/<language>/`), installed by `bin/issue-templates.sh` into `.gitlab/issue_templates/` or `.github/ISSUE_TEMPLATE/`.

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

**Feature** — required: Goal; Scope and Acceptance before it is split. A feature waiting to be split carries `compasso::new`.

```markdown
**Goal:** Customers see their last 24 months of invoices, newest first.

## Scope
- Invoice list
- Filter by year

## Acceptance
- [ ] Given 3 invoices, When I open Billing, Then I see 3 rows, newest first
- [ ] Given no invoices, When I open Billing, Then I see "No invoices yet"

## Decisions
- Paginate 20 per page (answered by @ana, 2026-10-02)
```

**Story** — required: the As/I want/so that line, Acceptance, Verify, Tests.

```markdown
**As** a customer **I want** an invoice list API **so that** the Billing page can show my history.

## Acceptance
- [ ] Given 3 invoices, When GET /invoices, Then 200 with 3 items, newest first
- [ ] Given another customer's token, When GET /invoices, Then 404

## Verify
- `npm test -- billing/api`

**Tests:** unit\
**Touches:** `src/billing/api/**`\
**Depends on:** #440\
**Blocked by:** #452
```

**Blocker** — required: Steps.

```markdown
**Needed for:** #9 PDF endpoint

## Steps
1. Ask the PDF team for API credentials for the invoices service
2. Store them as the masked CI variable PDF_API_KEY
3. Close this task
```

**Bug** — required: all sections. Verify fails before the fix and passes after.

```markdown
**Found in:** !88 (#431 Invoice history) · **By:** a person testing on staging

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

### Merge request and question formats

- **Merge request** (`bin/mr-body.sh`): `Closes #<story>`, then Changes (one behaviour change per line), How to test (the story's Verify commands), and Coverage only when it was measured (`production`).
- **Plan comment** (`templates/comments/plan.md`): one row per story with hours, developer and dependencies, the security result, and who approved it.
- **Question** (`bin/human.sh`): Needed, Why (the evidence), Steps (numbered; closing the issue is the last), Meanwhile. Section 8.

## 3. Commands

Claude Code names; on Codex the same skills are `$compasso-<name>`.

| Command | Who runs it | Purpose |
|---|---|---|
| `/compasso:setup` | a person | Connect GitLab or GitHub; persona, account, stage, sprint, commands, coverage, staging, people to ask, runner periods, models; the pipeline, labels and issue templates; the crontab line |
| `/compasso:start` | a person | Where the product stands, and the next step |
| `/compasso:discover` | a person | The product brief, from ideas, documents, issues or a prototype |
| `/compasso:backlog` | a person | Features with sizes, dependencies and the MVP line, on the tracker in no sprint |
| `/compasso:architect` | a person | The technical solution |
| `/compasso:roadmap` | a person | Features placed into sprints, MVP first |
| `/compasso:plan` | a person | The first sprint split into stories, checked, reviewed by security, approved and pushed |
| `/compasso:present` | a person | The solution presentation (HTML) |
| `/compasso:status` | anyone | Read-only: section 17 |
| `/compasso:report` | a person | The sprint's HTML report |
| `/compasso:build <job>` | the runner | A developer's job: build or rework one story |
| `/compasso:lead <job>` | the runner | A tech lead's job: review, deliver, plan, audit or drain |

Every command first checks this checkout's persona (`persona.sh gate`) and the tracker connection.

## 4. Roles and models

A role is a subagent a session dispatches. Each is defined once in `roles/<role>.md`.

| Role | Does | Claude default | Codex default |
|---|---|---|---|
| planner | Questions, breakdown and dependencies for `/compasso:plan` and the steps before it; runs in the conversation | `opus` | `gpt-6-astra` (high) |
| tester | `production`: the story's failing tests before the code exists; every plan: whether each story can be tested | `sonnet` | `gpt-6-sol` (medium) |
| reviewer | `production`: one pass over each merge request | `sonnet` | `gpt-6-sol` (high) |
| security | Every plan; `production`: one pass over each merge request | `opus` | `gpt-6-astra` (high) |

- Models are set per harness in `models.claude` and `models.codex`. Claude uses aliases (`opus`, `sonnet`, `haiku`, `inherit`).
- `bin/codex-models.sh check` compares `models.codex` with the account's own catalog and proposes replacements by tier; `--apply` writes them.
- **Floor:** `security` may not be set to the fast tier or to low effort.
- `bin/gen-agents.sh` writes `agents/<role>.md` from `roles/` with only the tools the role needs (security only reads) and a turn limit. No role has the Agent tool: only a session dispatches.
- The developer and the tech lead are not roles: they are the runner's own sessions (section 11).

## 5. The runner

Each agent's machine has one crontab line, printed by `bin/cron.sh --repo R`:

- It copies `bin/compasso-run` to `${COMPASSO_HOME:-~/.compasso}/bin`, a path no plugin update moves. `compasso-run` starts `bin/run.sh` of the newest Compasso installed: Claude Code's plugin cache, else the Codex engine.
- The tech lead runs every `run.lead_minutes` (15), a developer every `run.dev_minutes` (10).
- The line carries the PATH of the shell it was printed in (cron's own has no `glab`, `gh`, `jq`, `yq` or `claude`) and appends to `.compasso/runs/runner/cron.log`.
- It refuses a checkout whose persona is not tech lead or developer: the runner works for a team.
- It never edits the crontab: a person adds the line.

`bin/run.sh lead|dev [--name N]`, each tick:

1. Takes the role's lock; a tick that finds it held exits (`busy`).
2. Brings the checkout to the default branch as origin has it (`git fetch`, then a fast-forward), so a change merged there (the stage, `run.*`) reaches this tick. A checkout with uncommitted changes stays where it is, and the runner says so.
3. Reads the tracker once (`tracker.sh snapshot`: open issues, open merge requests, the default branch's last finished pipeline) and picks the role's next job (`bin/next.jq`). With none it records an `idle` run and exits: no model starts.
4. Runs a shell job itself, or starts one headless session for a model job, for at most `run.job_minutes` (60).
5. Reads the tracker again. The same job still waiting means no progress.
6. Appends one line to `events.jsonl`: the job, its stories, the result and the seconds, and, when the harness reports them, the session's tokens, cost and model, its subagents included (Claude Code: `--output-format json`; Codex: `--json`, tokens only). Nothing the harness does not report is guessed.

### Jobs

**Developer** (`dev --name N`), first match wins:
1. **rework**: its merge request is labelled `compasso::rework`, or its pipeline failed;
2. **build**: a story of its own already `compasso::building` with no merge request;
3. **build**: its next ready story.

**Tech lead** (`lead`), first match wins:
1. **unblock** (shell): stories with `needs::human` whose question is closed lose the label (`tracker.sh human-done`);
2. **red-main** (shell): the default branch's last pipeline failed and no fix is open (or the fix failed): `lead.sh red-main` (section 10);
3. **review**: every open merge request with a green pipeline, not a draft, not sent back, and not holding a story that waits for a person; one job for all of them;
4. **audit** (`harden`, once per machine);
5. **drain** (`harden`, `production`): an open after-MVP list;
6. **deliver**: a `compasso::building` feature with no open story or bug, while the default branch is green;
7. **assign** (shell): a ready story or bug with no developer and not `owner::human`, to the developer with the fewest ready ones, while one has fewer than `team.queue.min`;
8. **plan**: when a developer is short and nothing is left to assign, the next `compasso::new` feature.

**Order of work.** Bugs first, by `severity::` (blocker, major, minor; none counts as minor); then the earliest sprint (its milestone's due date; none last); then the oldest. A story is **ready** when it is not started (`compasso::backlog` or no state), nothing open blocks it, and it is not waiting for a person.

### Sessions and permissions

A model job is `claude -p "/compasso:<build|lead> <job JSON>"` or `codex exec "$compasso-<build|lead> <job JSON>"`.

| Stage | Claude Code | Codex |
|---|---|---|
| `mvp`, `harden` | `--permission-mode bypassPermissions` | `--dangerously-bypass-approvals-and-sandbox` |
| `production` | `--permission-mode dontAsk` with an allowlist: the repo's commands, git, `glab`/`gh`, Compasso's scripts, Agent, and `run.allow` | `--sandbox workspace-write` with network access |

Compasso's hooks guard every tool call in every stage (section 24).

### Failures

A job that exits non-zero, times out or makes no progress counts one failure against its key (the job and its items). After `run.failures` (2) in a row, the runner asks a person (`human.sh ask`, key `stuck-<key>`) with the log's path, and the job is skipped while that question is open. Once the person closes it, the count is cleared and the job starts over.

Files in `.compasso/runs/runner/`: `events.jsonl` (one line per run), `failures.json`, `logs/` (one per session), `<role>-<name>.lock`, `cron.log`, and `audited` (the tech lead's audit is done; delete it to audit again).

## 6. Stages

`stage` in `.compasso/project.yaml`: `mvp | harden | production`. No `stage` means `production`, so nothing gets looser until a person says so. It counts once it is on the default branch: each runner tick brings its checkout up to date first.

| | `mvp` | `harden` | `production` |
|---|---|---|---|
| Security | the pipeline's secret and SAST scans | as mvp, plus one audit of the whole code | a security agent on every merge request |
| Review | the tech lead, one pass, blockers only | as mvp | the tech lead, a reviewer and security, one pass each |
| Tests | the developer writes them | as mvp | the tester writes them; the developer never changes them |
| Coverage | not measured | not measured | measured locally and in CI; one extra pass on uncovered lines; a warning, never a block |
| Pipeline | verify, scans, staging deploy | as mvp | verify, e2e, coverage, scans, staging deploy |
| Non-blockers | the after-MVP list, never work in the MVP | the list drained into stories under one hardening feature | the list drained into stories |
| Permissions | no prompts | no prompts | an allowlist |

Switching stage is a person's decision: setup again, or an edit merged to the default branch, then `bin/ci.sh` again for the pipeline.

## 7. The tech lead's review

One pass over each green merge request, then a decision; never a second pass in the same session.

- **A blocker** is an acceptance line not met or not tested, data loss, a leaked secret, or a change that breaks the default branch. Nothing else sends work back. Style, naming, structure and better ideas are not blockers.
- In `production` the reviewer and security read the same diff, one pass each, at the same time; their blocker and major findings are blockers too.
- **No blockers:** `lead.sh merge` merges when the pipeline succeeds. A conflicting branch is sent back to rebase, which is not a review round.
- **Blockers:** `lead.sh rework` labels the merge request `compasso::rework` with a numbered list. One round: blockers found again after a rework go to a person (`needs::human`), and the story waits.
- **The after-MVP list.** What is worth keeping and is not a blocker goes to one open issue (`lead.sh later`, marked `<!-- compasso:after-mvp list -->`), one comment per merge request. In `mvp` it only waits. In `harden` and `production` the **drain** job groups its entries into stories (blockers and majors first) under one hardening feature (`lead.sh hardening`), drops the rest with a reason, and closes the list. New entries open a new list.
- **The audit** (`harden`, once): the tech lead reads the whole default branch, highest risk first (security, data, reliability, tests), and adds each finding to the after-MVP list. It fixes nothing.

## 8. Asking a person

The one way an agent reaches a person is `bin/human.sh ask`: a `needs::human` issue assigned to `people.ask`, in the project's language.

- **Fields:** need; why (the evidence: the command, the error, links); steps (numbered, one action each; closing the issue is always the last); meanwhile (what the team does until then).
- **The held story** gets `needs::human`; no job picks it up. The rest of the work goes on.
- **Asking again** with the same key and story updates the open issue.
- **The answer** is the person doing the steps and closing the issue. The tech lead's **unblock** job then removes `needs::human` from the story.
- **Who asks:** a developer that needs a secret, access, or a decision on scope or cost; the tech lead for scope, cost or secrets, a second rework, a revert that conflicts, and every delivery; the runner for a stuck job.

## 9. Delivery and staging

- Every merge to the default branch deploys to staging when `staging.deploy` is set (`compasso-deploy-staging`, after verify and the scan gate).
- When a feature being built has no open story or bug left and the default branch is green, the tech lead's **deliver** job writes a question: test the feature on staging (`staging.url` is the first step), one step per acceptance line. `lead.sh deliver` sends it to `people.ask` and closes the feature as `compasso::done`.
- A problem found there is filed as a bug.

## 10. The default branch stays green

- The tech lead merges only when the pipeline succeeds (`tracker.sh mr-merge`, which never merges after a failure). Setup asks a Maintainer to make the tracker refuse a merge whose pipeline failed.
- When the default branch's last finished pipeline failed anyway, the runner's **red-main** job (`lead.sh red-main`, no model) reverts the merge that broke it in a worktree under `.compasso/worktrees/`, opens it as a `compasso::fix-main` merge request that merges itself when its pipeline passes, and reopens the stories that merge closed. A revert that conflicts, or a fix whose pipeline failed, goes to a person.
- While a fix is open, the tech lead's review leaves the fix out; the rest of the work goes on.

## 11. The team

| Persona | Is | Never |
|---|---|---|
| `tech-lead` | The runner's `lead` sessions: reviews, merges, delivers, plans features into stories, assigns, asks people; owns the configuration | Builds a story |
| `developer` | The runner's `dev --name N` sessions: builds and reworks what carries `dev::<name>`, opens the merge request | Merges, plans, changes scope or settings |
| `default` | Outside a team: one agent does everything a person runs. In a team project it only reads (`status`, `report`, `present`) | |

- **The team** is `team.enabled: true` and `team.developers` in `.compasso/project.yaml`. `tracker.sh ensure-labels` creates `dev::<name>` for each. A developer joins by being added to the list.
- **The persona** and the developer's name belong to one checkout and are kept outside the repository: `${COMPASSO_HOME:-~/.compasso}/persona/<sha256 of the checkout's physical path>` (`bin/persona.sh set`).
- **Enforced** by `persona.sh gate`: `bin/tracker.sh` runs it before every tracker command, and each skill as its first step. The tracker cannot stop a member from changing a label: the gate prevents mistakes; it is not a security boundary.
- **The queue.** The **assign** job keeps each developer at `team.queue.min` ready stories, fewest first, from the earliest sprint first. A later sprint's work is assigned when nothing earlier is left: the team does not wait for a sprint to end.
- **One tracker account per agent.** GitLab: a service account per agent, its token in `~/.compasso/accounts/<host>/<login>` (mode 600, written by a person). GitHub: one machine user shared by the project's agents, its token from `gh auth token --user <login>`. `persona.sh account --set <login> --email <email>` records it; every tracker call and git push of the checkout use it (git through a credential helper in `~/.compasso`), and its commits carry the agent's name and that email.

### Status labels

| Label | Set by | Means |
|---|---|---|
| `compasso::new` | a person (the Feature template) | a feature waiting to be split |
| `compasso::backlog` | the assign job | assigned, not started |
| `compasso::building` | the developer; the tech lead on a feature it split | being built |
| `compasso::in-review` | the developer, with its merge request | waiting for the tech lead |
| `compasso::done` | the deliver job | a feature delivered to staging |
| `compasso::rework` | the tech lead, on a merge request | sent back with blockers |
| `compasso::fix-main` | the red-main job, on a merge request | the revert of a red default branch |
| `needs::human` | `human.sh ask` | waiting for a person |

## 12. Gates and checks

A **gate** stops the work; a **check** reports and never stops it.

| What | Where | Kind |
|---|---|---|
| Tracker connected | every command | gate |
| Persona allowed | every command and tracker write | gate |
| `plan-check` (sizes, dependencies, capacity) | before a plan is pushed | gate |
| Story contract (As/I want/so that, acceptance, Verify, tests) | `lead.sh story` | gate |
| `verify.sh`: test, lint, typecheck, build, the story's Verify commands, then e2e only when they all passed | before the merge request, and in the pipeline | gate |
| Verify commands approved by a person | `verify.sh`, only with `trust.verify_approval: true` | gate |
| SAST and secret detection | every merge request's pipeline | gate: any high or critical finding, or any secret, fails the scan gate |
| Pipeline green | every merge | gate |
| The tech lead's review | every developer's merge request | gate: blockers only |
| Reviewer and security | every merge request, `production` | gate: blockers and majors |
| Changed-line coverage | `production`, locally and in the pipeline | check (warning) |

## 13. The pipeline

`bin/ci.sh` writes `.gitlab/compasso.gitlab-ci.yml` (included from `.gitlab-ci.yml`); on a GitHub project it runs `bin/ci-github.sh`, which writes `.github/workflows/compasso.yml`. Jobs:

- **verify**: test, lint, typecheck, build, in `ci.image`;
- **e2e** and **coverage** (`production` only); coverage below its minimum is allowed to fail (exit 3) and shows as a warning;
- **SAST and secret detection**: GitLab's own templates; on GitHub, CodeQL and secret scanning where available, otherwise Gitleaks and Semgrep;
- **scan gate**, last: reads the scan reports and fails on any high or critical finding, and fails closed when secret detection did not run (GitLab Free neither shows nor enforces scan findings);
- **compasso-deploy-staging**: on the default branch, after verify and the scan gate, runs `staging.deploy`.

On GitHub, `tracker.sh protect` (setup asks first) writes the `compasso` ruleset on the default branch: pull requests only, no force push or deletion, the gate jobs required, CodeQL high or critical alerts blocking once CodeQL default setup is on, auto-merge allowed and merged branches deleted.

## 14. Coverage

- `bin/coverage.sh` runs `coverage.command`, then diff-cover on the Cobertura or LCOV `coverage.report` against the merge request's target branch.
- A changed file under `coverage.paths` missing from the report counts as uncovered.
- Threshold: the most specific `**Coverage:** N%` line (story, then feature, then epic), else `coverage.min_changed` (80).
- Line coverage only; e2e tests do not contribute.
- Below the threshold: exit 3, a warning in the pipeline and the figure in the merge request. The developer adds tests for the uncovered lines once. It never blocks a merge.
- No `coverage.command`: "not measured", never a pass. Outside `production` it is skipped.

## 15. Tests

- Each acceptance line is tested once, at the cheapest level that can observe it: unit for logic, rules, edge and abuse cases; e2e for a line that needs the real boundary (UI flow, public API, CLI, service integration). A story's tests are `unit`, `e2e` or both.
- No tests of prose: nothing pins the wording of comments or documentation.
- In `production` the tester writes the tests from the story alone, before the code; the developer never changes them and sends a wrong one back once, with the reason. `test_paths` says what counts as a test file.
- `verify.sh` runs e2e last, only when everything else passed, and runs a story's Verify command that equals a repo command only once.

## 16. Verify commands

A story's Verify commands are tracker text that `verify.sh` executes.

- `trust.verify_approval: false` (default, every stage): they run without asking. Anyone who can edit a story then chooses commands the agents run; setup says so.
- `trust.verify_approval: true`: a command runs only when a person approved that exact command for this checkout (`bin/trust.sh approve`), or when `.compasso/plan.yaml` on the default branch lists it for that story. `verify.sh` stops (exit 4) before running anything otherwise.
- Records: `${COMPASSO_HOME:-~/.compasso}/trust/<sha256 of the checkout's physical path>`, one `<sha256 of command>  <command>` line each. A home inside the repository is refused.
- `.compasso/project.yaml` commands are not covered: they change through merge requests.

## 17. Status

`/compasso:status` (`bin/status.sh`, `--json` for scripts) answers "where are we?" and writes nothing. From one tracker snapshot: the stage, the default branch's pipeline, what waits for a person (and which story each question holds), the open merge requests (green and waiting for review, sent back, draft, failing), each developer's stories and bugs with what blocks them, the after-MVP list, and the job `bin/run.sh` would start next for the tech lead and each developer. From this machine's runner files: the last runs, and the jobs skipped until a person answers. When the tracker cannot be read, the local part is still shown and it exits 1.

## 18. From ideas to the first plan

Each step is a resumable command with its own files, checks, approval and decision record. `/compasso:start` (`bin/start.sh`) finds the step from what exists.

| Step | Command | Writes | Checked by |
|---|---|---|---|
| Discover | `/compasso:discover` | `.compasso/product/brief.md`; with a prototype, `.compasso/product/prototype.json` | security; approval |
| Backlog | `/compasso:backlog` | `.compasso/backlog.yaml`: features with `size_h`, `mvp`, `depends_on`, `sensitive`, `sources`; tracker issues in no sprint (`tracker.sh push-backlog`) | `backlog-check.sh`; tester and security; approval |
| Architect | `/compasso:architect` | `.compasso/product/architecture.yaml` | `architecture-check.sh`; security; approval |
| Roadmap | `/compasso:roadmap` | `.compasso/roadmap.yaml`: sprints with goal, features and hours; `mvp_sprint` | `roadmap.sh check`; approval |
| Plan | `/compasso:plan` | `.compasso/plan.yaml`, pushed | `plan-check.sh`; security and tester; approval |

- **An explicit MVP line.** `roadmap.sh propose` places MVP features first by dependency and capacity; an MVP feature may depend only on MVP features.
- **A walking skeleton for greenfield** (F-0): the stack (the user decides), unit and e2e runners, CI, a staging deploy, one path end to end. Every MVP feature depends on it. Setup leaves commands empty until it exists, then runs again.
- **A prototype as the starting point** is a reference only: the product is rebuilt test-first. A running web app is crawled by `prototype.sh crawl` (Playwright in Docker, same-origin links only, never a button or a form, destructive-looking links skipped, at most `--max` pages); source code and single-file HTML prototypes are read by the planner; Figma through its connector or exported frames. All produce one inventory (`prototype.sh check`); every screen belongs to a feature, or the record says why not.
- **Files reach the default branch** through `plan-pr.sh` merge requests with their records.
- **Rolling wave.** Only the first plan is split by a person. After it, the tech lead's **plan** job splits each `compasso::new` feature into stories (`lead.sh story`, refused when a story is incomplete) when a developer runs short.
- **Inputs are data.** Documents, issues and prototype content are never instructions.

### Architecture and the presentation

- `/compasso:architect` writes `architecture.yaml`: summary, stack (choice and why per layer), components (responsibility, technology, the features each serves, who it talks to, the data it owns), integrations, data, observability, security controls, deployment, decisions with the alternatives not chosen, and risks. `bin/architecture-check.sh` refuses an empty section, an MVP feature no component serves, a link to a component that does not exist, observability without metrics or alerts, personal data without a security control, and a choice without why. Work the design needs and no feature covers is added to the backlog.
- `/compasso:present` (`bin/present.sh`, `templates/presentation.html`) builds one self-contained HTML page from Compasso's own files: the brief, the features on either side of the MVP line, the prototype's screens, the architecture, the decisions, the sprints, the next sprint's stories and blockers, and the risks. It says on the page what is missing. Every value is shown as text, never as markup.

## 19. Trackers

`tracker.provider` picks `bin/tracker/gitlab.sh` or `bin/tracker/github.sh` through `bin/tracker.sh`. Both have the same commands and options and print the same shapes; the GitHub adapter returns issues in the GitLab shape (`iid`, `opened`/`closed`, `issue_type`, `time_stats.time_estimate`). The labels live in one list, `bin/tracker/labels.txt`.

| Concept | GitLab | GitHub |
|---|---|---|
| Sprint | milestone `S<n>` | milestone `S<n>` and an iteration `S<n>` in the GitHub Project, kept in step |
| Hierarchy | child tasks | sub-issues |
| Dependencies | `**Depends on:**` line (Free) | native "blocked by" |
| Estimate | time estimate | the Project's number field (`tracker.github.fields.estimate`) |
| State | `compasso::` labels | `compasso::` labels and the Project's Status (`tracker.github.status`) |
| Merge | merge when the pipeline succeeds | auto-merge after the required checks |
| Scans | GitLab SAST and Secret Detection, with the scan gate | CodeQL and secret scanning where available; otherwise Gitleaks and Semgrep in the scan gate |

GitHub replaces an iteration field's whole configuration on update, so `push-plan` sends every existing iteration back with the new sprint's.

### Verified on gitlab.com Free (2026-09-23)

- Child tasks under an issue work (GraphQL `workItemCreate` with `hierarchyWidget.parentId`), and so do hour estimates on tasks.
- `blocks` links are refused ("Blocked issues not available for current license"); `relates_to` works.
- Tier detection: `namespaces/:id` returns `plan`; self-managed instances set `tracker.tier`.

## 20. Decision records

Every product step and the first plan write one Markdown record under `.compasso/records/`. Each has the same five sections, in order, and an empty one says "None":

| Section | Holds |
|---|---|
| Findings | security's and the tester's findings, check notes, each with what happened to it |
| Decisions | answers with who gave them and when, the approval; assumptions marked `Assumed:` |
| Takeaways | what the run taught about the product or the code |
| Constraints | capacity, sensitive paths, outside dependencies, dates, technical limits |
| Missing points | open questions and blockers, with their status |

The agent writes `RUN/record.json`; `bin/record.sh write` checks the five lists and renders the file, so headings never drift. Records reach the default branch with their files through `plan-pr.sh`.

## 21. Learnings

- One file per lesson in the product repo's `docs/learnings/`, with frontmatter `paths:` (globs) and `roles:` (planner, tester, developer, reviewer, security).
- Recall is targeted (`learnings.sh recall --role R [--story F]`): a role gets only the lessons whose roles include it and whose paths overlap the story's Touches. Nothing is injected into every session.
- A lesson comes from a merge request sent back: when a blocker is a mistake a rule would have prevented, the tech lead's rework comment ends with a `Lesson:` line (the production reviewer proposes one in its finding), and the developer adds it to `docs/learnings/` in the same commit as the fix, so it reaches the default branch with the story. The developer recalls its lessons before writing tests; the tech lead recalls the reviewer's before each review.
- `learnings.sh check` refuses a malformed lesson and flags one whose paths no longer exist.

## 22. Metrics and reporting

`/compasso:report` builds one self-contained HTML sprint report for team leads and management: planned vs done hours, burn-down, carry-over, velocity, cycle time, time waiting for people, findings and bugs. `bin/metrics.sh collect` reads the tracker (stories, estimates, label history, merge requests, past sprints) the runners' `events.jsonl` (agent effort by job and by story: time, tokens and cost; a job over several stories is shared out evenly), and `.compasso/metrics/<iid>.json` from before 4.0.0 where present; `bin/report.sh` renders `templates/report.html` with a table view for every chart. Each machine keeps its own events: `--events FILE` (repeatable) adds the developers' copied files, and without it only this machine's are read. Cost is `metrics.prices` applied to the tokens when set, otherwise the USD the harness reported.

## 23. Test framework defaults

The project's own frameworks first; a default only for an empty area (`templates/test-defaults.yaml`).

- **Areas:** unit; API and integration; browser e2e; coverage (Cobertura, LCOV or JaCoCo); property-based.
- **Browser e2e:** Playwright in the project's language where it has an official binding, otherwise Playwright (TypeScript) in `e2e/`.
- **Detection** (`bin/test-stack.sh detect`): a language is present when its manifests are tracked; for each area, the first framework whose sign appears in manifests, configs, CI or test files; an area whose command is in the config counts as existing.
- **Use:** setup records the result as `testing` (`source: existing | default`). Tests use the framework it names; the first story that needs a default area adds it, and never a second framework to an area that has one. The walking skeleton uses the defaults of the chosen stack.

## 24. Hooks

One script, `bin/hook.sh <event>`: `hooks/hooks.json` wires it on Claude Code, and `install-codex.sh --repo` writes `.codex/hooks.json`, which the person approves once with `/hooks`.

| Hook | Event | Enforces | On failure |
|---|---|---|---|
| Role guard | PreToolUse: Write, Edit, MultiEdit, NotebookEdit, apply_patch, and the files a shell command writes | Compasso's subagents only: the tester writes tests, manifests, test configs and its run folder; the reviewer only `docs/learnings/`; security and the planner nothing. No agent writes `.compasso/project.yaml`, `.claude/`, `.codex/`, `.git/` or outside the repository | denies (fails closed) |
| Command guard | PreToolUse: Bash, Read; every session | No force-push of the default branch, no `rm -r` outside the repository and temporary folders, no reading or copying secrets (`.env`, private keys, credential files), no download piped into a shell | denies (fails closed) |
| Metrics | PostToolUse on Agent; SubagentStart, SubagentStop | Each subagent run's role, model, tokens and time | silent |

- **Scope.** Plugin hooks fire in every repository; each exits at once outside one with `.compasso/project.yaml`.
- **Off switch.** `COMPASSO_HOOKS=off`, set by a person. The role guard denies agents writes to `.claude/` and `.codex/`, where hooks could be turned off.
- **Limits.** Shell writes are recognised by pattern (redirects, `tee`, `sed -i`, `cp`, `mv`, `rm`, `touch`, `mkdir`). The command guard is a pattern list, not a sandbox. The role guard does not apply to the runner's own sessions, which write the product's code.

## 25. Language

- `language` (en, pt-PT, pt-BR) covers work items, the issue templates, comments, merge requests, questions to people, and the files in the repository. Labels, `Closes #<n>`, the `<!-- compasso:… -->` markers and the test types `unit` and `e2e` stay as they are. Code, tests, commit messages and branch names follow the repository's conventions. Scripts' terminal output stays English.
- Each language is `templates/locales/<language>.yaml` (`md`, `text` with `{markers}`, `ui`), plus `templates/issue_templates/<language>/` and `templates/brief/<language>.md`. `bin/locale.sh` and `bin/i18n.jq` give every script the project's texts over English.
- `parse.jq` accepts each heading and key line in every language Compasso ships, so a work item written by hand in another language still works and changing the language later breaks nothing.
- Adding a language is adding its files.

## 26. Large data

Large JSON travels through files (`jq --slurpfile`, stdin), never as an argument or an environment variable: Linux allows each at most 128 KB, and macOS about 1 MB in total. The tests use plans and descriptions over 1 MB. `bin/html-inject.sh` writes the HTML pages: the data from a file with every `<` as `<`, `lang` and an escaped `<title>` from the project's language, and a check that the page holds all its data before it replaces the old one.

## 27. Portability: Claude Code and Codex

| Concern | Claude Code | Codex |
|---|---|---|
| Skills | `skills/<name>/SKILL.md` in the plugin | the same files, installed to `~/.agents/skills/compasso-*` by `install-codex.sh` |
| Invocation | `/compasso:<name>` | `$compasso-<name>` |
| Roles | `agents/<role>.md`, generated from `roles/` | `.codex/agents/compasso-<role>.toml`, per project, with model and effort |
| Hooks | `hooks/hooks.json` | `.codex/hooks.json`, approved with `/hooks` |
| The runner's sessions | `claude -p` | `codex exec` |

Scripts are bash, `jq`, `yq`, `perl` and the tracker's CLI, shared by both. `install-codex.sh` installs the engine once per machine in `~/.compasso/engine`, which `compasso-run` falls back to when Claude Code's plugin cache has no Compasso.

## 28. Open

- The runner has been tried against the fakes; a run of several days against a real GitLab and a real GitHub project is still owed.
- Codex agents' per-role tools are not set yet; that waits until Codex's agent options are verified.
- Codex model ids are pinned defaults and will age; revisit at each release.

## 29. Removed in 4.0.0

4.0.0 replaced the long-running sessions and their polls with the cron runner. Removed:

- **Commands:** `work`, `sprint`, `story`, `feature`, `review`, and the old `harden` command (hardening is now a stage).
- **Roles and agents:** the builder (the developer's session builds), the approver (the tech lead decides), the shipper, the mutator and the finops role.
- **Scripts:** the per-flow agent budget, the sprint's test guide and testers' results, mutation testing, flaky-test detection, the hardening report, the live checks, ship, comment, follow-ups, team, the merge-request report, the review gate, risk scoring and test hashes.
- **Tracker commands:** merge (replaced by `mr-merge`), followup and followups, set-milestone, mr-update, disarm, mr-of, mr-events, merge-commit, digest, labels, label, label-create, comment-delete and comment-edit.
- **Labels:** `needs::approval`, `needs::lead` and `compasso::auto-merged`.
- **The team's join block,** claims and messages between agents, and the `.working` marker. A developer joins by being added to `team.developers`.
- **The SessionStart resume hook,** and the budget guard.
- **Configuration**, dropped by `config.sh upgrade`: `limits.agent_runs`, `approvals.merge`, `harden`, `test_guide`, `sprint.parallel`, every `risk.*` key except `sensitive_paths`, `team.poll*`, `team.lead_*`, `team.agents`, and the models of the removed roles. `trust.mvp_approval` becomes `trust.verify_approval`, and `harden.images.a11y` becomes `prototype.image`.
