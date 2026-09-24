---
name: story
description: Compasso story flow - build one GitLab story test-first, verify it, run the review and mandatory security review with an automatic fix loop, and open its merge request. Use when the user invokes /compasso:story <iid> or $compasso-story <iid>.
---

Build one story end to end. Scripts are in `${CLAUDE_PLUGIN_ROOT}/bin`, roles in `${CLAUDE_PLUGIN_ROOT}/roles`. `RUN` is `.compasso/runs/<iid>` in the repo. Every role runs as a subagent that reads its role file, with the model set for that role and this harness in `.compasso/project.yaml`. Pass paths, not recaps. Give each role its lessons: `bash ${CLAUDE_PLUGIN_ROOT}/bin/learnings.sh recall --repo . --role <role> --story RUN/story.json > RUN/learnings-<role>.md`, passed with its inputs when not empty. Record every run for the report: after each subagent, `bash ${CLAUDE_PLUGIN_ROOT}/bin/story-metrics.sh agent --run RUN --role <role> --model <model> [--tokens N] [--ms N]` with the tokens and duration the harness reported (leave them out when it reported none); and `story-metrics.sh event --run RUN --type round|verify-fail|violation|replan` when those happen.

1. **Tracker gate.** `bash ${CLAUDE_PLUGIN_ROOT}/bin/tracker/gitlab.sh check --repo .` Stop on a non-zero exit.

2. **Story.** `bash ${CLAUDE_PLUGIN_ROOT}/bin/tracker/gitlab.sh story --repo . --iid <iid> > RUN/story.json`. Stop and say why when:
   - it is not an open task;
   - `open_dependencies` is not empty: name each one, and for a blocker say who it is assigned to;
   - `story.acceptance` is empty, or `story.verify` is empty for a story: it does not follow the Story format. A bug reported by a tester has no Verify yet: the tester's first job (step 4) is a failing test that reproduces it, and that test's command becomes `story.verify` in `RUN/story.json`;
   - it has the `owner::human` label, unless the user confirms an agent should build it.

3. **Branch.** The working tree must be clean. `git fetch`, then create `story/<iid>-<short-slug>` from `origin/<default branch>` (the base). `gitlab.sh set-state --iid <iid> --state building`.

4. **Tests first.** Dispatch the **tester** with `RUN/story.json`. Run the repo's test command and confirm the new tests fail. If some pass, send them back to the tester once. If, after that, none of the new tests fails, stop and hand back: the story has no behaviour of its own to build (usually enabling work that belongs in the story that uses it), and it needs re-planning, not code. Tests that pass only because they guard existing behaviour are fine next to at least one failing test. Commit the tests on their own ("Add failing tests for #<iid>"), note that commit as `TESTS`, then `bash ${CLAUDE_PLUGIN_ROOT}/bin/test-hashes.sh record --repo . --run RUN`.

5. **Build.** Dispatch the **builder** with `RUN/story.json`. Then:
   - `test-hashes.sh verify --repo . --run RUN`. A violation fails the round: restore the tests with `git checkout TESTS -- <each file it names>` (delete files it added), and send the builder back once; a second violation stops the flow.
   - `bash ${CLAUDE_PLUGIN_ROOT}/bin/verify.sh --repo . --run RUN --story RUN/story.json`. On FAIL, send the builder the failing output; after 3 failed attempts stop and hand back.

6. **Coverage (warning).** `bash ${CLAUDE_PLUGIN_ROOT}/bin/coverage.sh --repo . --base <base> --run RUN --min <coverage_min from story.json>`. Exit 3 is a warning: report it and continue.

7. **Review loop, at most 3 rounds.**
   - Write the diff (`git diff <base>` plus untracked files) to `RUN/diff.patch`.
   - Dispatch the **reviewer** and the **security** reviewer in parallel, each with `RUN/story.json`, `RUN/diff.patch`, `RUN/verify.json`, `RUN/coverage.json` and the current `RUN/findings.json` (start with `[]`). Security is mandatory in every round and is never skipped.
   - Merge both JSON arrays into `RUN/findings.json`, keeping earlier findings and their updated status.
   - `bash ${CLAUDE_PLUGIN_ROOT}/bin/review-gate.sh --findings RUN/findings.json --for review`. Exit 0 ends the loop.
   - Otherwise fix, tests first: when a finding means behaviour must change, dispatch the **tester** to add failing tests that pin the correct behaviour, commit them on their own ("Add failing tests for finding <id>"), note that commit as the new `TESTS` and re-record the hashes. Then dispatch the **builder** with the open blocker and major findings and every open security finding, repeat step 5's checks, and start the next round on the new diff: the reviewer re-reads only the changed hunks; security re-checks each of its findings and alone may set `verified_by: security`.
   - Still blocked after round 3: stop, set nothing, and hand back the open findings (`review-gate.sh --comment`). Do not open a merge request.

8. **Ship.** Dispatch the **shipper** with `RUN/story.json` and `RUN/findings.json`: it commits, writes `RUN/changes.md`, and files each open minor finding as a follow-up under the story's feature (`gitlab.sh followup`). If this run showed something went wrong (a blocker or major finding, a test-immutability violation, verify failing 3 times, the story needing re-planning), tell the shipper which, so it captures a lesson (at most 2), checked with `learnings.sh check` and committed in this merge request. Then `bash ${CLAUDE_PLUGIN_ROOT}/bin/story-metrics.sh write --run RUN --repo .` and commit `.compasso/metrics/<iid>.json` with the story, so the sprint report has its numbers. Push the branch.

9. **Merge request.** `bash ${CLAUDE_PLUGIN_ROOT}/bin/mr-body.sh --story RUN/story.json --run RUN > RUN/mr.md`, then `gitlab.sh open-mr --iid <iid> --branch <branch> --body-file RUN/mr.md` and `gitlab.sh set-state --iid <iid> --state in-review`.

10. **Approval.**
    - `approvals.merge: human` (default): stop here. A person reviews and merges.
    - `approvals.merge: agent`: dispatch the **approver** with the MR, `RUN/story.json` and `RUN/findings.json`. If it approves, `gitlab.sh merge --mr <mr> --body-file RUN/findings.json` (it refuses on any open security finding). If not, post its reasons with `gitlab.sh comment` and stop.

11. Hand back: the MR link, the verify and coverage results, the findings fixed and followed up, and anything a person must do.
