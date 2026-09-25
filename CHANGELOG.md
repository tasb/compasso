# Changelog

Versions follow `version` in `.claude-plugin/plugin.json`. Nothing has been released yet; everything below is on `main`.

## 0.1.0 (unreleased)

First version.

### Planning

- Three levels: an epic per sprint, features of at most half a sprint, stories of at most one working day (target half a day). `plan-check` enforces sizes, dependencies, cycles and capacity before anything reaches the tracker.
- `/compasso:plan` plans a sprint top-down; `/compasso:feature` plans one feature with up to 3 rounds of questions in the conversation. The security role reviews every plan, and the tester refuses stories with nothing observable to build.
- Blockers are tracker issues: urgent, always assigned to a person, with step-by-step instructions.
- `.compasso/plan.yaml` is the source of every push; pushes are idempotent and create stories in dependency order.

### From ideas to sprints

- `/compasso:start` finds where a product stands and runs the next step: `/compasso:discover` (a product brief from ideas, documents, tracker issues or a prototype), `/compasso:backlog` (features with rough hours, dependencies and an explicit MVP line, pushed to the tracker in no sprint) and `/compasso:roadmap` (features placed into sprints by dependency and capacity, MVP first). `/compasso:plan` then plans the roadmap's next sprint.
- A prototype can be the starting point: a running web app crawled by following links only, its source code, or a Figma file, all turned into one screen inventory. `backlog-check` notes every screen no feature covers.
- A repository with no code starts with a walking skeleton feature.

### Building

- `/compasso:story` builds a story test-first: the tester's failing tests, then the builder, who may never change them (test immutability by hashes).
- A story's Verify commands come from the tracker, so each exact command runs only after a person approved it for this checkout (`bin/trust.sh`); `verify.sh` refuses unapproved ones.
- The verify gate runs the repo's commands, the story's Verify commands and e2e before review, before the merge request and in CI.
- Review and the mandatory security review run with an automatic fix loop of at most 3 rounds. Only security can close a security finding. Open minor findings become backlog stories.
- `/compasso:sprint` builds everything that can run now, in dependency order and in parallel where paths do not overlap. A story can stack on the open merge request of the story it depends on.
- `/compasso:review` reviews any merge request.
- `/compasso:status` is a read-only readout of the sprint or one story: what can be built, what waits and on whom, and where an interrupted run stopped.

### Approvals

- A person approves plans and merges by default.
- `approvals.merge: agent` lets an agent merge once review is clear; `risk` lets low-risk changes merge on their own, with a daily digest. Sensitive paths and large changes always need a person. No mode merges with an open security finding.

### Checks in CI

- A generated GitLab pipeline or GitHub workflow runs verify, e2e and changed-line coverage.
- Coverage below 80% of changed lines is a warning, never a block; an epic, feature or story can set its own threshold.
- Scans: GitLab SAST and Secret Detection with Compasso's scan gate; on GitHub, CodeQL and secret scanning where available, otherwise Gitleaks and Semgrep in the scan gate. Any high or critical finding, or any secret, blocks the merge request.

### Trackers

- GitLab (Free way on every tier) and GitHub: milestones and Project iterations, sub-issues, native "blocked by", Project estimate and Status fields. `bin/tracker.sh` picks the adapter from `tracker.provider`.
- `tracker.sh protect` sets the GitHub ruleset, CodeQL default setup and auto-merge.

### Records, memory and reporting

- A decision record per plan, feature and story in `.compasso/records/S<n>/`: findings, decisions, takeaways, constraints and missing points. Plans reach the default branch through a plan merge request.
- Targeted learnings in `docs/learnings/`, recalled per role and per story.
- Per-story metrics and an HTML sprint report: delivery, flow and waiting, quality, agent effort and cost.
- An HTML test guide for business testers at sprint end; their results come back as bugs.

### Hardening (optional, after the MVP)

- `/compasso:harden`: a code set (mutation testing with agent-written mutants, property-based tests, flaky tests, test smells) and a live set against a test environment (API fuzzing, ZAP baseline, performance, accessibility). Gaps become stories for a later sprint.

### Agents

- Roles are registered Claude Code subagents (`compasso:<role>`), generated from `roles/`, each with only the tools it needs: security and the approver can only read, and no role can start another agent.
- Strict orchestration: every agent has a turn limit, and `bin/budget.sh` caps each role's runs in one flow run; when it runs out, the flow stops and hands back to a person.

### Harnesses

- Claude Code plugin and Codex skills from the same sources, with a model per role and harness. `security` and `approver` cannot use a fast-tier model or low effort.
