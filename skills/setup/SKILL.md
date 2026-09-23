---
name: setup
description: Compasso setup - connect a repository to its GitLab tracker and record sprint, limits, commands, approvals and models in .compasso/project.yaml. Use when the user invokes /compasso:setup or $compasso-setup, or when another Compasso command reports that setup is missing.
---

Connect this repository to Compasso. Every other Compasso command refuses to run until this succeeds. Scripts live in `${CLAUDE_PLUGIN_ROOT}/bin` (Codex: the `bin` folder next to this skill's plugin root).

Ask one topic at a time, show the default, and accept "default" as an answer. Never invent values the user did not confirm.

1. **GitLab login.** Run `glab auth status --hostname <host>` (default host `gitlab.com`). If it is not logged in, stop and tell the user to run `! glab auth login --hostname <host> --web` (the `!` prefix runs it in this session; never ask for a token in chat), then continue when they confirm.

2. **Config file.** If `.compasso/project.yaml` exists, read it and treat every question below as "keep or change". Otherwise ask for the GitLab project (`namespace/project`); propose the one from `git remote -v` when it points at GitLab. Then run:
   `bash ${CLAUDE_PLUGIN_ROOT}/bin/config.sh init --repo . --project <namespace/project>`
   For a self-managed GitLab, set `tracker.host`, and ask for the tier (`free` or `premium`) because detection only works on gitlab.com.

3. **Sprint.** Length in weeks (default 2), hours per working day (default 8), and team capacity in hours per sprint (default: weeks × 5 × hours per day, for one person; ask how many people, humans and agents, share the sprint).

4. **Limits.** Story hard limit (default 8h, and never above one working day) and target (default 4h). Explain that a feature may take at most half a sprint, derived from the sprint length.

5. **Commands.** Detect the repo's own `test`, `lint`, `typecheck`, `build`, `coverage` and `e2e` commands from its manifests (for example `package.json` scripts, `Makefile`, `pyproject.toml`, `go.mod`, CI files). Present what you found and let the user confirm or correct each; leave a command empty when it does not apply. If the repo has a UI or public API and no e2e command, say so and suggest a framework (Playwright for web, the project's own test runner for APIs, bats for CLIs), without installing anything.

6. **Approvals.** Plan approval: `human` (default) or `auto`. Merge approval: `human` (default) or `agent`. State plainly that security review runs on every plan and merge request regardless, and that no approval mode passes an open security finding.

7. **Harnesses and models.** Ask which harnesses the team uses: `claude`, `codex`, or both. Show the model table for each chosen harness from the config and ask whether to change any role. The `security` and `approver` roles have a floor: no fast-tier model and no low effort. Remove the `models.<harness>` block of a harness that is not used.

8. Write every answer with `yq -i` edits to `.compasso/project.yaml`, then validate:
   `bash ${CLAUDE_PLUGIN_ROOT}/bin/config.sh validate --repo .`
   Fix and re-ask until it passes.

9. **Tracker gate.** `bash ${CLAUDE_PLUGIN_ROOT}/bin/tracker/gitlab.sh check --repo .` On a non-zero exit, show its message and stop. On success, report the user, access level and tier, and what the tier means:
   - `premium`: native epics, iterations and "blocks" links.
   - `free`: a sprint is a milestone with a `type::epic` issue; features are `type::feature` issues; stories are child tasks; hard dependencies are written as a `**Depends on:** #<iid>` line in the story.

10. **Labels.** `bash ${CLAUDE_PLUGIN_ROOT}/bin/tracker/gitlab.sh ensure-labels --repo .` and report what it created.

11. **Issue templates.** `bash ${CLAUDE_PLUGIN_ROOT}/bin/issue-templates.sh --repo .` installs the Epic, Feature, Story and Bug formats into `.gitlab/issue_templates/`. Report any template it kept because the repo already has its own version.

12. Hand back: a summary of the config, a reminder to commit `.compasso/project.yaml` and `.gitlab/issue_templates/`, and the next command (`/compasso:plan` or `/compasso:feature <iid>`).
