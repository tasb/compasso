# Running a sprint

**When:** a sprint is planned and pushed.

## Day to day

- **`/compasso:status`** shows, without changing anything:
  - what can be built now, what is building or in review;
  - what waits on which story, and what is blocked by which blocker (and who owns it);
  - each feature's progress;
  - every local run, with the step it stopped at.
- **`/compasso:sprint`** builds everything that can run now:
  - It asks once for any Verify commands not yet approved.
  - It runs the ready stories in parallel, in separate worktrees, when their paths don't overlap.
  - A story whose only dependency is waiting for review is stacked on that story's branch instead of waiting.
- **`/compasso:story <iid>`** builds one story. The steps are:
  1. failing tests first;
  2. the builder makes them pass (it may never edit a test);
  3. verify;
  4. changed-line coverage, as a warning;
  5. review and security review, fixing tests-first, for at most 3 rounds;
  6. follow-up stories for minor findings, metrics and the decision record;
  7. the merge request.
- **Merging.** A person merges by default. With `approvals.merge: risk`, low-risk changes merge on their own and a daily digest lists them. A change to a sensitive path, or one over the line limit, always waits for a person, and no mode merges with an open security finding.
- **Blockers** are assigned to people with step-by-step instructions. Closing one frees the stories it held.
- **Human-owned stories** stay for a person. `/compasso:status` lists them with their assignee.

## Finishing features

When a feature's stories are all merged, the tester writes e2e tests for its acceptance. Failures become bugs under the feature. When they pass, the feature is done.

## Closing the sprint

When every feature is done, `/compasso:sprint`:
1. runs a regression pass and a security pass over everything the sprint changed;
2. writes the **test guide**, an HTML page for business testers: what's new, how to try it, what to expect. Their results come back as bugs;
3. builds the **sprint report**: delivery, flow and waiting, quality, agent effort and cost;
4. offers `/compasso:roadmap` to re-place what's ahead with the velocity you reached, then `/compasso:plan` for the next sprint. After the MVP sprint, it also offers [hardening](after-the-mvp.md).

`/compasso:report` builds the report at any time.
