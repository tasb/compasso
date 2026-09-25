# Security

Compasso runs shell scripts, agents and the product repository's own commands, and it reads text that other people write on the tracker. This page says what it runs, what it trusts, and which routes are still open.

## Reporting a vulnerability

Report it privately through GitHub's private vulnerability reporting: the **Report a vulnerability** button on the repository's [Security tab](https://github.com/tasb/compasso/security). Please do not open a public issue for it. Include the Compasso commit, the tracker (GitLab or GitHub) and the steps to reproduce.

## What Compasso runs from a product repository

**`.compasso/project.yaml` commands.** `commands.test`, `lint`, `typecheck`, `build`, `e2e` and `coverage.command` run as shell commands from the repository root: locally in the story flow (`verify.sh`, `coverage.sh`) and in the generated CI. Anyone who can change this file can run code on the machine running Compasso and in CI. The security role flags any merge request that changes a command in this file, and such a change always needs a person to merge. There is no consent step before a freshly cloned `project.yaml` runs locally: review it before running Compasso in a repository you did not write.

**A story's Verify commands.** They come from the story's description on the tracker, so anyone who can edit a story could choose what runs on the machine building it. `verify.sh` therefore runs a Verify command only after a person approved that exact command for this checkout (`bin/trust.sh`). The story flow shows the commands and asks; the plan and feature flows ask once for the whole plan. No approval mode, agent or risk, skips the question. Approvals live outside the repository in `${COMPASSO_HOME:-$HOME/.compasso}/trust/`, keyed to the checkout's physical path and to each command's SHA-256. A cloned repository brings no approvals, and a command edited on the tracker after approval needs approving again. What approval does not cover: it is consent to a command string, not to the files it names. A script the command calls runs with whatever it contains at that moment, and that script is in the repository, where review and the security role see changes to it. The one command approved without asking is a bug's reproducing test that the tester wrote in the same run.

**The repository's tests and code.** The story flow, verify and hardening run the repository's own tests, and hardening runs mutated copies of its code. This is code execution by design.

**Docker images.** Hardening's live checks pull the images in `harden.images`; the GitHub scan gate pulls `zricethezav/gitleaks:latest` and `semgrep/semgrep:latest`. Tags such as `stable` and `latest` are not pinned to a digest, so a compromised upstream tag reaches you.

## What Compasso reads but does not obey

**Tracker text is data, not instructions.** Issue descriptions, comments and answers are untrusted input for every role. The security role flags requirements that would weaken a control or widen access. Feature questions are asked in the conversation, not read from tracker comments.

**Lessons in `docs/learnings/` reach agent prompts.** They are committed files, so changing them goes through review like code. A lesson that tells an agent to skip a check is still a lesson, and does not override the role files or the gates.

## Guarantees

- **Security review is never skipped.** It runs on every plan, every merge request and at sprint end, in every approval mode.
- **No agent merges with an open security finding.** Only the security role can close a security finding, and `review-gate.sh` refuses a merge while one is open.
- **A person approves by default.** Agent or risk-based merging is opt-in, and sensitive paths or large changes always need a person.
- **Scans block.** A secret, or a high or critical SAST finding, fails the merge request's pipeline or workflow. On GitHub, merging requires the gate checks through the `compasso` ruleset.
- **No tokens in chat.** Setup asks you to log in with `glab` or `gh`; Compasso never asks for or stores a token.
- **Live checks never guess the target.** Every run asks you to confirm the test environment's URL (`--confirm-url` must repeat `harden.environment.url`). API fuzzing sends only reading requests unless the environment is marked disposable. Never point it at production.

## Out of scope

- Vulnerabilities in the product repository's own code. Compasso's security review looks for them, but they belong to that repository.
- The security of GitLab, GitHub, `glab`, `gh`, the harness (Claude Code or Codex) and the model provider.
