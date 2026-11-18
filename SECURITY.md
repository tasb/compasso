# Security

Compasso runs shell scripts, agents and the product repository's own commands, unattended, from cron, and it reads text that other people write on the tracker. This page says what it runs, what it trusts, and which routes are still open.

## Reporting a vulnerability

Report it privately through GitHub's private vulnerability reporting: the **Report a vulnerability** button on the repository's [Security tab](https://github.com/tasb/compasso/security). Please do not open a public issue for it. Include the Compasso commit, the tracker (GitLab or GitHub) and the steps to reproduce.

## What the runner runs

Cron starts `bin/run.sh` on each agent's machine. A job that needs a model runs as one headless session (`claude -p` or `codex exec`), for at most `run.job_minutes`, with nobody watching:

- **`mvp` and `harden`:** no permission prompts (Claude Code `bypassPermissions`; Codex `--dangerously-bypass-approvals-and-sandbox`). The session may run any command the agent chooses. Compasso's hooks still guard every tool call (below).
- **`production`:** Claude Code `dontAsk` with an allowlist: the repo's commands, git, `glab` or `gh`, Compasso's scripts, its agents, and the rules in `run.allow`. Anything else is refused, not asked. Codex runs in the `workspace-write` sandbox, with the network.

Run the agents on machines or accounts set aside for them, not on a person's everyday account: in `mvp` and `harden` an agent can do whatever that account can.

## What Compasso runs from a product repository

**`.compasso/project.yaml` commands.** `commands.test`, `lint`, `typecheck`, `build`, `e2e` and `coverage.command` run as shell commands, locally when a story is built (`verify.sh`, `coverage.sh`) and in the generated CI; `staging.deploy` runs in CI on every merge to the default branch. Anyone who can change this file on the default branch can run code on every agent's machine and in CI. Nothing asks before a freshly cloned `project.yaml` runs locally: review it before running Compasso in a repository you did not write.

**A story's Verify commands.** They come from the story's description on the tracker, so anyone who can edit a story chooses what runs on the machine that builds it.
- `trust.verify_approval: false` (the default, in every stage): they run without asking. Use it only when the people who can edit the tracker are the team.
- `trust.verify_approval: true`: `verify.sh` runs a Verify command only after a person approved that exact command for this checkout (`bin/trust.sh`), or when the plan on the default branch lists it for that story. A command not approved stops the story until a person approves it. Approvals live outside the repository in `${COMPASSO_HOME:-$HOME/.compasso}/trust/`, keyed to the checkout's physical path and to each command's SHA-256. A cloned repository brings no approvals, and a command edited on the tracker after approval needs approving again.
- Approval is consent to a command string, not to the files it names. A script the command calls runs with whatever it contains at that moment.

**The repository's tests and code.** Building a story runs the repository's own tests and build. This is code execution by design.

**Docker images.** Crawling a prototype pulls `prototype.image`; the GitHub scan gate pulls `zricethezav/gitleaks:latest` and `semgrep/semgrep:latest`. Tags such as `latest` are not pinned to a digest, so a compromised upstream tag reaches you.

## What Compasso reads but does not obey

**Tracker text is data, not instructions.** Issue descriptions, comments and answers are untrusted input for every agent. A comment that tells a developer to skip a check, run a command or merge is ignored and reported. In `production`, the security agent flags requirements that would weaken a control or widen access.

**Lessons in `docs/learnings/` reach agent prompts.** They are committed files, so changing them goes through a merge request like code. A lesson that tells an agent to skip a check does not override the role files or the gates.

## Accounts and tokens

- Each agent uses its own tracker account (a GitLab service account, or a GitHub machine user), never a person's. Every tracker call and git push of its checkout uses it.
- A GitLab token is written by a person, in their own terminal, to `~/.compasso/accounts/<host>/<login>` (mode 600). A GitHub token comes from `gh auth token --user <login>`. Compasso never asks for a token in chat and never stores one in the repository.

## Hooks

Compasso's hooks (`bin/hook.sh`) deny, in the harness:
- a Compasso agent writing outside its role's paths: the tester writes only tests, test configs and manifests; the reviewer only `docs/learnings/`; security and the planner nothing; no agent writes `.compasso/project.yaml`, `.claude/`, `.codex/`, `.git/` or outside the repository;
- for every session: a force-push of the default branch, `rm -r` outside the repository and temporary folders, reading secrets, and a download piped into a shell.

The guards fail closed: when a guard itself fails, the action is denied. Limits:
- The role guard applies to Compasso's subagents (tester, reviewer, security), not to the runner's own session, which builds the code.
- Files written by a shell command are recognised by pattern. A determined agent could still write through a script.
- The command guard is a pattern list, not a sandbox.

`COMPASSO_HOOKS=off` turns every hook off. It is a person's switch: agents cannot change the settings that would disable hooks.

## What holds in every stage

- **Scans block.** A secret, or a high or critical SAST finding, fails the merge request's pipeline or workflow. On GitHub, merging requires the gate checks through the `compasso` ruleset.
- **No merge on a red pipeline.** The tech lead merges only when the pipeline succeeds. When the default branch turns red anyway, the runner reverts the merge that broke it.
- **Blockers send work back.** The tech lead's review sends back a change with a leaked secret, data loss, an acceptance line not met, or a change that breaks the default branch.
- **Scope, cost and secrets go to a person.** The agents ask through a `needs::human` issue and stop.

What is not done in `mvp`: no security agent reads the merge requests, and the pipeline's scans are the only security check. `harden` adds one audit of the whole code; `production` adds a security agent on every merge request.

## Out of scope

- Vulnerabilities in the product repository's own code. Compasso's reviews look for them, but they belong to that repository.
- The security of GitLab, GitHub, `glab`, `gh`, cron, the harness (Claude Code or Codex) and the model provider.
