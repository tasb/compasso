---
name: plan
description: Compasso plan - turn a sprint goal into an epic, features and one-day user stories with dependencies, check them, get approval and push them to GitLab. Use when the user invokes /compasso:plan or $compasso-plan.
---

Plan one sprint top-down. You act as the planner: read `roles/planner.md` in the Compasso plugin root (`${CLAUDE_PLUGIN_ROOT}` on Claude Code) and follow it. Scripts are in `${CLAUDE_PLUGIN_ROOT}/bin`.

1. **Tracker gate.** `bash ${CLAUDE_PLUGIN_ROOT}/bin/tracker/gitlab.sh check --repo .` On a non-zero exit, show its message and stop; exit 3 on the config means `/compasso:setup` has not run.

2. **Plan file.** If `.compasso/plan.yaml` exists, this re-plans that sprint: read it and change only what the user asks; never touch `gitlab` fields. Otherwise copy `${CLAUDE_PLUGIN_ROOT}/templates/plan.yaml` there.

3. **Epic.** Ask for the sprint goal in one sentence. Propose the sprint name (`YYYY-S<ISO week of the start>`) and dates (next Monday to the Friday `sprint.weeks` later), and confirm the capacity from the config. Record risks the user names.

4. **Features.** Ask which features the sprint delivers. For each: goal, scope (what to build), acceptance (Given/When/Then). Ask questions in rounds as `roles/planner.md` says; record each answer as a bullet in `decisions`.

5. **Stories.** Read the code, then split each feature into stories that follow `roles/planner.md`. For every story set `title`, `as`/`want`/`so_that`, `acceptance`, `verify`, `tests`, `touches`, `depends_on`, `owner` and `estimate_h`. Ask the user who owns stories you cannot assign (`agent`, `human` or `either`). Add a `coverage` override only when the user asks for one.

6. **Check.** `bash ${CLAUDE_PLUGIN_ROOT}/bin/plan-check.sh --repo .` Fix every error and re-run until it passes. Mention its notes (stories above the target) and the overlapping paths.

7. **Show the plan** in the approved Plan format from `${CLAUDE_PLUGIN_ROOT}/templates/comments/plan.md`: one row per story with hours, owner and dependencies, plus the total and the critical path from plan-check.

8. **Security review (mandatory).** Dispatch a subagent that follows `roles/security.md`, with the model set for the `security` role in `.compasso/project.yaml` for this harness, and give it the path `.compasso/plan.yaml`. Add its result to the Plan's Security line. For each blocker or major finding, change the plan (usually acceptance for the abuse case) and re-run steps 6 and 8.

9. **Approval.** With `approvals.plan: human`, ask the user to approve the plan as shown and wait for an explicit yes. With `auto`, continue only when security reported no findings; otherwise ask the user.

10. **Push.** `bash ${CLAUDE_PLUGIN_ROOT}/bin/tracker/gitlab.sh push-plan --repo .` It creates or updates the milestone, the features, the stories as child tasks and the epic, and writes their ids into `plan.yaml`. If it fails, show the message; re-running resumes where it stopped.

11. Hand back: the epic and feature links, a reminder to commit `.compasso/plan.yaml`, and the next command (`/compasso:story <iid>` or `/compasso:sprint <epic>`).
