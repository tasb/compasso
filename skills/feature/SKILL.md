---
name: feature
description: Compasso feature flow - take a feature from a GitLab issue or an idea, ask its questions in this conversation, plan it into one-day stories, get approval, record the Q&A and plan on the tracker, then build it. Use when the user invokes /compasso:feature <iid|"idea"> or $compasso-feature.
---

Plan and build one feature. The conversation happens here; GitLab gets the record. Scripts are in `${CLAUDE_PLUGIN_ROOT}/bin`, roles in `${CLAUDE_PLUGIN_ROOT}/roles`; you act as the planner (`roles/planner.md`). `RUN` is `.compasso/runs/feature-<key>`.

1. **Tracker gate.** `bash ${CLAUDE_PLUGIN_ROOT}/bin/tracker/gitlab.sh check --repo .` Stop on a non-zero exit.

2. **Sprint.** The feature joins the current sprint in `.compasso/plan.yaml`. Without one, stop and point to `/compasso:plan`.

3. **Feature.**
   - `<iid>`: `gitlab.sh story --repo . --iid <iid>` and read `story.goal`, `story.scope`, `story.acceptance`, `story.decisions`. Add it to `plan.yaml` as a new feature (next free `F-n` key) with `gitlab: <iid>`; if it is already there, continue with that entry.
   - `"<idea>"`: add a new feature to `plan.yaml` with the idea as its goal and `gitlab: null`.

4. **Questions, in this conversation.** Read the lessons for planning first (`bash ${CLAUDE_PLUGIN_ROOT}/bin/learnings.sh recall --repo . --role planner`), then read the code, then ask what you need: at most 5 questions per round, each answerable in one line, with options where possible. At most 3 rounds; after that, or when the user says to proceed, list what is still open as assumptions and continue. Never ask on the tracker.
   - After each round write `RUN/qa-<round>.json` (`{round, user, date, items: [{question, answer}]}`, the user being the GitLab username from `gitlab.sh check`) and add each answer to the feature's `decisions` as `<answer> (answered by @<user> in the agent, <date>)`; assumptions as `Assumed: <assumption>`.
   - Complete the feature's `scope` and `acceptance` from the answers.

5. **Stories.** Split the feature into stories and blockers as `roles/planner.md` says, in `plan.yaml`. Then `bash ${CLAUDE_PLUGIN_ROOT}/bin/plan-check.sh --repo .` until it passes; it also checks the sprint's capacity with the feature added. If capacity is exceeded, say by how much and let the user choose what moves out.

6. **Security review of the plan (mandatory).** Dispatch the security role (`roles/security.md`, model from the config) with `.compasso/plan.yaml` and the feature's key. Write its result to `RUN/security.md` ("no findings", or one bullet per finding). Fix blocker and major findings in the plan and repeat steps 5 and 6.

7. **Approval.** Show the plan: `bash ${CLAUDE_PLUGIN_ROOT}/bin/comment.sh plan --repo . --feature <key> --approver <user> --security-file RUN/security.md` (the Approved line is only a preview). With `approvals.plan: human`, wait for an explicit yes. With `auto`, continue only when security found nothing; otherwise ask.

8. **Record on the tracker.**
   - `gitlab.sh push-plan --repo .` creates or updates the feature, its stories and blockers.
   - For each question round: `comment.sh qa --file RUN/qa-<round>.json > RUN/qa-<round>.md` and `gitlab.sh comment --repo . --iid <feature iid> --body-file RUN/qa-<round>.md`.
   - `comment.sh plan ... > RUN/plan.md` and post it the same way.
   - `gitlab.sh set-state --repo . --iid <feature iid> --state building`.
   - Remind the user to commit `.compasso/plan.yaml`.

9. **Build.** Run the sprint flow for this feature: `${CLAUDE_PLUGIN_ROOT}/skills/sprint/SKILL.md` with the feature's iid, which builds its stories in dependency order and verifies the feature when they are all merged.
