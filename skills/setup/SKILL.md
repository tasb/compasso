---
name: setup
description: Compasso setup - connect a repository to its GitLab or GitHub tracker and record the stage, sprint, commands, the team and models in .compasso/project.yaml, and print the crontab line that runs this checkout's agent. Use when the user invokes /compasso:setup or $compasso-setup, or when another Compasso command reports that setup is missing.
---

Connect this repository to Compasso. Every other Compasso command refuses to run until this succeeds. Scripts live in `${CLAUDE_PLUGIN_ROOT}/bin` (Codex: the `bin` folder next to this skill's plugin root).

Ask one topic at a time, show the default, and accept "default" as an answer. Never invent values the user did not confirm.

0. **Upgrade.** If `.compasso/project.yaml` exists, first run `bash ${CLAUDE_PLUGIN_ROOT}/bin/config.sh upgrade --repo .` so keys added by a newer Compasso are present.

1. **Tracker and login.** Ask which tracker: GitLab or GitHub (propose the one `git remote -v` points at). Never ask for a token in chat; the `!` prefix below runs the command in this session. Continue when the user confirms.
   - GitLab: `glab auth status --hostname <host>` (default `gitlab.com`); if not logged in, ask them to run `! glab auth login --hostname <host> --web`.
   - GitHub: `gh auth status --hostname <host>` (default `github.com`); if not logged in, ask them to run `! gh auth login --hostname <host> --web`. A GitHub Project needs the `project` scope: if `gh auth status` does not list it, ask them to run `! gh auth refresh --hostname <host> -s project`.

1b. **Persona.** Ask what this agent is in the project; show `bash ${CLAUDE_PLUGIN_ROOT}/bin/persona.sh show --repo .` when one is set. A persona belongs to this checkout and is kept outside the repository; it is not a role: the roles of step 7 are the subagents every persona dispatches.
   - **Default**: one agent does everything, as Compasso always worked. `persona.sh set --repo . --persona default`, and continue with every step.
   - **Tech lead**: plans, reviews, merges and delivers; never builds. `persona.sh set --repo . --persona tech-lead`. Ask for the developers' names (`team.developers`, for example `[jobs, woz]`: lowercase letters, digits and hyphens) and how many ready stories each developer should have waiting (`team.queue.min`, default 5: below it the runner assigns more, from the earliest sprint first, a later sprint's too). `team.enabled: true` and these are written with the other answers in step 8. Continue with every step: the tech lead owns the configuration. Say what a team changes: every story names a developer (the label `dev::<name>`) and `owner::` labels are not used, except `owner::human` on work only a person can do; an agent with no persona only reads.
   - **Developer**: builds what is assigned to it; always an agent. The project must already be a team: `.compasso/project.yaml` with `team.enabled: true`, from the default branch. Without it, stop before step 2 and say the tech lead's setup comes first, and that its configuration must be on the default branch and pulled here. Ask for the developer's name: one of `team.developers` (when it is not there, stop: the tech lead adds it first). Then `persona.sh set --repo . --persona developer --name <name>`. A developer never changes the configuration: do only steps 1, 1c, 6b, 9, 12 and 13.

1c. **Account (tech lead and developer; offered to default).** An agent uses its own tracker account, never a person's: a person cannot approve work their own account wrote, and the tracker's history shows who did what. Never ask for a token in chat.
   - GitLab: a **service account** per agent (every tier; created by a group Owner, or a project Maintainer, and added to the project as Developer; it uses no seat). Its personal access token is written by the person, in their own terminal (not with `!`), to the file `persona.sh account` names; the command prints how.
   - GitHub: GitHub has no service account: a **machine user** (an account a person creates for automation, shared by the project's agents), with write access to the repository and the GitHub Project. Ask the person to add it to gh: `! gh auth login --hostname <host> --web`, signing in as the machine user; then `! gh auth switch --hostname <host> --user <their own login>` gives gh back to them: Compasso asks gh for the agent's token by its login.
   - Ask for the login and the agent's commit email (for example `ana@agents.<domain>`), and have the person confirm that no person uses this account. Then `bash ${CLAUDE_PLUGIN_ROOT}/bin/persona.sh account --repo . --set <login> --email <email>`: every tracker call and git push of this checkout use that account from then on, and its commits carry the agent's name and that email. Running it again with another login changes the account; the next call uses it.

2. **Config file.** If `.compasso/project.yaml` exists, read it and treat every question below as "keep or change". Otherwise ask for the project (GitLab `namespace/project`, GitHub `owner/repo`); propose the one from `git remote -v`. Then run:
   `bash ${CLAUDE_PLUGIN_ROOT}/bin/config.sh init --repo . --project <project>`
   GitLab: for a self-managed server, set `tracker.host`, and ask for the tier (`free` or `premium`) because detection only works on gitlab.com.
   GitHub: set `tracker.provider: github` and `tracker.host` (default `github.com`). Then ask, one at a time, and never assume:
   - **Project.** Which GitHub Project holds sprints, estimates and status (its number from the Project's URL), or `0` for none. With none, estimates and sprint iterations are not recorded and the report shows no hours.
   - **Fields.** The Project's number field for estimates in hours, its iteration field for sprints, and its single-select status field (`tracker.github.fields`; defaults `Estimate (h)`, `Iteration`, `Status`). Offer to create any that are missing (`gh project field-create`); the iteration field is created in the Project's web settings when `gh` cannot.
   - **Status options.** Which status option means each Compasso state (`tracker.github.status`: `new`, `building`, `in-review`, `done`; defaults `Todo`, `In progress`, `In review`, `Done`). A state with no option only changes the label.

2b. **Language.** Ask which language Compasso writes in for people: `bash ${CLAUDE_PLUGIN_ROOT}/bin/locale.sh --list` (English, Português (Portugal), Português (Brasil)); default `en`. Set `language`. Say what it covers: work items on the tracker (their headings and key lines, and the text the agents write), the issue templates, comments and merge requests, and the files in the repository (brief, records, test guide, report, presentation). Labels stay in English: scripts and tracker filters use them. Code, tests, commit messages and branch names follow the repository's own conventions. Compasso reads work items in any language it ships, so changing it later breaks nothing.

3. **Sprint.** Length in weeks (default 2), hours per working day (default 8), and team capacity in hours per sprint (default: weeks × 5 × hours per day, for one person; ask how many people, humans and agents, share the sprint).

4. **Limits.** Story hard limit (default 8h, and never above one working day) and target (default 4h). Explain that a feature may take at most half a sprint, derived from the sprint length.

5. **Commands.** In a repository with no product code yet (`bash ${CLAUDE_PLUGIN_ROOT}/bin/start.sh --repo . --json` says `greenfield: true`), leave every command empty, skip the pipeline, and say so: the walking skeleton (the backlog's F-0) sets up the stack and its test runners, and setup runs again once it is merged. Otherwise, detect the repo's own `test`, `lint`, `typecheck`, `build` and `e2e` commands from its manifests (for example `package.json` scripts, `Makefile`, `pyproject.toml`, `go.mod`, CI files). Present what you found and let the user confirm or correct each; leave a command empty when it does not apply. If the repo has a UI or public API and no e2e command, say so and suggest a framework (Playwright for web, the project's own test runner for APIs, bats for CLIs), without installing anything.

   **Coverage.** Find the repo's coverage command and the Cobertura or LCOV file it writes, and the product-code paths (for example `src/**`). Default threshold: 80% of changed lines; below it is a warning, never a block. Without a command, every merge request shows coverage as "not measured" - say so.

   **Test frameworks.** `bash ${CLAUDE_PLUGIN_ROOT}/bin/test-stack.sh detect --repo .` shows, per language and area (unit, API, browser e2e, coverage, property-based), what the project already uses, and Compasso's default where it has nothing. Defaults never replace what exists: they fill only empty areas, and are added by the first story that needs them. Let the user change any default, then `bash ${CLAUDE_PLUGIN_ROOT}/bin/test-stack.sh write --repo .` (edit `testing` in the config for their changes). When there is no coverage command and coverage shows a default, propose its `command` and `report` from `test-stack.sh detect --json`.

   **Tests.** Show `test_paths` (what counts as a test file; in `production` the tester writes them and the developer never changes them) and adjust it to the repo's layout.

   **Pipeline.** Ask for the CI image that has the repo's toolchain (`ci.image`, for example the image the repo's CI already uses), then, once step 8 has written every answer (the stage among them: in `mvp` the pipeline leaves out e2e and coverage), run `bash ${CLAUDE_PLUGIN_ROOT}/bin/ci.sh --repo .`.
   - GitLab: add `include: [{ local: .gitlab/compasso.gitlab-ci.yml }]` to `.gitlab-ci.yml` (create it if missing). The file runs the verify gate, e2e, changed-line coverage as a warning, and GitLab SAST and Secret Detection on every merge request.
   - GitHub: it writes `.github/workflows/compasso.yml`: the verify gate, e2e and changed-line coverage as a warning on every pull request. Security scans are GitHub's own (CodeQL and secret scanning) when the repository has them - public, or private with Advanced Security - and otherwise Compasso's scan gate (Gitleaks and Semgrep). Say which one it chose.

6. **Stage.** Ask the project's stage (`stage`), and say what each one checks before a change merges:
   - `mvp`, for a product nobody uses yet: the pipeline's secret and SAST scans, and the tech lead's one review pass that looks only for blockers (an acceptance line not met or not tested, data loss, a leaked secret, a change that breaks the default branch). Everything else goes to one after-MVP list and never becomes work in the MVP. The pipeline leaves out e2e and coverage.
   - `harden`: as `mvp`, plus one audit of the whole code by the tech lead; the after-MVP list is drained into stories under one hardening feature.
   - `production` (what no stage means): a reviewer and a security agent read every merge request beside the tech lead, one pass each; their blocker and major findings send it back once, a second rework goes to a person. The developer gets its tests from the tester, and the pipeline runs e2e and coverage.
   In every stage the runner asks nobody for permission: in `mvp` and `harden` sessions run without permission prompts; in `production` only the repo's commands, git, the tracker CLI, Compasso's scripts and agents, and `run.allow` run. A story's Verify commands run without a person's approval unless `trust.verify_approval: true`; say plainly that anyone who can edit a story on the tracker then chooses commands the agents run, and offer `true` for a tracker that people outside the team can edit. Switching stage is a person's decision: setup again, or an edit to the file merged to the default branch; after it run `bin/ci.sh --repo .` and commit its output.

   **Staging.** Ask for the command that deploys the default branch to staging (`staging.deploy`, run in `ci.image` on every green merge) and its address (`staging.url`). When a feature's stories are all merged, the tech lead asks people to test it there.

   **People.** Ask for the tracker logins of the people the agents ask (`people.ask`): each question is a `needs::human` issue assigned to them, with the evidence, numbered steps and what the agents do meanwhile. The person answers there and closes it; the runner goes on by itself.

   **Runner.** Show `run` (`lead_minutes` 15, `dev_minutes` 10, `job_minutes` 60, `failures` 2: failed jobs on one story before a person is asked) and ask whether to change any.

   **Plan approval and sensitive paths.** Plan approval: `human` (default) or `auto`. Ask for the sensitive paths (`risk.sensitive_paths`: authentication, payments, personal data, secrets handling); when `.compasso/architecture.yaml` exists, propose them from its components, for the person to accept. Their stories get abuse cases from security at planning.

6b. **Hooks.** Say what Compasso's hooks do in this repository and nowhere else: the role guard (each agent writes only where its role may: the tester never touches product code, security only reads), the command guard (no force-push of the default branch, no `rm -r` outside the repository, no reading secrets, no piping a download into a shell), and agent-run metrics. On Claude Code they come with the plugin; on Codex, `install-codex.sh --repo` writes `.codex/hooks.json` and the user approves them once with `/hooks`. `COMPASSO_HOOKS=off` in a person's shell turns them off.

7. **Harnesses and models.** Ask which harnesses the team uses: `claude`, `codex`, or both. Show the model table for each chosen harness from the config and ask whether to change any role. The `security` role has a floor: no fast-tier model and no low effort. Remove the `models.<harness>` block of a harness that is not used. When the team uses Codex, first check its models against what this Codex account can use: `bash ${CLAUDE_PLUGIN_ROOT}/bin/codex-models.sh check --repo .` (it reads `codex debug models`). Show every problem with its proposal (by tier: strong roles never get a fast model), and after the user agrees run it again with `--apply`; a model the account cannot use makes that agent fail at its first run. Then, after validating (step 8), run `bash ${CLAUDE_PLUGIN_ROOT}/bin/install-codex.sh --repo .` to write `.codex/agents/compasso-*.toml` with each role's model (tell the user to run `install-codex.sh` once without `--repo` on each machine first, and to re-run the `--repo` form after changing models).

8. Write every answer with `yq -i` edits to `.compasso/project.yaml`, then validate:
   `bash ${CLAUDE_PLUGIN_ROOT}/bin/config.sh validate --repo .`
   Fix and re-ask until it passes.

9. **Tracker gate.** `bash ${CLAUDE_PLUGIN_ROOT}/bin/tracker.sh check --repo .` On a non-zero exit, show its message and stop. On success, report the user, access and tier, and what it means:
   - GitLab `premium`: detected, but Premium features are switched off for now; Compasso works the Free way on every tier.
   - GitLab `free`: a sprint is a milestone with a `type::epic` issue; features are `type::feature` issues; stories are child tasks; hard dependencies are written as a `**Depends on:** #<iid>` line in the story.
   - GitHub: a sprint is a milestone `S<n>` and an iteration `S<n>` in the Project, with a `type::epic` issue; features are `type::feature` sub-issues of the epic; stories are sub-issues of their feature; dependencies and blockers are GitHub's own "blocked by"; estimates and status live in the Project, and the state is also a `compasso::` label.

10. **Labels.** `bash ${CLAUDE_PLUGIN_ROOT}/bin/tracker.sh ensure-labels --repo .` and report what it created.

11. **Issue templates.** `bash ${CLAUDE_PLUGIN_ROOT}/bin/issue-templates.sh --repo .` installs the Epic, Feature, Story, Bug and Blocker formats into `.gitlab/issue_templates/` (GitHub: `.github/ISSUE_TEMPLATE/`, with each type's labels). Report any template it kept because the repo already has its own version.

    **GitHub: protect the default branch.** Commit and push `.github/workflows/compasso.yml` first, so its checks exist. Show the user what `tracker.sh protect` changes and ask before running it: a `compasso` ruleset on the default branch (changes only through pull requests, no force pushes or deletion, the workflow's gate jobs required, no approving review required because merging is the approval), CodeQL default setup and a rule that blocks high or critical CodeQL alerts where GitHub code scanning is available, auto-merge allowed (the tech lead's merge waits for the checks with it) and merged branches deleted. Then `bash ${CLAUDE_PLUGIN_ROOT}/bin/tracker.sh protect --repo .`. When it says CodeQL could not be set up yet (no code in a supported language), run it again once there is code.

12. **Ignore run files.** Add `.compasso/runs/` and `.compasso/worktrees/` to `.gitignore`: jobs keep their logs and the runner its state in the first, and the tech lead reverts a change that broke the default branch in a worktree in the second.

12b. **Team (tech lead).** Step 10 created a `dev::<name>` label for each of `team.developers`. A developer who joins later is added to `team.developers` (commit it), then `tracker.sh ensure-labels --repo .` again.

13. **Runner (tech lead and developer).** The agent works by itself: cron starts `bin/run.sh` on this machine, one job per run, each in a fresh session, and no model starts when there is nothing to do. Run `bash ${CLAUDE_PLUGIN_ROOT}/bin/cron.sh --repo .`: it prints this checkout's crontab line. Then give the person these steps, numbered, to do in their own terminal on this machine:
    1. `crontab -e`, paste the line, save.
    2. `crontab -l` shows it.
    3. After the first period, `tail .compasso/runs/runner/cron.log` shows a run (`nothing to do` is a run). On macOS, if it shows `Operation not permitted`, give `cron` Full Disk Access (System Settings > Privacy & Security), then wait for the next run.
    `/compasso:status` shows what the runner will do next. To stop the agent, remove the line (`crontab -e`).

    **Main stays green (tech lead).** Ask a project Maintainer to make the tracker refuse a merge whose pipeline failed. GitLab (Settings > Merge requests): "Pipelines must succeed". GitHub: the default branch's ruleset requiring the checks to pass (`tracker.sh protect` sets it).

    Hand back: a summary of the config, a reminder to commit `.compasso/project.yaml` and `.gitlab/` with `.gitlab-ci.yml` (GitHub: `.github/`), and the next step: `/compasso:plan` for the first plan, or, with features on the tracker, the runner (the tech lead splits the next feature into stories by itself).
