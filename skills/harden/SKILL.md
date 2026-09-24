---
name: harden
description: Compasso harden - optional, after the MVP is delivered. Check a delivered feature's or epic's tests with agent-written mutants; turn the gaps into stories for a later sprint. Never part of the story or sprint flow. Use when the user invokes /compasso:harden <feature|epic iid> or $compasso-harden.
---

Harden one delivered feature (or every feature of an epic). This never slows delivery: it runs only when a person asks. Scripts are in `${CLAUDE_PLUGIN_ROOT}/bin`, roles in `${CLAUDE_PLUGIN_ROOT}/roles`; each role runs as a subagent with the model set for it in `.compasso/project.yaml`. `RUN` is `.compasso/runs/harden-<iid>`.

1. **Tracker gate.** `bash ${CLAUDE_PLUGIN_ROOT}/bin/tracker/gitlab.sh check --repo .` Stop on a non-zero exit.

2. **Scope.** For an epic, repeat steps 2 to 6 for each of its features. The feature's stories are its child tasks (`gitlab.sh sprint-sync --parent <feature>` lists them). For each closed one, `gitlab.sh merge-commit --iid <story>`; skip stories that were not merged. `git fetch`, check out the default branch in a clean worktree, then `bash ${CLAUDE_PLUGIN_ROOT}/bin/mutate.sh scope --repo . --commits "<the merge commits>" --out RUN/scope.patch`. Stop if it has no changed lines.

3. **Mutants.** Dispatch the **mutator** with `RUN/scope.patch` and the feature's acceptance (`gitlab.sh story --iid <feature>`). It writes `RUN/mutants/<id>.json`, 2 to 4 per behaviour.

4. **Run them.** `bash ${CLAUDE_PLUGIN_ROOT}/bin/mutate.sh run --repo . --mutants RUN/mutants --test "<the repo's test command, and e2e when the feature has it>" --out RUN/results.json`. Exit 1 means the tree could not be restored: stop and tell the user.

5. **Judge the survivors.** Dispatch the **tester** with `RUN/results.json` and each survivor's patch: for each, is it a real gap (a behaviour a user or caller relies on that no test checks) or a change with no observable effect? It writes `RUN/verdicts.json`: `[{"id", "verdict": "gap" | "equivalent", "reason"}]`.

6. **Record.**
   - Group the gaps by behaviour. For each group, write a story in the Story format ("Strengthen tests for <behaviour>": acceptance says a test must fail for each of its mutants, Verify is the test command, `Tests: unit`, owner agent, 1–2h) and file it for a later sprint: `gitlab.sh followup --parent <feature> --title "Strengthen tests for <behaviour>" --body-file <story> --labels owner::agent --milestone none`. Put its iid in each of the group's verdicts as `story`.
   - `bash ${CLAUDE_PLUGIN_ROOT}/bin/mutate.sh report --results RUN/results.json --verdicts RUN/verdicts.json --feature <feature> > RUN/report.md` and `gitlab.sh comment --iid <feature> --body-file RUN/report.md`.

7. **Hand back:** mutants tried, caught, gaps with their new stories, and changes with no observable effect. The next `/compasso:plan` offers the new stories.
