---
name: plan
description: Compasso plan - turn a sprint goal into an epic, features and one-day user stories with dependencies, check them, get approval and push them to the tracker (GitLab or GitHub). Use when the user invokes /compasso:plan or $compasso-plan.
---

Plan one sprint top-down. You act as the planner: read `roles/planner.md` in the Compasso plugin root (`${CLAUDE_PLUGIN_ROOT}` on Claude Code) and follow it. Scripts are in `${CLAUDE_PLUGIN_ROOT}/bin`. `RUN` is `.compasso/runs/plan-S<n>`.

**Agents, strictly orchestrated.** Each role runs as the `compasso:<role>` subagent (on Codex, the `compasso-<role>` agent), given the model set for it in `.compasso/project.yaml` for this harness. Only this flow dispatches agents; none can start another. Before every dispatch, and before continuing an agent, claim it: `bash ${CLAUDE_PLUGIN_ROOT}/bin/budget.sh claim --repo . --run RUN --role <role>`. On exit 3 do not dispatch: stop where you are, change nothing more on the tracker, and hand back with its message. Never reset a budget yourself: `budget.sh reset` is a person's decision. An agent that stopped at its turn limit has not finished: treat its output as incomplete.

1. **Tracker gate.** `bash ${CLAUDE_PLUGIN_ROOT}/bin/tracker.sh check --repo .` On a non-zero exit, show its message and stop; exit 3 on the config means `/compasso:setup` has not run.

2. **Plan file.** If `.compasso/plan.yaml` exists, this re-plans that sprint: read it and change only what the user asks; never touch `gitlab` fields. Otherwise copy `${CLAUDE_PLUGIN_ROOT}/templates/plan.yaml` there.

3. **From the roadmap.** When `.compasso/roadmap.yaml` exists, `bash ${CLAUDE_PLUGIN_ROOT}/bin/roadmap.sh next --repo .` gives the next sprint: its number, goal and features as the backlog describes them. Use them for the epic and the features below, and confirm with the user rather than asking again: keep each feature's key and `gitlab` number from the backlog, so the push moves that same issue into the sprint, and copy its title, goal, scope, acceptance and decisions (not `size_h`, `mvp`, `depends_on` or `sources`, which belong to the backlog). A `sensitive` feature's stories get security's abuse cases (step 8). When the sprint is the roadmap's MVP sprint, say so in the epic's risks. Without a roadmap, continue with step 3a.

3a. **Epic.** Ask for the sprint goal in one sentence. Propose the sprint number (one more than the highest `S<n>` milestone in the project, or 1) and dates (next Monday to the Friday `sprint.weeks` later), and confirm the capacity from the config. Record risks the user names.

4. **Features.** Also offer the open stories that have no sprint yet (the backlog: hardening gaps, minor follow-ups), with their hours; the ones the user picks join the sprint under their feature.
   Ask which features the sprint delivers. For each: goal, scope (what to build), acceptance (Given/When/Then). Ask questions in rounds as `roles/planner.md` says; record each answer as a bullet in `decisions`. Ask in this conversation, never on the tracker.

5. **Stories.** Read the lessons for planning (`bash ${CLAUDE_PLUGIN_ROOT}/bin/learnings.sh recall --repo . --role planner`) and the code, then split each feature into stories that follow `roles/planner.md`. For every story set `title`, `as`/`want`/`so_that`, `acceptance`, `verify`, `tests`, `touches`, `depends_on`, `owner` and `estimate_h`. Ask the user who owns stories you cannot assign (`agent`, `human` or `either`). Add a `coverage` override only when the user asks for one.

   **Blockers.** For anything outside the plan a story waits for (credentials, another team, a decision), add a blocker: a title, the tracker username of the project member who will resolve it (ask; it is required), and the steps to resolve it, one clear action each. List it in the story's `blocked_by`.

6. **Check.** `bash ${CLAUDE_PLUGIN_ROOT}/bin/plan-check.sh --repo .` Fix every error and re-run until it passes. Mention its notes (stories above the target) and the overlapping paths.

7. **Show the plan** in the approved Plan format from `${CLAUDE_PLUGIN_ROOT}/templates/comments/plan.md`: one row per story with hours, owner and dependencies, plus the total and the critical path from plan-check.

8. **Security review (mandatory).** Dispatch **security** with the path `.compasso/plan.yaml`. Add its result to the Plan's Security line. For each finding of severity blocker or major, change the plan (usually acceptance for the abuse case) and re-run steps 6 and 8. For every story on a sensitive path (`risk.sensitive_paths`), security writes its abuse cases ("Given another customer's token, When …, Then 404") into the story's acceptance and you set `security_reviewed: true`; plan-check refuses the plan until then.

9. **Testability.** Dispatch the **tester** with `.compasso/plan.yaml`: for each story, can a test fail before it is built, and does every acceptance line describe something observable? It lists the stories that fail this (enabling work with nothing of its own, "works as before", vague outcomes). Fix them (usually by merging a story into the one that uses it) and re-run step 6.

10. **Approval.** With `approvals.plan: human`, ask the user to approve the plan as shown and wait for an explicit yes. With `auto`, continue only when security reported no findings; otherwise ask the user.
    **Verify commands.** `bash ${CLAUDE_PLUGIN_ROOT}/bin/trust.sh check --repo . --plan` lists the stories' Verify commands not yet approved on this machine. Show them and ask whether they may run when the stories are built; this question is always asked, even with `approvals.plan: auto`. After an explicit yes, `bash ${CLAUDE_PLUGIN_ROOT}/bin/trust.sh approve --repo . --plan`. Without it the plan is still pushed, and each story asks again when it is built.

11. **Push.** `bash ${CLAUDE_PLUGIN_ROOT}/bin/tracker.sh push-plan --repo .` It creates or updates the milestone, the features, the stories as child tasks and the epic, and writes their ids into `plan.yaml`. If it fails, show the message; re-running resumes where it stopped.

12. **Record.** Write `RUN/record.json` for `bin/record.sh` (its header describes the fields; every list is required, empty when there is nothing): **findings** - security's and the tester's findings on the plan and what changed for each, plan-check's notes (overlapping paths, stories above the target); **decisions** - every answer with who gave it and when, owners chosen, the approval, and assumptions (`"assumed": true`); **takeaways** - what planning taught about the product or the code; **constraints** - capacity used of available, sensitive paths, outside dependencies, dates; **missing** - questions still open and blockers (`"status": "open"` or `"blocker"`). Then `bash ${CLAUDE_PLUGIN_ROOT}/bin/record.sh write --data RUN/record.json --out "$(bash ${CLAUDE_PLUGIN_ROOT}/bin/record.sh path --repo . --kind plan --key plan)"`.

13. **Plan merge request.** `bash ${CLAUDE_PLUGIN_ROOT}/bin/plan-pr.sh --repo . --title "Plan S<n>: <goal>"` commits `.compasso/plan.yaml` and the sprint's records on `plan/S<n>` and opens (or, on a re-plan, updates) its merge request. It leaves the current branch alone.

14. Hand back: the epic and feature links, the plan merge request to merge, and the next command (`/compasso:story <iid>` or `/compasso:sprint <epic>`).
