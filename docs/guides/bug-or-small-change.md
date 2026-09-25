# A bug or a small change

**When:** something is broken, or a change fits in a day.

## A bug

1. **File it on the tracker** from the Bug template (`type::bug`): steps, expected, actual, evidence. Testers' failed scenarios arrive this way automatically.
2. **`/compasso:story <bug number>`.**
   - The tester first writes a test that fails the way the bug does. That test becomes the bug's Verify command; it is the one command approved without asking, because it came from this run.
   - The builder makes it pass without touching the test.
   - Verify, review and security review run as for any story, then the merge request opens.
3. **You merge**, or the approver does if you set `approvals.merge` to `agent` or `risk`.

## A small change

1. **Write it as a story** on the tracker (Story template): who wants it, acceptance, Verify, tests, paths touched. Give it a feature as its parent and put it in the current sprint's milestone. Or ask `/compasso:feature` to plan it; it will produce a single story.
2. **`/compasso:story <number>`.** Before running anything it shows the story's Verify commands and asks whether they may run.

## Tips

- A story written by hand must follow the Story format. Without acceptance and Verify, the story flow stops and says why.
- A change that turns out to need more than a day is split, not stretched.
- `/compasso:status <number>` shows where a story's run stopped, and the step to resume from.
