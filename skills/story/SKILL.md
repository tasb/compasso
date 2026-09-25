---
name: story
description: Compasso story flow - build one story test-first, verify it, run the review and mandatory security review with an automatic fix loop, and open its merge request. Use when the user invokes /compasso:story <iid> or $compasso-story <iid>.
---

Build one story end to end. Scripts are in `${CLAUDE_PLUGIN_ROOT}/bin`, roles in `${CLAUDE_PLUGIN_ROOT}/roles`. `RUN` is `.compasso/runs/<iid>` in the repo. Every role runs as a subagent that reads its role file, with the model set for that role and this harness in `.compasso/project.yaml`. Pass paths, not recaps. Give each role its lessons: `bash ${CLAUDE_PLUGIN_ROOT}/bin/learnings.sh recall --repo . --role <role> --story RUN/story.json > RUN/learnings-<role>.md`, passed with its inputs when not empty. Record every run for the report: after each subagent, `bash ${CLAUDE_PLUGIN_ROOT}/bin/story-metrics.sh agent --run RUN --role <role> --model <model> [--tokens N] [--ms N]` with the tokens and duration the harness reported (leave them out when it reported none); and `story-metrics.sh event --run RUN --type round|verify-fail|violation|replan` when those happen.

1. **Tracker gate.** `bash ${CLAUDE_PLUGIN_ROOT}/bin/tracker.sh check --repo .` Stop on a non-zero exit.

2. **Story.** `bash ${CLAUDE_PLUGIN_ROOT}/bin/tracker.sh story --repo . --iid <iid> > RUN/story.json`. Stop and say why when:
   - it is not an open task;
   - `open_dependencies` is not empty: name each one, and for a blocker say who it is assigned to. One exception, **stacking**: when the only open item is a story whose merge request is already open (sprint-sync lists this story with `stack_on`), build on top of it instead of waiting;
   - `story.acceptance` is empty, or `story.verify` is empty for a story: it does not follow the Story format. A bug reported by a tester has no Verify yet: the tester's first job (step 4) is a failing test that reproduces it, and that test's command becomes `story.verify` in `RUN/story.json`;
   - it has the `owner::human` label, unless the user confirms an agent should build it.

3. **Branch.** The working tree must be clean. `git fetch`, then create `story/<iid>-<short-slug>` from `origin/<default branch>` (the base). When stacking, the base is instead the branch of the story it stacks on (`tracker.sh open-mr-branch --iid <that story>`), and step 9 opens the merge request with `--target` that branch; when that merge request is merged and its branch deleted, GitLab and GitHub retarget this one to the default branch. `tracker.sh set-state --iid <iid> --state building`.

4. **Tests first.** Dispatch the **tester** with `RUN/story.json`. Run the repo's test command and confirm the new tests fail. If some pass, send them back to the tester once. If, after that, none of the new tests fails, stop and hand back: the story has no behaviour of its own to build (usually enabling work that belongs in the story that uses it), and it needs re-planning, not code. Tests that pass only because they guard existing behaviour are fine next to at least one failing test. Commit the tests on their own ("Add failing tests for #<iid>"), note that commit as `TESTS`, then `bash ${CLAUDE_PLUGIN_ROOT}/bin/test-hashes.sh record --repo . --run RUN`.

5. **Build.** Dispatch the **builder** with `RUN/story.json`. Then:
   - `test-hashes.sh verify --repo . --run RUN`. A violation fails the round: restore the tests with `git checkout TESTS -- <each file it names>` (delete files it added), and send the builder back once; a second violation stops the flow.
   - `bash ${CLAUDE_PLUGIN_ROOT}/bin/verify.sh --repo . --run RUN --story RUN/story.json`. On FAIL, send the builder the failing output; after 3 failed attempts stop and hand back.
   - When verify passes, commit the builder's work with the message it wrote in `RUN/commit-msg.txt` (what changed and why), so every round ends on a clean tree.

6. **Coverage (warning).** `bash ${CLAUDE_PLUGIN_ROOT}/bin/coverage.sh --repo . --base <base> --run RUN --min <coverage_min from story.json>`. Exit 3 is a warning: report it and continue.

7. **Review loop, at most 3 rounds.**
   - Write the diff (`git diff <base>` plus untracked files) to `RUN/diff.patch`.
   - Dispatch the **reviewer** and the **security** reviewer in parallel, each with `RUN/story.json`, `RUN/diff.patch`, `RUN/verify.json`, `RUN/coverage.json` and the current `RUN/findings.json` (start with `[]`). Security is mandatory in every round and is never skipped.
   - Merge both JSON arrays into `RUN/findings.json`, keeping earlier findings and their updated status.
   - **Mutation check on sensitive lines** (first round only, when the story touches `risk.sensitive_paths`): `bash ${CLAUDE_PLUGIN_ROOT}/bin/mutate.sh scope --repo . --base <base> --sensitive --out RUN/sensitive.patch`; if it has changed lines, dispatch the **mutator** for 2 or 3 mutants on them, run `mutate.sh run --repo . --mutants RUN/mutants --test "<the story's Verify commands>" --out RUN/mutants.json`, and have the **tester** judge the survivors. Each real gap joins `RUN/findings.json` as `{"by": "reviewer", "severity": "major", "status": "open", "summary": "Tests miss: <behaviour> - <what the mutant changed>"}`, fixed tests-first like any finding.
   - `bash ${CLAUDE_PLUGIN_ROOT}/bin/review-gate.sh --findings RUN/findings.json --for review`. Exit 0 ends the loop.
   - **Keep the same agents.** From round 2, continue the tester, builder, reviewer and security agents of round 1 with the new findings (on Claude Code, SendMessage to each), instead of starting new ones: they keep what they read, and a round costs about half. Start a new one only when continuing is not possible.
   - Otherwise fix, tests first: when a finding means behaviour must change, dispatch the **tester** to add failing tests that pin the correct behaviour, commit them on their own ("Add failing tests for finding <id>"), note that commit as the new `TESTS` and re-record the hashes. Then dispatch the **builder** with the open blocker and major findings and every open security finding, repeat step 5's checks, and start the next round on the new diff: the reviewer re-reads only the changed hunks; security re-checks each of its findings and alone may set `verified_by: security`.
   - Still blocked after round 3: stop, set nothing, and hand back the open findings (`review-gate.sh --comment`). Do not open a merge request.

8. **Ship (no agent).** If this run showed something went wrong (a blocker or major finding, a test-immutability violation, verify failing 3 times, the story needing re-planning), tell the **reviewer** which, in its last round, so it captures a lesson (at most 2, checked with `learnings.sh check`). Then `bash ${CLAUDE_PLUGIN_ROOT}/bin/ship.sh --repo . --run RUN`: it files each open minor finding as a backlog story, writes the story's metrics, and commits them and any lessons. The builder has already committed the code and written `RUN/changes.md`. Push the branch.

9. **Merge request.** `bash ${CLAUDE_PLUGIN_ROOT}/bin/risk.sh --repo . --run RUN --base <base>` (low or high risk, with the reasons; always, so the merge request says whether a person must approve), then `bash ${CLAUDE_PLUGIN_ROOT}/bin/mr-body.sh --story RUN/story.json --run RUN > RUN/mr.md`, then `tracker.sh open-mr --iid <iid> --branch <branch> --body-file RUN/mr.md` and `tracker.sh set-state --iid <iid> --state in-review`.

10. **Approval.**
    - `approvals.merge: human` (default): stop here. A person reviews and merges.
    - `approvals.merge: risk`: a high-risk change stops here for a person, the reasons in its merge request. A low-risk one goes to the approver as below, and `tracker.sh merge` also gets `--risk RUN/risk.json` (it refuses anything but low).
    - `approvals.merge: agent`: dispatch the **approver** with the MR, `RUN/story.json` and `RUN/findings.json`. If it approves, `tracker.sh merge --mr <mr> --body-file RUN/findings.json` (it refuses on any open security finding). If not, post its reasons with `tracker.sh comment` and stop.

11. Hand back: the MR link, the verify and coverage results, the findings fixed and followed up, and anything a person must do.
