# Reviewing a merge request

**When:** you want Compasso's review and security review on any merge request (a pull request on GitHub), including ones written by people.

## Steps

1. **`/compasso:review <mr>`.** A reviewer checks correctness, regressions, simplicity, tests and docs. A security reviewer checks injection, access control, secrets and unsafe defaults. Both run on the diff.
2. **Findings are posted** on the merge request, each with its evidence: blocker, major or minor.
3. **Fixes only on request.** Ask for fixes and Compasso runs the story flow's loop: failing tests that pin the correct behaviour first, then the fix, then review again. Pushing to someone else's branch needs your yes.

## Good to know

- Only security can close a security finding. No approval mode merges while one is open.
- A change to a command in `.compasso/project.yaml` is always flagged: those commands run on developers' machines and in CI.
- Security scans in the pipeline (SAST and secret detection, or CodeQL on GitHub) also block high findings, whether or not anyone runs a review.
