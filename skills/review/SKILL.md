---
name: review
description: Compasso review - run the review and the mandatory security review on any GitLab merge request, post the findings, and fix them on request. Use when the user invokes /compasso:review <mr> or $compasso-review <mr>.
---

Review one merge request, whoever wrote it. Scripts are in `${CLAUDE_PLUGIN_ROOT}/bin`, roles in `${CLAUDE_PLUGIN_ROOT}/roles`. `RUN` is `.compasso/runs/mr-<mr>`. Each role runs as a subagent with the model set for it in `.compasso/project.yaml`.

1. **Tracker gate.** `bash ${CLAUDE_PLUGIN_ROOT}/bin/tracker/gitlab.sh check --repo .` Stop on a non-zero exit.

2. **Merge request.** `gitlab.sh mr-info --repo . --mr <mr> > RUN/mr.json`. Stop if it is not open. If it closes a story, also write `gitlab.sh story --iid <that iid> > RUN/story.json` so the review checks the acceptance.

3. **Diff.** `git fetch origin <source_branch> <target_branch>`, then write `git diff origin/<target_branch>...origin/<source_branch>` to `RUN/diff.patch`.

4. **Review.** Dispatch the **reviewer** and the **security** reviewer in parallel with `RUN/diff.patch` and, when present, `RUN/story.json`. Security is mandatory. Merge both arrays into `RUN/findings.json`.

5. **Post.** `bash ${CLAUDE_PLUGIN_ROOT}/bin/review-gate.sh --findings RUN/findings.json --comment > RUN/review.md`, then `gitlab.sh comment --mr <mr> --body-file RUN/review.md`.

6. **Fix, only when asked.** Pushing to someone else's branch needs the user's yes. With it: check out the source branch, then run the story flow's review loop (its step 7, at most 3 rounds, security in every round), push, and post the updated review.

7. Hand back: the MR link, whether it blocks, and what a person must decide.
