# Compasso

A sprint-sized SDLC for Claude Code and Codex. It plans one epic per sprint, features of at most half a sprint and user stories of at most one day in your tracker (GitLab or GitHub). It builds each story test-first, reviews every merge request with a mandatory security review, and hands business testers an HTML test guide at sprint end. The goal is a fast MVP that stays safe, with an optional hardening phase afterwards.

Humans approve plans and merges by default. Security review is never skipped, in any mode.

Design and decisions: [docs/SPEC.md](docs/SPEC.md).

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

Run `/compasso:setup` once in the product repository. It connects the tracker, asks for the sprint length, capacity, commands, approvals and models, and writes `.compasso/project.yaml`. Every other command refuses to run until the tracker check passes.

| Command | What runs |
|---|---|
| `/compasso:setup` | Connect GitLab or GitHub; record sprint, limits, commands, coverage, approvals, risk and models; generate the CI pipeline or workflow; install labels and issue templates |
| `/compasso:plan` | The planner turns a sprint goal into an epic, features and one-day stories with dependencies and blockers. `plan-check` validates sizes, dependencies and capacity; security reviews the plan; after your approval it is pushed to the tracker |
| `/compasso:feature <iid\|"idea">` | The feature flow: up to 3 rounds of questions in the conversation, a breakdown into stories, approval, then the Q&A and plan recorded on the tracker |
| `/compasso:story <iid>` | The story flow: failing tests first, the smallest change that passes, the verify gate, review and security review with an automatic fix loop, then the merge request |
| `/compasso:sprint [feature]` | Builds everything that can be built now, in dependency order and in parallel where paths do not overlap. Verifies each finished feature with e2e. At sprint end, writes the test guide |
| `/compasso:review <mr>` | Review and the mandatory security review on any merge request (a pull request on GitHub), findings posted, fixes on request |
| `/compasso:report` | The sprint's HTML report: delivery, flow and waiting, quality, agent effort and cost |
| `/compasso:harden <iid>` | Optional, after the MVP: mutation, property-based, flaky and test-smell checks; with `--set live`, API fuzzing, a ZAP scan, performance and accessibility checks. Gaps become stories for a later sprint |

### Work hierarchy

| Level | Size (defaults) | Tracker |
|---|---|---|
| Epic | one sprint (2 weeks) | a milestone `S<n>` and a `type::epic` issue titled `S<n>: <goal>` |
| Feature | at most half a sprint | a `type::feature` issue under the epic |
| Story | at most 8h, target 4h | a child task of its feature, with an estimate |
| Blocker | anything outside the plan a story waits for | a `type::blocker` issue, urgent, always assigned to a person, with step-by-step instructions |

Dependencies are part of the plan. Stories are created in dependency order. A story waits until what it depends on is merged, or it stacks on that story's open merge request. Sprint sync shows what can run now, what waits, and on whom.

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

## The gates

A gate stops the flow. A check reports and never stops it.

- **Tracker.** Every command first checks the login, access and project.
- **Plan check.** Story and feature sizes, dependencies, cycles and capacity are checked before anything is pushed. Stories that touch sensitive paths need a security review at planning.
- **Story contract.** A story needs Acceptance and Verify before it is built. A story that cannot be tested goes back to the planner.
- **Test immutability.** Test files are hashed after the tester writes them, and the builder may never change them.
- **Verify.** Tests, lint, typecheck, build, the story's own Verify commands and e2e run before review, before the merge request and in CI.
- **Security review.** Runs on every plan, every merge request and at sprint end, and is never skipped. Only security can close a security finding, and no approval mode merges with one open.
- **Scan gate.** Any high or critical SAST finding, or any secret, blocks the merge request.
- **Merge approval.** A person merges by default. `approvals.merge: agent` lets an agent merge once review is clear. `risk` lets low-risk changes merge on their own; sensitive paths or more than `risk.max_changed_lines` changed lines always need a person, and a daily digest lists what merged.
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
| approver | Optional agent approval, only when `approvals.merge: agent` | opus |
| shipper | The sprint's test guide for business testers | haiku |
| mutator | Writes deliberate bugs to check the tests catch them (hardening only) | sonnet |

`security` and `approver` have a floor: no fast-tier model and no low effort.

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
bin/tracker.sh check|ensure-labels|push-plan|story|set-state|open-mr|followup|merge|mr-info|comment \
               |sprint-sync|sprint-items|sprint-done|merge-commit|open-mr-branch|digest --repo .
bin/tracker.sh protect --repo .                        # GitHub: the ruleset, CodeQL and auto-merge
bin/plan-check.sh --repo .                             # sizes, dependencies, capacity
bin/ci.sh --repo .                                     # the merge request pipeline or pull request workflow
bin/issue-templates.sh --repo .                        # the work-item formats as issue templates
bin/verify.sh --repo . --run DIR --story F             # the verify gate
bin/coverage.sh --repo . --base origin/main --run DIR  # changed-line coverage (warning)
bin/test-hashes.sh record|verify --repo . --run DIR    # test immutability
bin/review-gate.sh --findings F [--for merge]          # do review findings still block?
bin/risk.sh --repo . --run DIR --base REF              # low or high risk
bin/ship.sh --repo . --run DIR                         # finish a story: follow-ups, metrics, record, commit
bin/record.sh path|write|story ...                     # decision records
bin/plan-pr.sh --repo . --title T                      # the plan and its records, as a merge request
bin/learnings.sh recall --role R --story F             # the lessons one role needs for one story
bin/metrics.sh collect --repo . --out F                # the sprint report's data
bin/report.sh --data F --out O                         # the sprint report page
bin/test-guide.sh --data F --out O                     # the test guide
bin/mutate.sh, flaky.sh, live.sh, harden-report.sh     # hardening
bin/install-codex.sh [--repo R]                        # install for Codex
```

## Developing

```bash
bats tests/
```

The tests run offline against fake `glab` and `gh` (`tests/fake/`). New behaviour is proven by breaking it on purpose and watching a test fail.

## License

MIT. See [LICENSE](LICENSE). Security reports: [SECURITY.md](SECURITY.md). Contributing: [CONTRIBUTING.md](CONTRIBUTING.md).
