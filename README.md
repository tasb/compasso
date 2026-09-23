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
```

## Develop

```bash
bats tests/
```
