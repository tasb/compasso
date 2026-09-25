---
name: harden
description: Compasso harden - optional, after the MVP is delivered. Check a delivered feature (or every feature of an epic) with the code set (mutation testing, property-based tests, flaky tests, test smells; no infrastructure) and, when asked, the live set (API fuzzing, ZAP security scan, performance, accessibility; needs a running test environment and Docker). Gaps become stories for a later sprint. Never part of the story or sprint flow. Use when the user invokes /compasso:harden <feature|epic iid> [--set code|live|all] [--checks a,b] or $compasso-harden.
---

Harden one delivered feature, or every feature of an epic. It runs only when a person asks and never slows delivery. Scripts are in `${CLAUDE_PLUGIN_ROOT}/bin`, roles in `${CLAUDE_PLUGIN_ROOT}/roles`. `RUN` is `.compasso/runs/harden-<iid>`; every check writes its result to `RUN/results/<check>.json` in the common format that `bin/harden-report.sh` describes.

**Agents, strictly orchestrated.** Each role runs as the `compasso:<role>` subagent (on Codex, the `compasso-<role>` agent), given the model set for it in `.compasso/project.yaml` for this harness. Only this flow dispatches agents; none can start another. Before every dispatch, and before continuing an agent, claim it: `bash ${CLAUDE_PLUGIN_ROOT}/bin/budget.sh claim --repo . --run RUN --role <role>`. On exit 3 do not dispatch: stop where you are, change nothing more on the tracker, and hand back with its message. Never reset a budget yourself: `budget.sh reset` is a person's decision. An agent that stopped at its turn limit has not finished: treat its output as incomplete.

**Which checks.** `--set code` (the default): mutation, property, flaky, smells. `--set live`: fuzz, zap, perf, a11y. `--set all`: both. `--checks` picks individual ones. A check that cannot run (for example no OpenAPI schema, or a feature with no UI for accessibility) writes `{"check", "title", "ran": false, "reason"}` instead of being skipped silently.

1. **Tracker gate.** `bash ${CLAUDE_PLUGIN_ROOT}/bin/tracker.sh check --repo .` Stop on a non-zero exit. `git fetch` and work in a clean worktree of the default branch.

2. **Scope.** The feature's stories are its child tasks (`tracker.sh sprint-sync --parent <feature>`). For each closed one, `tracker.sh merge-commit --iid <story>`; skip stories that were not merged. Then `bash ${CLAUDE_PLUGIN_ROOT}/bin/mutate.sh scope --repo . --commits "<the merge commits>" --out RUN/scope.patch`. Stop if it has no changed lines. The feature's acceptance comes from `tracker.sh story --iid <feature>`.

## Code set (no infrastructure)

3. **Mutation testing.** Dispatch the **mutator** with `RUN/scope.patch` and the acceptance; it writes `RUN/mutants/<id>.json`. Run `bash ${CLAUDE_PLUGIN_ROOT}/bin/mutate.sh run --repo . --mutants RUN/mutants --test "<test command, and e2e when the feature has it>" --out RUN/mutants.json` (exit 1: the tree could not be restored; stop and tell the user). Dispatch the **tester** to judge each survivor into `RUN/verdicts.json`. File the gaps (step 8), then `mutate.sh result --results RUN/mutants.json --verdicts RUN/verdicts.json --out RUN/results/mutation.json`.

4. **Property-based tests.** On a branch `harden/<feature>-properties`, dispatch the **tester** to write property-based tests with the framework `testing.<language>.property` names (when it is `none`, table-driven tests over many generated cases) from the acceptance, for the code in `RUN/scope.patch`. Run them. Rules that hold stay as tests and ship like a story (review and mandatory security review, shipper, merge request "Add property-based tests for #<feature>"). Each rule that breaks is a bug (step 8). Result: counts "rules", "hold", "broken"; one gap per broken rule.

5. **Flaky tests.** `bash ${CLAUDE_PLUGIN_ROOT}/bin/flaky.sh --repo . --test "<test command>" --runs <harden.flaky_runs> --out RUN/flaky`. Exit 3: dispatch the **tester** to read the failing logs and name the flaky tests; each becomes a story "Make <test> stable". Exit 4: every run failed, which is a broken build, not flakiness: stop and say so. Result: counts "runs", "passed", "flaky tests"; one gap per flaky test.

6. **Test smells.** Dispatch the **tester** to review the tests that the feature's stories added or changed. Result: counts "tests read", "smells"; one gap per smell ("<test file>: <smell>").

## Live set (running environment and Docker)

7. **Before anything,** read `harden.environment.url` from the config, show it to the user and ask them to confirm it is a test environment, never production. Then, for each live check chosen:
   `bash ${CLAUDE_PLUGIN_ROOT}/bin/live.sh run <fuzz|zap|perf|a11y> --repo . --confirm-url <the confirmed URL> --out RUN/live` and copy `RUN/live/<check>.result.json` to `RUN/results/<check>.json`. API fuzzing sends only reading requests unless the environment is marked disposable. Accessibility runs only for features with pages (`harden.environment.pages`); performance only with endpoints (`harden.environment.endpoints`).

## Record

8. **Gaps become stories for a later sprint.** For each gap, or group of gaps about one behaviour, write a story in the Story format (what to strengthen or fix, acceptance a test can check, Verify, `Tests: unit` or `unit, e2e`, owner agent, 1–4h) and file it: `tracker.sh followup --parent <feature> --title "<title>" --body-file <story> --labels owner::agent --milestone none` (bugs from broken rules or failing live checks: `--labels type::bug,severity::<level>,owner::agent`). Put each story's iid on its gap as `story`.

9. **Report.** `bash ${CLAUDE_PLUGIN_ROOT}/bin/harden-report.sh --results RUN/results --set <set> --feature <feature> > RUN/report.md`, then `tracker.sh comment --iid <feature> --body-file RUN/report.md`.

10. **Hand back:** per check what ran, what it found, and the new stories. The next `/compasso:plan` offers them.
