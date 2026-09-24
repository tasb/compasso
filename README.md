# Compasso

A sprint-sized SDLC for Claude Code and Codex. It plans an epic per sprint, features of at most half a sprint, and user stories of at most one day in GitLab; builds stories test-first; and reviews every merge request with a mandatory security review. Humans approve plans and merges by default.

Design: [docs/SPEC.md](docs/SPEC.md). Status: step 1 of 5 (setup and the GitLab adapter).

## Install

**Claude Code**

```bash
claude plugin marketplace add tasb/compasso
claude plugin install compasso@compasso
```

Commands are `/compasso:setup`, `/compasso:plan`, `/compasso:feature`, `/compasso:story`, `/compasso:sprint` and `/compasso:review`.

**Codex**

```bash
git clone https://github.com/tasb/compasso && cd compasso
bin/install-codex.sh                 # once per machine: engine in ~/.compasso/engine, skills in ~/.agents/skills
~/.compasso/engine/bin/install-codex.sh --repo /path/to/project   # per project: .codex/agents with each role's model
```

The same commands are `$compasso-setup`, `$compasso-plan` and so on. Re-run the first command to update, and the second after changing `models.codex`.

## Requirements

`bash`, `git`, `glab` (logged in), `jq`, `yq` (mikefarah v4). Tests: `bats`.

## Use

In the product repository, run `/compasso:setup` (Claude Code) or `$compasso-setup` (Codex). It writes `.compasso/project.yaml`; commit that file.

The scripts can also be run directly:

```bash
bin/config.sh init --repo . --project my-group/my-app   # write the default config
bin/config.sh validate --repo .                          # list every problem
bin/tracker/gitlab.sh check --repo .                     # the tracker gate: login, access, tier
bin/tracker/gitlab.sh ensure-labels --repo .             # create Compasso's labels
bin/issue-templates.sh --repo .                          # install the work-item formats as issue templates
bin/plan-check.sh --repo .                               # check .compasso/plan.yaml: sizes, dependencies, capacity
bin/tracker/gitlab.sh push-plan --repo .                 # create or update the plan in GitLab
bin/tracker/gitlab.sh story --repo . --iid 8           # a story, its coverage threshold and open dependencies
bin/verify.sh --repo . --run DIR --story F               # the verify gate
bin/coverage.sh --repo . --base origin/main --run DIR    # changed-line coverage (warning)
bin/review-gate.sh --findings F [--for merge]           # do review findings still block?
bin/ci.sh --repo .                                       # generate the merge request pipeline
bin/tracker/gitlab.sh sprint-sync --repo .              # what can be built now, what waits and on whom
bin/comment.sh qa|plan ...                              # the feature flow's comments on GitLab
bin/test-guide.sh --data F --out O                     # the HTML test guide for business testers
bin/test-results.sh --guide G --results R              # file a tester's failures as bugs
bin/learnings.sh recall --role R --story F               # the lessons one role needs for one story
bin/install-codex.sh [--repo R]                          # install for Codex
bin/metrics.sh collect --repo . --out F                  # the sprint report's data
bin/report.sh --data F --out O                          # the sprint report page
```

## Develop

```bash
bats tests/
```
