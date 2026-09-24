---
name: sprint
description: Compasso sprint flow - build everything that can be built in the current sprint (or one feature), in dependency order and in parallel where paths do not overlap, verify each finished feature with e2e tests, and close the sprint with a regression run, a security pass and the test guide. Resumable. Use when the user invokes /compasso:sprint [feature iid] or $compasso-sprint.
---

Move the sprint forward as far as it can go, then say exactly what waits and on whom. Re-running continues where it stopped. Scripts are in `${CLAUDE_PLUGIN_ROOT}/bin`, roles in `${CLAUDE_PLUGIN_ROOT}/roles`. `RUN` is `.compasso/runs/sprint-S<n>`.

1. **Tracker gate.** `bash ${CLAUDE_PLUGIN_ROOT}/bin/tracker/gitlab.sh check --repo .` Stop on a non-zero exit. `git fetch` and update the default branch.

2. **Where the sprint stands.** `gitlab.sh sprint-sync --repo . > RUN/sync.json`. With a feature iid, add `--parent <iid>`: only that feature's stories and bugs count.

3. **Build the next batch.** For each item in `next_batch` run the story flow (`${CLAUDE_PLUGIN_ROOT}/skills/story/SKILL.md`). Items in one batch never touch overlapping paths, so they can run at the same time: give each its own worktree (`git worktree add ../<repo>-<iid> origin/<default branch>`) and run the story flows in parallel, one orchestrator per story; remove each worktree when its flow ends.
   - With `approvals.merge: human`, stories that depend on an item of this batch wait for its merge request to be merged: stop after the batch and report.
   - With `approvals.merge: agent`, repeat steps 2 and 3 while `next_batch` is not empty.

4. **Verify finished features.** For each feature with `ready_to_verify`:
   - `gitlab.sh set-state --iid <feature> --state verifying`.
   - On a branch `feature/<iid>-e2e` from the default branch, dispatch the **tester** to write end-to-end tests for every acceptance line of the feature (the feature's description has them), using the repo's e2e framework.
   - Run the whole suite and e2e (`verify.sh --repo . --run RUN/feature-<iid>`). For every failing test, file a Bug under the feature: `gitlab.sh followup --parent <feature> --title <what fails> --body-file <Bug format> --labels type::bug,severity::<blocker|major|minor>,owner::agent`, with the failing test as its Verify. Mark those tests skipped with a reference to the bug, so the passing ones can ship.
   - Ship the tests like a story: review and mandatory security review loop, shipper, merge request "Add end-to-end tests for #<feature>".
   - When the feature is `ready_to_finish` (all its stories and bugs closed) and its e2e merge request is merged: write the feature's section of the test guide (`${CLAUDE_PLUGIN_ROOT}/templates/test-guide.md`), post it as a comment on the feature, and `gitlab.sh set-state --iid <feature> --state done`. A person closes the feature.

5. **Close the sprint** when `sprint_done` is true:
   - Regression: `verify.sh` on the default branch with the e2e command.
   - Security pass over everything the sprint changed: the **security** role on `git diff <last commit of the default branch before the sprint's start date>..origin/<default branch>` (`git rev-list -1 --before=<start> origin/<default branch>`). Every finding becomes a Bug on the epic's feature it touches (or on the epic), severity as found.
   - The test guide: the **shipper** assembles `docs/releases/S<n>-test-guide.md` from the features' sections, following the template, and opens a merge request for it; post the guide's link on the epic.

6. **Report**, every run: what was built and its merge requests; what waits for a person to approve and merge (with links); human-owned stories and their assignees; open blockers and who owns them; stories waiting on other stories; features verified; bugs filed. End with the command to run next.
