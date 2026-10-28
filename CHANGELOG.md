# Changelog

Versions follow `version` in `.claude-plugin/plugin.json`. Claude Code updates an installed plugin only when this version changes, so every change users should receive ships in a new version.

## 3.3.0 (2026-10-27)

Balanced tests, from the GoSales sprint 1 report: the tester was the costliest role (16.7M tokens, 829 agent minutes, more than the builder), and an acceptance line was often tested three times. Upgrade notes for the agent: [docs/releases/3.3.0.md](docs/releases/3.3.0.md).

- **Each acceptance line is tested once,** at the cheapest level that can observe it: unit for logic, rules, edge and abuse cases, e2e for a line that needs the real boundary. A story's tests may be `unit`, `e2e` or both: `plan-check` no longer requires `unit`.
- **A finished feature gets e2e only for what its stories' tests left out.** With nothing to add there is no e2e merge request; the whole suite and e2e still run (`verify.sh --e2e`, also used by the sprint's regression).
- **Verify runs e2e last,** only when every other command passed.
- **No local coverage in `mvp`:** `coverage.sh` is skipped, and the merge request says "not measured in the MVP".
- **No tests of prose.** The tester refuses tests that pin the wording of docstrings, comments or documentation; a wrong comment is fixed in its text.
- **Time in checks is measured:** each verify command's seconds and the coverage run go to the story's metrics (`verify_seconds`) and the sprint report (`quality.verify_minutes`, a "Time running checks" tile).

## 3.2.0 (2026-10-27)

MVP fast mode, from a team's retrospective in `mvp`: merges per day fell 3.9 times after 3.1.0, a merge request waited about 8 hours for the tech lead's poll, verify ran the suite twice, and developers asked most about stories they could not build. Upgrade notes for the agent: [docs/releases/3.2.0.md](docs/releases/3.2.0.md).

- **In `mvp` only blocker and major findings are fixed in the story.** The open minors are filed as one `compasso::after-mvp` issue per story, in no sprint, never assigned during the MVP. Every finding to be filed carries an acceptance line its reviewer wrote, and a follow-up's Verify lists real commands. Reviewer and security rate anything that can leak or destroy data, widen access, fail open or break production at least major.
- **In `mvp` a change merges on green.** The developer sets its own merge request to merge when nothing needs a person: no approver, no behind rule. The tech lead handles high risk, rejections and a red main: `team.sh main` turns off auto-merge while main is red, and `team.sh fix-main` files the fix as a blocker bug for the developer whose merge broke it (new `tracker.sh main-pipeline` and `disarm`). `production` keeps 3.1.0's rules.
- **In `mvp` the tech lead answers questions on its own,** unless scope, security or cost change, and lists its answers. A developer takes the next batch in the same tick.
- **Not ready.** In a team project a story with no acceptance or Verify, or a `dev::` label naming no one in the team, is never built or assigned; the tech lead's inbox lists it. A story whose paths overlap a merge request still open waits for it to merge.
- **Verify runs each command once,** and the `mvp` pipeline leaves out e2e and coverage (regenerate it with `ci.sh`).
- **Sensitive paths in `mvp`** are named as a warning on the merge request and in the tech lead's review.
- `followups.sh legacy [--close]` closes the old follow-ups no test could check (new `tracker.sh close`). `start` and `status` warn when an older Compasso runs than the newest installed. A continued agent whose dispatch was never bound no longer fails with "unknown role 'null'".

## 3.1.2 (2026-10-23)

Upgrade notes for the agent: [docs/releases/3.1.2.md](docs/releases/3.1.2.md).

- **The presentation's menu no longer scrolls sideways on a wide screen.** The links wrap onto a second row when they do not fit, the light/dark button stays at the right of the first row, and sections leave room for a two-row menu. On a phone the menu is still one row you swipe.

## 3.1.1 (2026-10-22)

Upgrade notes for the agent: [docs/releases/3.1.1.md](docs/releases/3.1.1.md).

- **The 3.1.0 upgrade notes no longer say `/compasso:setup` is required.** `team.lead_merge_minutes` is optional (missing means 15); setup only writes the key so it can be changed. No code changed.

## 3.1.0 (2026-10-21)

From reading a team's tracker in `mvp`: follow-ups nobody built, merge requests stacked four deep, a red default branch, and queues full of stories that could not start. Upgrade notes for the agent: [docs/releases/3.1.0.md](docs/releases/3.1.0.md).

- **Every finding is fixed in its story,** minors too. Only a minor finding whose fix needs someone other than the developer (a person, an outside admin) becomes a follow-up: `needs` names who, and it is filed `owner::human` in the story's sprint. The findings are also posted on the story.
- **Follow-ups keep their labels in a team project** (`owner::human`); before, every follow-up there was filed with none and in no sprint. `bin/followups.sh` moves the open ones in no sprint into the current sprint.
- **No stacking.** A story waits until what it depends on is merged. `open-mr --target` and `open-mr-branch` are gone.
- **Main stays green.** No merge, in any mode, after a failed pipeline. The tech lead merges only a branch that is up to date with its target, with no conflicts and a pipeline that is not running; `team.sh update` brings one up to date (new `tracker.sh mr-checks` and `mr-update`).
- **Two polls for the tech lead:** `/compasso:work --merge` every `team.lead_merge_minutes` (default 15) and `/compasso:work --flow` every `team.lead_poll_minutes` (30), each in its own session.
- **The queue counts what can be built,** and the tech lead assigns first the stories that can start and hold up the most others. Work for a person is never offered to a developer.
- The approver runs once per version of a change: a rebase that changes nothing keeps its verdict.

## 3.0.2 (2026-10-20)

From a team running `compasso:work` in `mvp`: a person was asked again and again to reset a role's budget and to approve Verify commands.

- **Rework has its own budget.** A merge request the tech lead sends back used to be reworked on what was left of the first build's budget, so the tester ran out at once. The story flow now starts a new one (`budget.sh rework`, refused while the story is building); the spent one is kept as `budget-<n>.jsonl`.
- **The tech lead's approver runs once per head.** Its review folder is now `.compasso/runs/lead-<mr>-<head>`, so reviewing a reworked merge request no longer hits the approver's limit of 1 spent on the earlier head.
- **New limits for new projects:** tester 9, builder 10, reviewer 6, total 30. An existing project keeps its values; edit `limits.agent_runs` to take them.
- **In `mvp` only the total limit applies:** `limits.agent_runs.mvp_total`, default 40.
- **The plan approves its Verify commands.** A story's Verify command runs without asking when the plan on the default branch lists it for that story. Edited commands, follow-ups and bugs still ask.
- **In `mvp` Verify commands run without approval,** unless `trust.mvp_approval: true`. `production` ignores it.
- No setup needed: a project without the new keys uses their defaults.

## 3.0.1 (2026-10-15)

Fixes reported from a team running the story flow on GitLab ([#1](https://github.com/tasb/compasso/issues/1)).

- **Follow-ups attach where GitLab allows them.** GitLab allows no Task under a Task, so a follow-up of a story with no feature was created and then left unattached, and `ship.sh` stopped. A story's follow-up now goes to its feature, else to its sprint's epic. A failed attach is tried again (GitLab's transient "Internal server error"). When no parent works, the follow-up is linked to the story ("relates to") and GitLab's own error is shown. Either way its number is returned, so running `ship.sh` again never files it twice. GitHub's follow-ups also retry and are always returned.
- **One dispatch spends one run.** On Claude Code the hook claims the budget when an agent is dispatched; a `budget.sh claim` by hand is now refused there instead of spending a second run. Codex, where the claim is made by hand, is unchanged. `budget.sh reset --role <role>` gives one role its runs back.
- **Commands are discoverable.** Every script answers `--help` with the commands written at its top. `tracker.sh` says when a command belongs to `team.sh` (`release`, `working`, `claim`...). The story flow says to run `ship.sh` on its own and read its result before pushing.

## 3.0.0 (2026-10-15)

From running 2.0.0 with a tech lead and developers. Team projects change how they merge; every project gets the stage, the security rule and the new risk rules.

- **Stage.** `stage: mvp | production` (no stage is `production`). In `mvp` a person approves only an infrastructure change whose cost report says `increase` or `unknown`. In `production` the high-risk reasons apply, now including infrastructure, migrations and public API contracts (`risk.infra_paths`, `risk.production_paths`) and a change security marks sensitive by its content.
- **Product lines.** `risk.max_changed_lines` counts only the lines of `risk.product_paths` (default `src/**`): tests, configuration, docs and other folders no longer count. A security finding fixed in its own story no longer makes the change high risk.
- **Security closes what it opens.** Every security round ends with each finding `fixed` or, for a minor one only, `followup`, both verified by security; a deferred finding becomes a follow-up story. The story flow does not open a merge request until then. This is what stopped merge requests from ever merging.
- **Reports on the merge request.** The run posts its findings, and for an infrastructure change the new **finops** role's cost report, as comments the tech lead reads back (`bin/mr-report.sh`); a later round edits them in place.
- **The tech lead merges** (team projects). The developer opens the merge request and stops. The tech lead's poll reads the reports, works out the risk from the branch, has the approver check it, and merges; when the risk needs a person it labels the merge request `needs::approval`, and a person approves or rejects it with the tracker's own review. A rejection goes back to the same developer on the same merge request. New `team.sh review|ask|merge|return`; `tracker.sh merge` is refused in a team project.
- **Status labels.** `compasso::backlog` (assigned, not started) joins `building` and `in-review`. The tech lead polls every `team.lead_poll_minutes` (default 30); developers every `team.poll_minutes` (60).
- **The queue.** In `mvp` the tech lead keeps each developer's backlog between `team.queue.min` (5) and `team.queue.target` (15) on its own, within the sprint.
- **One account per agent.** `persona.sh account --set <login> --email <email>`: every tracker call and git push of the checkout use that account's token (a GitLab service account; a GitHub machine user), and its commits carry the agent's name and email. `team.agents` lists the agents' logins, whose approvals never count as a person's.
- **Upgrading.** Run `/compasso:setup` once in each project: it adds the new keys and the finops model to `.compasso/project.yaml` and creates the `compasso::backlog` and `needs::approval` labels. Until then the configuration does not validate. The tech lead's setup runs `team.sh mark-backlog` on every open sprint, so work assigned before 3.0.0 counts in the queue. Developers who joined under 2.x run setup again to set their account and paste the new join block into the tech lead: their name is kept and their account recorded in `team.agents`.

## 2.0.0 (2026-10-13)

Personas: several agents on one project. Claude Code only for now. Projects that do not turn a team on work as before.

- **Personas.** Setup asks what the agent is: `default` (everything, as before), `tech-lead` (scope and assignment; never builds) or `developer` (builds what is assigned to it; always an agent, with a name). The persona is kept per checkout, outside the repository. Every command and every tracker write checks it first.
- **Teams.** `team.enabled: true` makes a project a team project. A developer's setup prints a JSON block; pasted into the tech lead's agent, it creates the label `dev::<name>`.
- **Assignment by label.** In a team project every story names its developer (`dev: <name>` in the plan, on the story or its feature), `owner::` labels are not used, and work for a person is a blocker. Bugs are filed with no developer and wait for the tech lead.
- **One agent per story.** An agent claims a story with a comment before building it; the earliest claim wins. This applies without a team too, so two sessions no longer build the same story.
- **Messages.** The tech lead and developers talk through comments on the story, at most 250 characters. A developer's question raises the new `needs::lead` label; the answer lowers it.
- **The poll.** New `/compasso:work`: each agent reads the tracker every `team.poll_minutes` (default 60) and skips the read while it works. The tech lead's agent proposes answers and assignments; a person decides.
- **Upgrading.** Run `/compasso:setup` once: it adds the `team` keys to `.compasso/project.yaml` and the `needs::lead` label. Until then the configuration does not validate.
- New scripts `bin/persona.sh` and `bin/team.sh`; guide: `docs/guides/team.md`.

## 1.2.1 (2026-10-05)

Fixes reported from a real project.

- **Large plans:**
  - `/compasso:present` left an empty page and still reported success when its data passed 128 KB, the most Linux allows one argument or environment variable.
  - The same limit stopped `/compasso:sprint` and `/compasso:status` (through `sprint-sync`) on sprints with long descriptions, and could break `plan-check`, `story` and the sprint report.
  - Large JSON now always travels through files. The three HTML pages are written by `bin/html-inject.sh`, which checks the page before keeping it and never leaves an empty or partial file.
- **Language and title:** the test guide, the sprint report and the presentation now carry `lang` and `<title>` in the HTML itself, in the project's language, for screen readers, hyphenation, the browser tab and the printed header.

## 1.2.0 (2026-10-04)

- Setup asks the project's language: English, Portuguese (Portugal) or Portuguese (Brazil). It covers work items on the tracker, the issue templates, comments, merge requests, and the brief, records, test guide, sprint report and presentation. Labels stay in English.
- Compasso reads work items in every language it ships, so items written in another language, or before a change of language, keep working.
- Each language is one file of texts plus its issue templates and brief; adding a language changes no code.
- `test_guide.language` becomes `language`; `config.sh upgrade` keeps an existing choice.

## 1.1.0 (2026-10-03)

- `/compasso:architect` designs the technical solution between the backlog and the roadmap: stack, components serving the backlog's features, integrations, data, observability (from an observability prototype), security, environments, decisions with their alternatives, and risks. It is checked by `bin/architecture-check.sh`, reviewed by security, and approved.
- `/compasso:present` builds one self-contained HTML presentation of the functional and technical solution, the decisions, the sprints and the next sprint's user stories, from Compasso's files.
- Single-file HTML prototypes are read as source; several prototypes share one screen inventory.
- The test guide, the sprint report and the presentation write every `<` in their data as `\u003c`, so no text can end the data block or open a tag.

## 1.0.0 (2026-10-03)

First release. Installs made before it reported `0.1.0`, a snapshot of work in progress that `claude plugin update` could not move past; update to this version.

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
- A sprint batch's stories are built side by side in worktrees under `.compasso/worktrees/`, all driven by the conversation running the sprint, since a subagent cannot start agents.
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

### Test frameworks

- A default per language and test area (unit, API, browser e2e, coverage, property-based) for JavaScript/TypeScript, Python, Go, Java/Kotlin, C#/.NET, Ruby, PHP, Rust and Bash. It is used only where the project has nothing yet; what the project already uses always wins (`bin/test-stack.sh`).

### Hooks

- Hooks enforce in the harness, on Claude Code and Codex:
  - a role guard (each agent writes only where its role may);
  - the agent-run budget;
  - a command guard (force-push of the default branch, `rm -r` outside the repository, secrets, downloads piped into a shell).
  They also record agent-run metrics, and say where local runs stopped after a compaction. The guards fail closed; `COMPASSO_HOOKS=off` turns them off.

### Agents

- Roles are registered Claude Code subagents (`compasso:<role>`), generated from `roles/`, each with only the tools it needs: security and the approver can only read, and no role can start another agent.
- Strict orchestration: every agent has a turn limit, and `bin/budget.sh` caps each role's runs in one flow run; when it runs out, the flow stops and hands back to a person.

### Harnesses

- `bin/codex-models.sh` checks `models.codex` against what the Codex account can use and proposes replacements by tier.
- Claude Code plugin and Codex skills from the same sources, with a model per role and harness. `security` and `approver` cannot use a fast-tier model or low effort.
