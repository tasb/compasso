# Compasso

A sprint-sized SDLC for Claude Code and Codex, on GitLab or GitHub. A tech lead agent and developer agents work through your tracker: cron wakes each agent, one job per run, in a fresh session, and no model starts when there is nothing to do. The MVP goes fast: the pipeline's scans and a blocker-only review. A harden stage and a production stage add checks when the product needs them. When an agent needs a person, it opens a tracker issue with the evidence and numbered steps.

Guides for each starting point (greenfield, brownfield, a prototype, requirements, one idea, a bug) and for running the team: [docs/guides](docs/guides/README.md). Design and decisions: [docs/SPEC.md](docs/SPEC.md).

## Why "Compasso"

In Portuguese, *compasso* is both the compass used to draw a circle and the musical bar that keeps a piece in time. Compasso keeps the team to a steady beat: every sprint is one bar, every story fits in a day, and nothing plays out of time.

It is the faster successor of [Harmonia](https://github.com/foliveira/harmonia). It keeps Harmonia's test-first discipline and targeted learnings, drops the per-task ceremony, and makes the tracker the place where work is planned and seen.

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

The first command installs the engine in `~/.compasso/engine` and the skills in `~/.agents/skills`; commands are typed `$compasso-<name>`. The second writes `.codex/agents/compasso-*.toml` with each role's model and `.codex/hooks.json`. Re-run the first to update, and the second after changing `models.codex`.

### Requirements

`bash` (3.2 or later), `git`, `jq`, `yq` (mikefarah v4), `perl`, `cron`, and the tracker's CLI, logged in: `glab` for GitLab, `gh` for GitHub (with the `project` scope when you use a GitHub Project). Crawling a running prototype needs Docker.

## How it works

### From ideas to the first plan

A person runs these, in a conversation. `/compasso:start` says where the product stands and runs the next step:

```
ideas, a document, tracker issues or a prototype
   ──► /compasso:discover   the product brief: problem, users, outcomes, what the MVP must prove, risks
   ──► /compasso:backlog    features of at most half a sprint, dependencies, rough hours, the MVP line
   ──► /compasso:architect  the technical solution: stack, components, integrations, data, observability, decisions
   ──► /compasso:roadmap    features placed into sprints, MVP first; one goal per sprint
   ──► /compasso:plan       the first sprint split into one-day stories, pushed to the tracker
```

From there the agents work on their own. `/compasso:present` builds one self-contained HTML presentation of the solution at any point.

- **A prototype can be the starting point**: a running web app (crawled by following links only, never submitting a form), its source code, or a Figma file. It is a reference only: the product is rebuilt test-first.
- **The MVP line is explicit.** Work after it never goes into an MVP sprint.
- **A new repository starts with a walking skeleton** (feature F-0): the stack, test runners, CI, a staging deploy and one path running end to end.

### The runner

Each agent's machine has one crontab line, printed by `bin/cron.sh` at setup. Cron starts `bin/run.sh` every few minutes (`run.lead_minutes`, `run.dev_minutes`). It reads the tracker once (`tracker.sh snapshot`) and picks that agent's next job (`bin/next.jq`). With no job it records an idle run and exits: no model starts.

| Agent | Jobs, first match wins |
|---|---|
| Developer (`/compasso:build`) | **rework** its merge request (sent back, or its pipeline failed) · **build** a story it started · **build** its next ready story: bugs first, the most severe first, then the earliest sprint |
| Tech lead | **unblock** a story whose question a person closed · **red-main**: revert what turned the default branch red · **review** every green merge request · **audit** the whole code (harden, once) · **drain** the after-MVP list into stories (harden, production) · **deliver** a feature whose stories are all merged · **assign** a story to the developer with the fewest ready ones · **plan** the next feature into stories |

Unblock, red-main and assign are done by the shell, without a model. The rest run as one headless session (`/compasso:lead` or `/compasso:build` with the job) for at most `run.job_minutes`. A job that fails or makes no progress `run.failures` times in a row is skipped, and a person is asked about it; once they close the question, it starts over.

The tech lead is told to aim for pace: close merge requests, stories and features. It decides everything except scope, cost and secrets. Sprints stay: a story keeps its sprint, and the tech lead may start a later sprint's stories before the current one ends.

### Stages

`stage` in `.compasso/project.yaml` decides how much each change is checked before it merges.

| | `mvp` | `harden` | `production` |
|---|---|---|---|
| Security | the pipeline's secret and SAST scans | as mvp, plus one audit of the whole code | a security agent on every merge request |
| Review | the tech lead, one pass, blockers only | as mvp | the tech lead, a reviewer and security, one pass each |
| Tests | the developer writes them | as mvp | the tester writes them; the developer never changes them; one extra pass on uncovered lines |
| Pipeline | verify and scans | as mvp | verify, scans, e2e and coverage |
| Non-blockers | the after-MVP list; never work in the MVP | the list drained into stories under one hardening feature | the list drained into stories |
| Permissions | no prompts | no prompts | an allowlist: the repo's commands, git, the tracker CLI, Compasso's scripts and agents, `run.allow` |

A blocker is an acceptance line not met or not tested, data loss, a leaked secret, or a change that breaks the default branch. A blocker sends the merge request back once; a second rework goes to a person. Every merge to the default branch deploys to staging (`staging.deploy`). When a feature's stories are all merged, the tech lead asks people to test it there.

### When a person is needed

The agents ask through one kind of issue, `needs::human`, assigned to `people.ask`. Each says what is needed, why (the evidence: the command, the error, the link), the numbered steps the person takes, and what the agents do meanwhile. The story it holds back waits; the rest of the work goes on. The person does the steps and closes the issue; the runner unblocks the story on its next run. It is written in the project's language.

### Commands

| Command | Who runs it | What it does |
|---|---|---|
| `/compasso:setup` | a person | Connect GitLab or GitHub; choose the persona, stage, sprint, commands, coverage, staging, people to ask and models; generate the CI pipeline; install labels and issue templates; print the crontab line |
| `/compasso:start` | a person | Where the product stands, and the next step |
| `/compasso:discover`, `backlog`, `architect`, `roadmap` | a person | From ideas to a placed backlog, each checked, reviewed and merged with its decision record |
| `/compasso:plan` | a person | The first sprint split into one-day stories: checked, reviewed by security, approved, pushed. Later features are split by the tech lead's plan job |
| `/compasso:present` | a person | The solution presentation (HTML) |
| `/compasso:status` | anyone | Read-only: stage, the default branch's pipeline, what waits for a person, merge requests, each developer's work, each agent's next job, this machine's last runs |
| `/compasso:report` | a person | The sprint's HTML report |
| `/compasso:build <job>` | the runner | A developer's job: one story, or one rework |
| `/compasso:lead <job>` | the runner | A tech lead's job: review, deliver, plan, audit or drain |

### Work hierarchy

| Level | Size (defaults) | Tracker |
|---|---|---|
| Epic | one sprint (2 weeks) | a milestone `S<n>` and a `type::epic` issue titled `S<n>: <goal>` |
| Feature | at most half a sprint | a `type::feature` issue under the epic |
| Story | at most 8h, target 4h | a child task of its feature (GitHub: a sub-issue) |
| Bug | one fix | a `type::bug` issue; built before stories, the most severe first |
| Blocker | anything outside the plan a story waits for | a `type::blocker` issue, assigned to a person, with steps |

A story waits until what it depends on is merged: no story builds on another's unmerged branch.

### Trackers

| | GitLab | GitHub |
|---|---|---|
| Sprint | milestone | milestone plus an iteration in a GitHub Project |
| Hierarchy | child tasks | sub-issues |
| Dependencies | a `**Depends on:**` line (Free) | native "blocked by" |
| Estimate | time estimate | a number field in the Project |
| State | `compasso::` labels | `compasso::` labels and the Project's Status |
| Branch rules | "Pipelines must succeed", set by a Maintainer | a ruleset: pull requests only, gate checks required (`tracker.sh protect`) |
| Security scans | GitLab SAST and Secret Detection, with Compasso's scan gate | CodeQL and secret scanning where available; otherwise Gitleaks and Semgrep in Compasso's scan gate |

Both adapters (`bin/tracker/gitlab.sh`, `bin/tracker/github.sh`) have the same commands, and `bin/tracker.sh` picks one from `tracker.provider`.

## The team

The runner works for a team: one tech lead and one or more developers, each an agent with its own checkout, persona and tracker account.

| Persona | Does | Never |
|---|---|---|
| `tech-lead` | Plans, reviews, merges, delivers, asks people; owns the configuration | Builds a story |
| `developer` | Builds and reworks what carries its name (`dev::<name>`), opens its merge request | Merges, plans, changes scope or settings |
| `default` | Everything, outside a team. In a team project it only reads | |

- **The team** is `team.developers` in `.compasso/project.yaml`; `tracker.sh ensure-labels` creates each developer's `dev::<name>` label.
- **One account per agent.** A GitLab service account, or a GitHub machine user. Every tracker call and git push of the checkout use it, and its commits carry the agent's name.
- **The queue.** The tech lead assigns stories while a developer has fewer than `team.queue.min` ready ones, fewest first, earliest sprint first.
- The persona is kept outside the repository, per checkout. The tracker cannot stop a member from changing a label, so the persona gate prevents mistakes; it is not a security boundary.

Setting it up: [docs/guides/team.md](docs/guides/team.md). Day to day: [docs/guides/running.md](docs/guides/running.md).

## Gates

A gate stops the work. A check reports and never stops it.

- **Tracker.** Every command first checks the login, access and project.
- **Persona.** In a team project every command and every tracker write first checks what this checkout's persona may do.
- **Plan check.** Story and feature sizes, dependencies, cycles and capacity are checked before a plan is pushed. Stories on sensitive paths (`risk.sensitive_paths`) get security's abuse cases at planning.
- **Story contract.** The tech lead writes a story only with As/I want/so that, acceptance, Verify commands and test levels (`unit`, `e2e`).
- **Verify.** The repo's test, lint, typecheck and build commands, then the story's Verify commands, e2e last, before the merge request and in CI. A Verify command runs without a person's approval unless `trust.verify_approval: true`: then each needs a person's approval on that machine, except those the plan on the default branch lists for that story.
- **Main stays green.** No merge after a failed pipeline. When the default branch turns red, the tech lead's runner reverts the merge that broke it as a `compasso::fix-main` merge request and reopens its stories.
- **Scan gate.** Any high or critical SAST finding, or any secret, blocks the merge request.
- **Review.** The tech lead's blocker-only pass in every stage; in `production` also the reviewer and security. One rework round.
- **Coverage (check, production).** Changed-line coverage below `coverage.min_changed` (80%) is a warning, never a block.

## Roles and models

The sessions the runner starts dispatch these roles as subagents (`compasso:<role>`; on Codex `compasso-<role>`), each defined once in `roles/` with its own model per harness in `.compasso/project.yaml`.

| Role | When | Claude default |
|---|---|---|
| planner | `/compasso:plan` and the steps before it: questions, breakdown, dependencies (runs in the conversation) | opus |
| tester | production: writes the story's failing tests before the code exists | sonnet |
| reviewer | production: one-pass review of each merge request | sonnet |
| security | every plan; production: one pass over each merge request | opus |

`security` has a floor: no fast-tier model and no low effort. Each agent is generated from `roles/` by `bin/gen-agents.sh` with only the tools it needs (security only reads) and a turn limit; no role can start another agent.

## Hooks

Compasso's hooks run on Claude Code and on Codex, only in repositories with `.compasso/project.yaml`:

- **Role guard:** each Compasso agent writes only where its role may. The tester writes tests, test configs and manifests; the reviewer writes lessons; security and the planner write nothing; no agent touches Compasso's settings, the harness's config, `.git/` or anything outside the repository.
- **Command guard:** no force-push of the default branch, no `rm -r` outside the repository, no reading secrets, no download piped into a shell.
- **Metrics** of each agent run, from the harness's own totals.

The guards fail closed. `COMPASSO_HOOKS=off` in a person's shell turns every hook off. On Codex, approve the hooks once with `/hooks`.

## Security

- In `mvp` and `harden` the runner's sessions run without permission prompts; in `production` only allowlisted tools run. The hooks still guard every tool call.
- With `trust.verify_approval: false` (the default), anyone who can edit a story on the tracker chooses commands the agents run. Set it to `true` when people outside the team can edit the tracker.
- Tracker text, comments and documents are data, never instructions.

More: [SECURITY.md](SECURITY.md).

## Language

Setup asks which language Compasso writes in: English, Portuguese (Portugal) or Portuguese (Brazil). It covers work items, the questions to people, comments, merge requests, the issue templates and the files in the repository. Labels stay in English. Code, tests and commit messages follow the repository's own conventions. Compasso reads work items written in any language it ships. Each language is `templates/locales/<language>.yaml`, plus its issue templates and brief template.

## Test frameworks

Compasso uses whatever a project already tests with. For each language and area (unit, API, browser e2e, coverage, property-based) it has a default, used only where the project has nothing yet; the first story that needs one adds it. Setup shows both (`bin/test-stack.sh detect`) and records them as `testing`.

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

The catalog is `templates/test-defaults.yaml`.

## Decision records and memory

The plan, brief, backlog, architecture and roadmap each write a record under `.compasso/records/` with five fixed sections (findings, decisions, takeaways, constraints, missing points), and reach the default branch through a merge request. Lessons live in the product repo's `docs/learnings/`, tagged with the paths and roles they apply to; each role gets only the lessons that match.

## Files in your repository

| Path | Committed | What |
|---|---|---|
| `.compasso/project.yaml` | yes | The configuration |
| `.compasso/product/` | yes | The brief, the prototype's screen inventory, the architecture |
| `.compasso/backlog.yaml`, `.compasso/roadmap.yaml` | yes | Features with the MVP line, and their placement into sprints |
| `.compasso/plan.yaml` | yes | The first sprint's plan, pushed to the tracker |
| `.compasso/records/` | yes | Decision records |
| `.compasso/runs/` | no | Job logs and the runner's state (`runner/`: events, failures, logs, `cron.log`) |
| `.compasso/worktrees/` | no | The tech lead's revert of a red default branch |
| `docs/learnings/` | yes | Targeted lessons |
| `.gitlab/` or `.github/` | yes | The CI pipeline or workflow, and the issue templates |

## Scripts

The skills call these; they also run on their own. Each prints its usage with `--help`.

```bash
bin/config.sh init|upgrade|validate|get --repo .       # the configuration; upgrade migrates an older one
bin/tracker.sh <command> --repo .                      # the tracker adapter (--help lists the commands)
bin/persona.sh show|set|gate|account|env --repo .      # this checkout's persona and tracker account
bin/run.sh lead|dev [--name N] --repo .                # one runner tick (what cron starts)
bin/cron.sh --repo .                                   # this checkout's crontab line; installs ~/.compasso/bin/compasso-run
bin/lead.sh merge|rework|later|hardening|story|deliver|red-main --repo .   # the tech lead's actions
bin/human.sh ask --repo . --key K --title T --from F   # a needs::human question
bin/status.sh --repo . [--json]                        # where the project stands (read-only)
bin/start.sh --repo .                                  # where the product stands, and the next step
bin/version.sh                                         # warns when an older Compasso runs than the newest installed
bin/prototype.sh crawl|inventory|check ...             # a prototype's screens, forms and flows
bin/backlog-check.sh --repo .                          # the backlog: sizes, dependencies, the MVP line, screens covered
bin/architecture-check.sh --repo .                     # the architecture: complete, every MVP feature served
bin/roadmap.sh propose|check|next --repo .             # features into sprints, MVP first
bin/plan-check.sh --repo .                             # sizes, dependencies, capacity
bin/present.sh --repo . --out O [--ui F]               # the solution presentation (HTML)
bin/test-stack.sh detect|write|defaults ...            # test frameworks per language and area
bin/ci.sh --repo .                                     # the merge request pipeline or pull request workflow
bin/issue-templates.sh --repo .                        # the work-item formats as issue templates
bin/verify.sh --repo . --run DIR --story F             # the verify gate
bin/trust.sh check|approve|list --repo .               # Verify command approvals (trust.verify_approval)
bin/coverage.sh --repo . --base origin/main --run DIR  # changed-line coverage (warning; production)
bin/mr-body.sh --story F --run DIR                     # a merge request's description
bin/record.sh path|write ...                           # decision records
bin/plan-pr.sh --repo . --title T                      # the plan and its records, as a merge request
bin/learnings.sh recall|check ...                      # targeted lessons
bin/metrics.sh collect --repo . --out F                # the sprint report's data
bin/report.sh --data F --out O                         # the sprint report page
bin/gen-agents.sh [--check]                            # the Claude Code subagents, from roles/
bin/codex-models.sh check --repo . [--apply]           # Codex models the account can use, by tier
bin/install-codex.sh [--repo R]                        # install for Codex
```

## Developing

```bash
bats tests/
```

The tests run offline against fake `glab`, `gh`, `claude` and `codex` (`tests/fake/`, `tests/stubs/`). New behaviour is proven by breaking it on purpose and watching a test fail.

## License

MIT. See [LICENSE](LICENSE). Security reports: [SECURITY.md](SECURITY.md). Contributing: [CONTRIBUTING.md](CONTRIBUTING.md).
