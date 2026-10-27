# Compasso

A sprint-sized SDLC for Claude Code and Codex. It plans one epic per sprint, features of at most half a sprint and user stories of at most one day in your tracker (GitLab or GitHub). It builds each story test-first, reviews every merge request with a mandatory security review, and hands business testers an HTML test guide at sprint end. The goal is a fast MVP that stays safe, with an optional hardening phase afterwards.

Humans approve plans and merges by default. Security review is never skipped, in any mode.

Guides for each starting point (greenfield, brownfield, a prototype, requirements, one idea, a bug): [docs/guides](docs/guides/README.md). Design and decisions: [docs/SPEC.md](docs/SPEC.md).

## Why "Compasso"

In Portuguese, *compasso* is both the compass used to draw a circle and the musical bar that keeps a piece in time. Compasso keeps the team to a steady beat: every sprint is one bar, every story fits in a day, and nothing plays out of time.

It is the faster successor of [Harmonia](https://github.com/foliveira/harmonia). It keeps Harmonia's test-first discipline, test immutability, targeted learnings and security review. It drops the per-task ceremony, and the tracker becomes the place where work is planned and seen.

## Install

### Claude Code

```bash
claude plugin marketplace add tasb/compasso
claude plugin install compasso@compasso
```

Commands are typed `/compasso:<name>`.

### Codex

```bash
git clone https://github.com/tasb/compasso && cd compasso
bin/install-codex.sh                                               # once per machine
~/.compasso/engine/bin/install-codex.sh --repo /path/to/project    # once per project
```

The first command installs the engine in `~/.compasso/engine` and the skills in `~/.agents/skills`; commands are typed `$compasso-<name>`. The second writes `.codex/agents/compasso-*.toml` with each role's model. Re-run the first to update, and the second after changing `models.codex`.

### Requirements

`bash` (3.2 or later), `git`, `jq`, `yq` (mikefarah v4), and the tracker's CLI, logged in: `glab` for GitLab, `gh` for GitHub (with the `project` scope when you use a GitHub Project). Hardening's live checks need Docker and `xmllint`.

## Using it

### From ideas to sprints

You don't need a sprint goal to begin. `/compasso:start` says where the product stands and runs the next step:

```
ideas, a document, tracker issues or a prototype
   ──► /compasso:discover   the product brief: problem, users, outcomes, what the MVP must prove, risks
   ──► /compasso:backlog    features of at most half a sprint, dependencies, rough hours, the MVP line
   ──► /compasso:architect  the technical solution: stack, components, integrations, data, observability, decisions
   ──► /compasso:roadmap    features placed into sprints, MVP first; one goal per sprint
   ──► /compasso:plan       the next sprint split into one-day stories
   ──► /compasso:sprint     built, reviewed, merged; at its close the roadmap is refined with real velocity
```

At any point, `/compasso:present` builds one self-contained HTML presentation of the solution from these files: the problem, the functional and technical solution, the decisions, the sprints and the next sprint's user stories.

- **A prototype can be the starting point**: a running web app (crawled by following links only, never submitting a form), its source code, or a Figma file. It becomes an inventory of screens, forms and flows; every screen must belong to a feature or be left out on purpose. The prototype is a reference only: the product is rebuilt test-first. Public prototypes only for now.
- **Only the next sprint gets stories.** Later sprints stay as features and are re-placed at each sprint close.
- **The MVP line is explicit.** Work after it never goes into an MVP sprint, and `/compasso:harden` is offered once the MVP sprint closes.
- **A new repository starts with a walking skeleton** (feature F-0): the stack, test runners, CI and one path running end to end. Setup runs again once it exists.
- The brief, backlog and roadmap are files in `.compasso/`, each reaching the default branch through a merge request with its decision record. Backlog features are also tracker issues in no sprint.

### Running it

Run `/compasso:setup` once in the product repository. It connects the tracker, asks for the sprint length, capacity, commands, approvals and models, and writes `.compasso/project.yaml`. Every other command refuses to run until the tracker check passes.

| Command | What runs |
|---|---|
| `/compasso:setup` | Connect GitLab or GitHub; record sprint, limits, commands, coverage, approvals, risk and models; generate the CI pipeline or workflow; install labels and issue templates |
| `/compasso:start` | Where the product stands (setup, discover, backlog, roadmap, plan, build) and the next step |
| `/compasso:discover` | Ideas, documents, issues or a prototype into a product brief, with security's view of the data and access involved |
| `/compasso:backlog` | The brief into features with rough hours, dependencies and the MVP line; checked, reviewed, pushed to the tracker in no sprint |
| `/compasso:architect` | The technical solution: stack, components (each serving backlog features), integrations, data, observability (from an observability prototype when there is one), environments, decisions with their alternatives; checked, reviewed by security, approved |
| `/compasso:present` | One self-contained HTML presentation of the functional and technical solution, the decisions, the sprints and the next sprint's stories, regenerated whenever the plan changes |
| `/compasso:roadmap` | The backlog into sprints by dependency and capacity, MVP first, one goal each; refined at every sprint close |
| `/compasso:plan` | The planner turns a sprint goal into an epic, features and one-day stories with dependencies and blockers. `plan-check` validates sizes, dependencies and capacity; security reviews the plan; after your approval it is pushed to the tracker |
| `/compasso:feature <iid\|"idea">` | The feature flow: up to 3 rounds of questions in the conversation, a breakdown into stories, approval, then the Q&A and plan recorded on the tracker |
| `/compasso:story <iid>` | The story flow: failing tests first, the smallest change that passes, the verify gate, review and security review with an automatic fix loop, then the merge request |
| `/compasso:sprint [feature]` | Builds everything that can be built now, in dependency order and in parallel where paths do not overlap. Verifies each finished feature with e2e. At sprint end, writes the test guide |
| `/compasso:review <mr>` | Review and the mandatory security review on any merge request (a pull request on GitHub), findings posted, fixes on request |
| `/compasso:status [iid]` | A read-only readout. For the sprint: what can be built now, what waits and on whom, features, the plan on the default branch and local runs. For a story: its state, what it waits on, how far its run got and the step to resume from. Changes nothing |
| `/compasso:report` | The sprint's HTML report: delivery, flow and waiting, quality, agent effort and cost |
| `/compasso:work` | Team projects only: one tick of the poll. A developer builds the next story assigned to it; the tech lead sees questions, work with no developer and each developer's load. Skipped while the agent works |
| `/compasso:harden <iid>` | Optional, after the MVP: mutation, property-based, flaky and test-smell checks; with `--set live`, API fuzzing, a ZAP scan, performance and accessibility checks. Gaps become stories for a later sprint |

### Work hierarchy

| Level | Size (defaults) | Tracker |
|---|---|---|
| Epic | one sprint (2 weeks) | a milestone `S<n>` and a `type::epic` issue titled `S<n>: <goal>` |
| Feature | at most half a sprint | a `type::feature` issue under the epic |
| Story | at most 8h, target 4h | a child task of its feature, with an estimate |
| Blocker | anything outside the plan a story waits for | a `type::blocker` issue, urgent, always assigned to a person, with step-by-step instructions |

Dependencies are part of the plan. Stories are created in dependency order. A story waits until what it depends on is merged: no story builds on another's unmerged branch. Sprint sync shows what can run now, what waits, and on whom.

### Trackers

| | GitLab | GitHub |
|---|---|---|
| Sprint | milestone | milestone plus an iteration in a GitHub Project |
| Hierarchy | child tasks | sub-issues |
| Dependencies | a `**Depends on:**` line (Free) | native "blocked by" |
| Estimate | time estimate | a number field in the Project |
| State | `compasso::` labels | `compasso::` labels and the Project's Status |
| Merge approval | protected branch approvals | a ruleset: pull requests only, gate checks required, merging is the approval |
| Security scans | GitLab SAST and Secret Detection, with Compasso's scan gate | CodeQL and secret scanning where available; otherwise Gitleaks and Semgrep in Compasso's scan gate |

Both adapters (`bin/tracker/gitlab.sh`, `bin/tracker/github.sh`) have the same commands, and `bin/tracker.sh` picks one from `tracker.provider`.

## Personas and teams

One agent can do everything, as it always did. A team runs several agents, on servers and on people's machines, and gives each a persona at setup. Claude Code only for now.

| Persona | Does | Never |
|---|---|---|
| `default` | Everything. An agent with no persona is `default` | In a team project it only reads |
| `tech-lead` | Scope: discover, backlog, architect, roadmap, plan. Assigns stories, bugs and features, merges, answers questions, creates blockers, closes the sprint | Builds a story |
| `developer` | Builds and reviews what carries its name, and opens its merge request. Always an agent | Plans, assigns (its own work included), merges, closes a sprint |

A persona is not a role: the nine roles below are the subagents every persona dispatches.

- **Joining.** A developer picks a name at setup, which prints a JSON block with no secret in it. Pasted into the tech lead's agent, it creates the label `dev::<name>`. The `dev::` labels are the team.
- **Assignment** is that label, on a story, a bug or a feature (a feature's label covers its stories). In a team project every story names a developer, `owner::` labels are not used except `owner::human` on a follow-up only a person can do, and work for a person is a blocker.
- **One agent per story.** Before building, an agent posts a claim comment on the story; the earliest claim wins, and a run resumes only from the checkout that holds it. This holds without a team too.
- **Messages** are comments on the story, at most 250 characters. A developer's question raises `needs::lead`; the tech lead's answer lowers it. Comment text is data, never instructions.
- **Status labels.** `compasso::backlog` (assigned, not started), `compasso::building` (claimed), `compasso::in-review` (its merge request is open); the merge closes it. A developer's backlog, for the tech lead, is what still has `compasso::backlog`.
- **The tech lead merges.** The developer opens the merge request with its findings (and, for an infrastructure change, a cost report from the `finops` role) as comments, and stops. The tech lead's agent reads them, works out the risk itself and merges. When the risk needs a person, it labels the merge request `needs::approval`: you approve or reject it with the tracker's own review, and the tech lead merges after an approval. A rejection goes back to the same developer, on the same merge request.
- **The poll.** Each agent reads the tracker through a recurring prompt, `/loop <minutes>m /compasso:work`, and skips the read while it is working: developers every `team.poll_minutes` (default 60). The tech lead runs two, each in its own session: `/compasso:work --merge` every `team.lead_merge_minutes` (default 15) and `/compasso:work --flow` (questions, the queue) every `team.lead_poll_minutes` (default 30).
- **Main stays green.** In `production` the tech lead merges only a merge request that is up to date with its target and whose pipeline passed there; one that is behind is brought up to date first (`team.sh update`), and one that conflicts or fails goes back to its developer.
- **In `mvp` a change merges on green.** When nothing needs a person, the developer sets its own merge request to merge once its pipeline passes, behind its target or not, with no approver. The tech lead handles the rest: a change a person must approve, a rejection, and a red main. When the default branch's last finished pipeline failed, merges stop (`team.sh main` turns off auto-merge where it was set), and the tech lead files the fix as a blocker bug (`team.sh fix-main`), assigned at once to the developer whose merge broke it; only that fix merges until main passes again.
- **Unbuildable stories never reach a developer.** A story or bug with no acceptance or no Verify, or whose `dev::` label names no one in the team, is not ready: nobody builds it or is assigned it until the story is fixed. A story whose paths overlap a merge request still open waits until it merges.
- **The queue counts what can be built.** A developer's backlog counts toward `team.queue` only for stories with nothing open ahead of them, and the tech lead assigns first the stories that can start and hold up the most others.
- **Stage.** In `stage: mvp` the tech lead also keeps each developer's backlog between `team.queue.min` (5) and `team.queue.target` (15) on its own, within the sprint, and answers questions on its own unless the answer changes scope, security or cost (its readout lists every answer, so a person can overturn one); in `production` it proposes assignments and answers and a person decides. A developer keeps building: after a batch it takes the next one in the same tick.
- **One account per agent.** Each agent uses its own tracker account (a GitLab service account; on GitHub, a machine user): every tracker call and git push of its checkout use that account's token, and its commits carry the agent's name and email. A person's approval counts only from an account not listed in `team.agents`.
- **Bugs** found in merged work are filed with no developer and wait for the tech lead.

The persona is kept outside the repository, per checkout. The tracker cannot stop a member from changing a label, so the persona gate prevents mistakes; it is not a security boundary. How to set one up: [docs/guides/team.md](docs/guides/team.md). Design: [docs/SPEC.md](docs/SPEC.md), sections 31 and 32.

## Language

Setup asks which language Compasso writes in: English, Portuguese (Portugal) or Portuguese (Brazil). It covers what people read:
- work items on the tracker: headings and key lines, and the text the agents write;
- the issue templates;
- comments and merge requests;
- the files in the repository: brief, decision records, test guide, sprint report and presentation.

Labels stay in English: scripts and tracker filters use them. Code, tests and commit messages follow the repository's own conventions. Compasso reads work items written in any language it ships, so an item written by hand in English still works in a Portuguese project, and changing the language later breaks nothing.

Each language is one file of texts, `templates/locales/<language>.yaml`, plus its issue templates and brief template.

## Test frameworks

Compasso uses whatever a project already tests with. For each language and area (unit, API, browser e2e, coverage, property-based) it has a default, used only where the project has nothing yet. The first story that needs one adds it. Setup shows both (`bin/test-stack.sh detect`) and records them as `testing` in `.compasso/project.yaml`.

| Language | Unit | API | Browser e2e | Coverage | Property-based |
|---|---|---|---|---|---|
| JavaScript / TypeScript | Vitest | Vitest + fetch | Playwright | Vitest (LCOV) | fast-check |
| Python | pytest | pytest + httpx | Playwright (pytest) | pytest-cov (Cobertura) | Hypothesis |
| Go | go test | httptest | Playwright (TypeScript, `e2e/`) | coverprofile → Cobertura | rapid |
| Java / Kotlin | JUnit 5 | REST Assured | Playwright (Java) | JaCoCo | jqwik |
| C# / .NET | xUnit | WebApplicationFactory | Playwright (.NET) | coverlet (Cobertura) | FsCheck |
| Ruby | RSpec | rack-test | Playwright (TypeScript, `e2e/`) | SimpleCov (Cobertura) | prop_check |
| PHP | PHPUnit | the framework's test client | Playwright (TypeScript, `e2e/`) | PHPUnit (Cobertura) | table-driven tests |
| Rust | cargo test | reqwest in `tests/` | Playwright (TypeScript, `e2e/`) | cargo-llvm-cov (LCOV) | proptest |
| Bash | bats-core | bats + curl | none | kcov | none |

The catalog, with the signs used to recognise each framework, is `templates/test-defaults.yaml`.

## The gates

A gate stops the flow. A check reports and never stops it.

- **Tracker.** Every command first checks the login, access and project.
- **Persona.** In a team project every command and every tracker write first checks what this checkout's persona may do. A story is built only by the developer it is assigned to, and only by the checkout that claimed it.
- **Plan check.** Story and feature sizes, dependencies, cycles and capacity are checked before anything is pushed. Stories that touch sensitive paths need a security review at planning.
- **Story contract.** A story needs Acceptance and Verify before it is built. A story that cannot be tested goes back to the planner.
- **Verify commands approved.** A story's Verify commands are tracker text, so they run only after a person approved each exact command on this machine, or when the plan on the default branch lists that command for that story. Plans ask once for all their stories; a command edited later asks again. In `stage: mvp` none is asked, unless `trust.mvp_approval` is true.
- **Test immutability.** Test files are hashed after the tester writes them, and the builder may never change them.
- **Verify.** Tests, lint, typecheck, build, the story's own Verify commands and e2e run before review, before the merge request and in CI; a Verify command the same as one of the repo's runs once. In `stage: mvp` each merge request's pipeline runs verify and the security scans only: e2e and coverage come back in `production`.
- **Findings.** Every finding is fixed in its story, minors too, except a minor whose fix needs someone else (filed for that person). In `stage: mvp` only blocker and major findings must be fixed: a story's open minors are filed together as one issue for after the MVP (`compasso::after-mvp`, in no sprint), each with an acceptance line its reviewer wrote. Anything that can leak or destroy data, widen access, fail open or break production is at least major.
- **Security review.** Runs on every plan, every merge request and at sprint end, and is never skipped. Only security can close a security finding, and no approval mode merges with one open.
- **Scan gate.** Any high or critical SAST finding, or any secret, blocks the merge request.
- **Merge approval.** A person merges by default. `approvals.merge: agent` lets an agent merge once review is clear. `risk` lets low-risk changes merge on their own, and a daily digest lists what merged. What needs a person depends on `stage`: in `mvp` only an infrastructure change whose cost report says `increase` or `unknown` (a change to sensitive paths asks no one, but its merge request names it as a warning); in `production` also sensitive paths, infrastructure, migrations and API contracts, the build or dependencies, more than `risk.max_changed_lines` lines of product code (`risk.product_paths`), low coverage, or a change security marks sensitive. In a team project the tech lead merges instead (see Personas and teams).
- **Coverage (check).** Changed-line coverage below 80% is a warning, never a block. An epic, feature or story can set its own threshold.

## Roles and models

Eight roles, each defined once in `roles/`, each with its own model per harness in `.compasso/project.yaml`.

| Role | What it does | Claude default |
|---|---|---|
| planner | Q&A, breakdown into one-day stories, dependencies | opus |
| tester | Writes the failing tests first: unit always, e2e when the story asks | sonnet |
| builder | Makes the tests pass with the smallest change and fixes findings. Never edits a test | sonnet |
| reviewer | One-pass review: correctness, regressions, simplicity, tests, docs | sonnet |
| security | Mandatory security review of plans, merge requests and sprints | opus |
| approver | Agent approval: when `approvals.merge: agent`, and for a team's tech lead before it merges | opus |
| shipper | The sprint's test guide for business testers | haiku |
| mutator | Writes deliberate bugs to check the tests catch them (hardening only) | sonnet |
| finops | Reports the monthly cost of a change to infrastructure, on its merge request | sonnet |

`security` and `approver` have a floor: no fast-tier model and no low effort.

Each role is a registered subagent (`compasso:<role>`), generated from `roles/` by `bin/gen-agents.sh`, with only the tools it needs: security and the approver can only read, and no role can start another agent. Every run is bounded: each agent has a turn limit, and `bin/budget.sh` caps how many times each role runs in one story or plan (`limits.agent_runs`; in `stage: mvp` only their total, `mvp_total`). A merge request sent back for rework starts a new budget. When the budget runs out, the flow stops and hands back to a person.

## Hooks

Compasso's hooks enforce in the harness what used to rest on instructions, on Claude Code and on Codex, and only in repositories with `.compasso/project.yaml`:

- **Role guard:** each agent writes only where its role may. The builder never touches tests, security and the approver write nothing, and no agent touches Compasso's settings, the budget, the harness's config or anything outside the repository.
- **Budget guard:** every dispatch and continuation of an agent is claimed against the run's budget, and denied when it is spent.
- **Command guard:** no force-push of the default branch, no `rm -r` outside the repository, no reading secrets, no download piped into a shell.
- **Metrics** are recorded from the harness's own totals, and after a compaction the flow is told where each local run stopped.

The guards fail closed. `COMPASSO_HOOKS=off` in a person's shell turns every hook off. On Codex, approve the hooks once with `/hooks`.

## Decision records

The tracker holds the work; the repository holds why. Every plan, feature and story writes a record under `.compasso/records/S<n>/` with five fixed sections: findings, decisions, takeaways, constraints and missing points. An empty section says "None". Records are rendered by `bin/record.sh` from the run's data, and reach the default branch through a merge request: a story's record rides in the story's own, a plan's in a plan merge request.

## Memory

Lessons live in the product repo's `docs/learnings/`, one file each, tagged with the paths and roles they apply to. When a story runs, each role gets only the lessons that match the story's paths and that role, so the prompts stay small.

## Reporting

- **Metrics.** Each story run records its agents' tokens and time, review rounds, verify failures and re-plans in `.compasso/metrics/<iid>.json`, committed with the story.
- **Sprint report.** `/compasso:report` builds a self-contained HTML page from the tracker and those files. It runs on demand and at sprint close.
- **Test guide.** At sprint end testers get an HTML guide written for business testers: features and how to try them, with no work items or merge requests. Their results come back as bugs.

## Files in your repository

| Path | Committed | What |
|---|---|---|
| `.compasso/project.yaml` | yes | The configuration |
| `.compasso/product/` | yes | The product brief, the prototype's screen inventory, and the architecture |
| `.compasso/backlog.yaml`, `.compasso/roadmap.yaml` | yes | Features with the MVP line, and their placement into sprints |
| `.compasso/plan.yaml` | yes | The sprint plan: the source for everything pushed to the tracker. It reaches the default branch through a plan merge request |
| `.compasso/records/S<n>/` | yes | A decision record per plan, feature and story: findings, decisions, takeaways, constraints and missing points |
| `.compasso/metrics/` | yes | One metrics file per story |
| `.compasso/runs/` | no | Run logs, findings and intermediate files |
| `docs/learnings/` | yes | Targeted lessons |
| `.gitlab/` or `.github/` | yes | The CI pipeline or workflow, and the issue templates |

## Scripts

The skills call these; they also run on their own.

```bash
bin/config.sh init|upgrade|validate|get --repo .       # the configuration
bin/tracker.sh check|ensure-labels|push-backlog|push-plan|story|set-state|open-mr|followup|merge|mr-info|comment \
               |sprint-sync|sprint-items|sprint-done|merge-commit|digest|mr-checks|main-pipeline|followups|close --repo .
bin/tracker.sh protect --repo .                        # GitHub: the ruleset, CodeQL and auto-merge
bin/persona.sh show|set|join|gate --repo .             # this checkout's persona: default, tech-lead or developer
bin/team.sh add|list|assign|claim|release|msg|messages|inbox|working --repo .   # a team: names, assignment, claims, messages, the poll
bin/team.sh review|ask|update|merge|return --iid N --repo .                 # the tech lead merges (in mvp, merge also the developer)
bin/team.sh main|fix-main --repo .                                          # the tech lead: a red main, and its fix
bin/followups.sh --repo . [--milestone S<n>] [--apply]                     # upgrading: follow-ups in no sprint join the sprint
bin/followups.sh legacy --repo . [--close]                                  # upgrading: follow-ups no test could check, closed
bin/start.sh --repo .                                  # where the product stands, and the next step
bin/version.sh                                         # warns when an older Compasso runs than the newest installed
bin/prototype.sh crawl|inventory|check ...             # a prototype's screens, forms and flows
bin/backlog-check.sh --repo .                          # the backlog: sizes, dependencies, the MVP line, screens covered
bin/architecture-check.sh --repo .                     # the architecture: complete, every MVP feature served
bin/roadmap.sh propose|check|next --repo .             # features into sprints, MVP first
bin/present.sh --repo . --out O [--ui F]               # the solution presentation (HTML)
bin/test-stack.sh detect|write|defaults ...            # test frameworks per language and area, with defaults
bin/plan-check.sh --repo .                             # sizes, dependencies, capacity
bin/status.sh --repo . [--iid N] [--json]              # where the sprint or a story stands (read-only)
bin/ci.sh --repo .                                     # the merge request pipeline or pull request workflow
bin/issue-templates.sh --repo .                        # the work-item formats as issue templates
bin/verify.sh --repo . --run DIR --story F             # the verify gate
bin/trust.sh check|approve --repo . --story F|--plan   # approve the Verify commands a story runs
bin/coverage.sh --repo . --base origin/main --run DIR  # changed-line coverage (warning)
bin/test-hashes.sh record|verify --repo . --run DIR    # test immutability
bin/review-gate.sh --findings F [--for merge]          # do review findings still block?
bin/risk.sh --repo . --run DIR --base REF              # low or high risk
bin/ship.sh --repo . --run DIR                         # finish a story: follow-ups for a person, minors for after the MVP, metrics, record, commit
bin/record.sh path|write|story ...                     # decision records
bin/plan-pr.sh --repo . --title T                      # the plan and its records, as a merge request
bin/learnings.sh recall --role R --story F             # the lessons one role needs for one story
bin/metrics.sh collect --repo . --out F                # the sprint report's data
bin/report.sh --data F --out O                         # the sprint report page
bin/test-guide.sh --data F --out O                     # the test guide
bin/mutate.sh, flaky.sh, live.sh, harden-report.sh     # hardening
bin/gen-agents.sh [--check]                            # the Claude Code subagents, from roles/
bin/budget.sh claim|show|rework|reset --run DIR        # the agent-run budget of one flow run
bin/codex-models.sh check --repo . [--apply]           # Codex models the account can use, by tier
bin/install-codex.sh [--repo R]                        # install for Codex
```

## Developing

```bash
bats tests/
```

The tests run offline against fake `glab` and `gh` (`tests/fake/`). New behaviour is proven by breaking it on purpose and watching a test fail.

## License

MIT. See [LICENSE](LICENSE). Security reports: [SECURITY.md](SECURITY.md). Contributing: [CONTRIBUTING.md](CONTRIBUTING.md).
