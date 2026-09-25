---
name: setup
description: Compasso setup - connect a repository to its GitLab or GitHub tracker and record sprint, limits, commands, approvals and models in .compasso/project.yaml. Use when the user invokes /compasso:setup or $compasso-setup, or when another Compasso command reports that setup is missing.
---

Connect this repository to Compasso. Every other Compasso command refuses to run until this succeeds. Scripts live in `${CLAUDE_PLUGIN_ROOT}/bin` (Codex: the `bin` folder next to this skill's plugin root).

Ask one topic at a time, show the default, and accept "default" as an answer. Never invent values the user did not confirm.

0. **Upgrade.** If `.compasso/project.yaml` exists, first run `bash ${CLAUDE_PLUGIN_ROOT}/bin/config.sh upgrade --repo .` so keys added by a newer Compasso are present.

1. **Tracker and login.** Ask which tracker: GitLab or GitHub (propose the one `git remote -v` points at). Never ask for a token in chat; the `!` prefix below runs the command in this session. Continue when the user confirms.
   - GitLab: `glab auth status --hostname <host>` (default `gitlab.com`); if not logged in, ask them to run `! glab auth login --hostname <host> --web`.
   - GitHub: `gh auth status --hostname <host>` (default `github.com`); if not logged in, ask them to run `! gh auth login --hostname <host> --web`. A GitHub Project needs the `project` scope: if `gh auth status` does not list it, ask them to run `! gh auth refresh --hostname <host> -s project`.

2. **Config file.** If `.compasso/project.yaml` exists, read it and treat every question below as "keep or change". Otherwise ask for the project (GitLab `namespace/project`, GitHub `owner/repo`); propose the one from `git remote -v`. Then run:
   `bash ${CLAUDE_PLUGIN_ROOT}/bin/config.sh init --repo . --project <project>`
   GitLab: for a self-managed server, set `tracker.host`, and ask for the tier (`free` or `premium`) because detection only works on gitlab.com.
   GitHub: set `tracker.provider: github` and `tracker.host` (default `github.com`). Then ask, one at a time, and never assume:
   - **Project.** Which GitHub Project holds sprints, estimates and status (its number from the Project's URL), or `0` for none. With none, estimates and sprint iterations are not recorded and the report shows no hours.
   - **Fields.** The Project's number field for estimates in hours, its iteration field for sprints, and its single-select status field (`tracker.github.fields`; defaults `Estimate (h)`, `Iteration`, `Status`). Offer to create any that are missing (`gh project field-create`); the iteration field is created in the Project's web settings when `gh` cannot.
   - **Status options.** Which status option means each Compasso state (`tracker.github.status`: `new`, `building`, `in-review`, `done`; defaults `Todo`, `In progress`, `In review`, `Done`). A state with no option only changes the label.

3. **Sprint.** Length in weeks (default 2), hours per working day (default 8), and team capacity in hours per sprint (default: weeks × 5 × hours per day, for one person; ask how many people, humans and agents, share the sprint).

4. **Limits.** Story hard limit (default 8h, and never above one working day) and target (default 4h). Explain that a feature may take at most half a sprint, derived from the sprint length.

5. **Commands.** In a repository with no product code yet (`bash ${CLAUDE_PLUGIN_ROOT}/bin/start.sh --repo . --json` says `greenfield: true`), leave every command empty, skip the pipeline, and say so: the walking skeleton (the backlog's F-0) sets up the stack and its test runners, and setup runs again once it is merged. Otherwise, detect the repo's own `test`, `lint`, `typecheck`, `build` and `e2e` commands from its manifests (for example `package.json` scripts, `Makefile`, `pyproject.toml`, `go.mod`, CI files). Present what you found and let the user confirm or correct each; leave a command empty when it does not apply. If the repo has a UI or public API and no e2e command, say so and suggest a framework (Playwright for web, the project's own test runner for APIs, bats for CLIs), without installing anything.

   **Coverage.** Find the repo's coverage command and the Cobertura or LCOV file it writes, and the product-code paths (for example `src/**`). Default threshold: 80% of changed lines; below it is a warning, never a block. Without a command, every merge request shows coverage as "not measured" - say so.

   **Test frameworks.** `bash ${CLAUDE_PLUGIN_ROOT}/bin/test-stack.sh detect --repo .` shows, per language and area (unit, API, browser e2e, coverage, property-based), what the project already uses, and Compasso's default where it has nothing. Defaults never replace what exists: they fill only empty areas, and are added by the first story that needs them. Let the user change any default, then `bash ${CLAUDE_PLUGIN_ROOT}/bin/test-stack.sh write --repo .` (edit `testing` in the config for their changes). When there is no coverage command and coverage shows a default, propose its `command` and `report` from `test-stack.sh detect --json`.

   **Tests.** Show `test_paths` (what counts as a test file; the builder may never change these) and adjust it to the repo's layout.

   **Pipeline.** Ask for the CI image that has the repo's toolchain (`ci.image`, for example the image the repo's CI already uses), then run `bash ${CLAUDE_PLUGIN_ROOT}/bin/ci.sh --repo .`.
   - GitLab: add `include: [{ local: .gitlab/compasso.gitlab-ci.yml }]` to `.gitlab-ci.yml` (create it if missing). The file runs the verify gate, e2e, changed-line coverage as a warning, and GitLab SAST and Secret Detection on every merge request.
   - GitHub: it writes `.github/workflows/compasso.yml`: the verify gate, e2e and changed-line coverage as a warning on every pull request. Security scans are GitHub's own (CodeQL and secret scanning) when the repository has them - public, or private with Advanced Security - and otherwise Compasso's scan gate (Gitleaks and Semgrep). Say which one it chose.

6. **Approvals and risk.** Plan approval: `human` (default) or `auto`. Merge approval: `human` (default), `agent`, or `risk` (low-risk changes merge without a person; the rest wait for one, and a daily digest lists what merged). Ask for the sensitive paths (`risk.sensitive_paths`: authentication, payments, personal data, secrets handling) and the line limit (`risk.max_changed_lines`, default 200); a change to them always needs a person, their stories get abuse cases from security at planning, and a quick mutation check in review. State plainly that security review runs on every plan and merge request regardless, and that no approval mode passes an open security finding.

7. **Harnesses and models.** Ask which harnesses the team uses: `claude`, `codex`, or both. Show the model table for each chosen harness from the config and ask whether to change any role. The `security` and `approver` roles have a floor: no fast-tier model and no low effort. Remove the `models.<harness>` block of a harness that is not used. When the team uses Codex: after validating (step 8), run `bash ${CLAUDE_PLUGIN_ROOT}/bin/install-codex.sh --repo .` to write `.codex/agents/compasso-*.toml` with each role's model (tell the user to run `install-codex.sh` once without `--repo` on each machine first, and to re-run the `--repo` form after changing models).

8. Write every answer with `yq -i` edits to `.compasso/project.yaml`, then validate:
   `bash ${CLAUDE_PLUGIN_ROOT}/bin/config.sh validate --repo .`
   Fix and re-ask until it passes.

9. **Tracker gate.** `bash ${CLAUDE_PLUGIN_ROOT}/bin/tracker.sh check --repo .` On a non-zero exit, show its message and stop. On success, report the user, access and tier, and what it means:
   - GitLab `premium`: detected, but Premium features are switched off for now; Compasso works the Free way on every tier.
   - GitLab `free`: a sprint is a milestone with a `type::epic` issue; features are `type::feature` issues; stories are child tasks; hard dependencies are written as a `**Depends on:** #<iid>` line in the story.
   - GitHub: a sprint is a milestone `S<n>` and an iteration `S<n>` in the Project, with a `type::epic` issue; features are `type::feature` sub-issues of the epic; stories are sub-issues of their feature; dependencies and blockers are GitHub's own "blocked by"; estimates and status live in the Project, and the state is also a `compasso::` label.

10. **Labels.** `bash ${CLAUDE_PLUGIN_ROOT}/bin/tracker.sh ensure-labels --repo .` and report what it created.

11. **Issue templates.** `bash ${CLAUDE_PLUGIN_ROOT}/bin/issue-templates.sh --repo .` installs the Epic, Feature, Story, Bug and Blocker formats into `.gitlab/issue_templates/` (GitHub: `.github/ISSUE_TEMPLATE/`, with each type's labels). Report any template it kept because the repo already has its own version.

    **GitHub: protect the default branch.** Commit and push `.github/workflows/compasso.yml` first, so its checks exist. Show the user what `tracker.sh protect` changes and ask before running it: a `compasso` ruleset on the default branch (changes only through pull requests, no force pushes or deletion, the workflow's gate jobs required, no approving review required because merging is the approval), CodeQL default setup and a rule that blocks high or critical CodeQL alerts where GitHub code scanning is available, auto-merge allowed (used only when `approvals.merge` is `agent` or `risk`) and merged branches deleted. Then `bash ${CLAUDE_PLUGIN_ROOT}/bin/tracker.sh protect --repo .`. When it says CodeQL could not be set up yet (no code in a supported language), run it again once there is code.

12. **Ignore run files.** Add `.compasso/runs/` to `.gitignore`: story runs keep logs and findings there.

13. Hand back: a summary of the config, a reminder to commit `.compasso/project.yaml` and `.gitlab/` with `.gitlab-ci.yml` (GitHub: `.github/`), and the next command (`/compasso:plan` or `/compasso:feature <iid>`).
