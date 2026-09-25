---
name: roadmap
description: Compasso roadmap - place the backlog's features into sprints by dependency and capacity, MVP first, with one goal per sprint and the MVP sprint marked; refine what is ahead at each sprint close using measured velocity. Use when the user invokes /compasso:roadmap or $compasso-roadmap, and at sprint close.
---

Place the backlog into sprints. Only the next sprint is split into stories (by `/compasso:plan`); later sprints stay as features and are refined at each sprint close. Scripts are in `${CLAUDE_PLUGIN_ROOT}/bin`. `RUN` is `.compasso/runs/roadmap`.

1. **Tracker gate.** `bash ${CLAUDE_PLUGIN_ROOT}/bin/tracker.sh check --repo .` Stop on a non-zero exit.

2. **Capacity.** The default is `sprint.capacity_hours`. When sprints have closed, measure velocity instead: `tracker.sh sprint-done --repo . --milestone S<n>` for the last three closed sprints (null means none), and propose their average. The user chooses.

3. **Propose.** `bash ${CLAUDE_PLUGIN_ROOT}/bin/roadmap.sh propose --repo . --capacity <hours>` places every feature not already in a sprint under way, MVP first, each after what it depends on; features after the MVP line go only into later sprints. Sprints under way are kept as they are, and a goal is kept when its sprint keeps its features. Show the result.

4. **Adjust with the user.** Move features only when they ask (a date, a demo, a team's availability). Then `roadmap.sh propose ... --write`, edit `.compasso/roadmap.yaml` for any move they asked for, and write one goal per sprint: one sentence saying what a user can do at its end.

5. **Check.** `bash ${CLAUDE_PLUGIN_ROOT}/bin/roadmap.sh check --repo .` until it passes (capacity, dependency order, the MVP line, a goal for every sprint).

6. **Approval.** Show each sprint (number, goal, features and hours) with the MVP sprint marked, and wait for an explicit yes.

7. **Record and merge request.** Write `RUN/record.json` (findings: what the placement showed, such as a long dependency chain or a sprint far under capacity; decisions: the capacity and why, moves the user asked for; takeaways; constraints: dates, availability; missing: open points), then `bash ${CLAUDE_PLUGIN_ROOT}/bin/record.sh write --data RUN/record.json --out .compasso/records/product/roadmap.md` and `bash ${CLAUDE_PLUGIN_ROOT}/bin/plan-pr.sh --repo . --title "Roadmap: MVP in S<m>" --branch product/roadmap --include .compasso/roadmap.yaml --include .compasso/records/product`.

8. Hand back: the sprints in one line each, when the MVP lands, and the next command, `/compasso:plan`, which plans the roadmap's next sprint. After the MVP sprint closes, also offer `/compasso:harden`.
