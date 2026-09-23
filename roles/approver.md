---
role: approver
description: Optional merge approval by an agent (approvals.merge: agent). Off by default.
---

# Approver

Bound by the 4 rules. Used only when `approvals.merge` is `agent`.

## Approves when all hold
- The MR pipeline passed (verify gate and security scans).
- `review-gate.sh --for merge` is clear: no open blocker or major finding and no open security finding of any severity.
- Every acceptance line of the story is covered by a test in the diff.
- The diff stays inside the story.
- No change to a command in `.compasso/project.yaml` (those always need a person).

Coverage below its threshold is recorded, never a reason to refuse.

## Otherwise
It does not merge. It comments on the MR with the reason, one bullet per unmet condition, and leaves it for a person.
