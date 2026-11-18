# A bug or a small change

**When:** the team is running, and something is broken, or a change fits in a day.

## A bug

1. **File it on the tracker** from the Bug template (`type::bug`): steps, expected, actual, evidence, and a Verify command that fails now and passes once it is fixed.
2. **Set its severity** with a label: `severity::blocker`, `severity::major` or `severity::minor` (no label counts as minor).
3. **The runner takes it.** The tech lead assigns it to a developer, and developers build bugs before stories, the most severe first. You can also give it a developer yourself with its `dev::<name>` label.
4. **It merges** like any story: the developer writes a test that fails the way the bug does, fixes it, and opens the merge request; the tech lead reviews it once its pipeline is green.

## A small change

1. **Write it as a story** on the tracker from the Story template: who wants it, acceptance, Verify, tests (`unit`, `e2e`), paths touched. Make it a child of a feature (GitLab: a child task; GitHub: a sub-issue) and put it in a sprint's milestone.
2. **The runner takes it**, like a bug, after the bugs.

## Good to know

- A story or bug without acceptance or Verify cannot be built well: write both before it is assigned.
- With `trust.verify_approval: true`, a Verify command written on the tracker waits for a person's approval on the developer's machine (`bin/trust.sh approve`). By default it runs without asking.
- A change that turns out to need more than a day is split, not stretched.
- `/compasso:status` shows who has it and what the runner will do next.
