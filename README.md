# Compasso

A sprint-sized SDLC for Claude Code and Codex. It plans an epic per sprint, features of at most half a sprint, and user stories of at most one day in GitLab; builds stories test-first; and reviews every merge request with a mandatory security review. Humans approve plans and merges by default.

Design: [docs/SPEC.md](docs/SPEC.md). Status: step 1 of 5 (setup and the GitLab adapter).

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
```

## Develop

```bash
bats tests/
```
