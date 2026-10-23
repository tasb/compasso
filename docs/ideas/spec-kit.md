# Ideas from GitHub Spec Kit

Status: parked (2026-10-22). Nothing here is decided for a release yet, except where a section says "Agreed".

Source: [github/spec-kit](https://github.com/github/spec-kit) 1.2.3 (commit `27d14e2`, 2026-10-22), read in full: command templates, docs, extensions, workflow engine, and the agentic workflows on its own repository.

## Spec Kit in short

Spec-driven development: the spec is the source of truth and the code serves it. A Python CLI (`specify`) installs prompt templates into 43 integrations (41 agents, plus `none` and `generic`). Core flow, each step writing Markdown into `specs/NNN-feature/`:

- `constitution`: the project's principles, versioned by semver.
- `specify`: user stories P1/P2/P3, each independently testable (Given/When/Then); requirements `FR-###`, success criteria `SC-###`; at most 3 `[NEEDS CLARIFICATION]`; a 16-item self-check of the spec's quality.
- `clarify`: up to 5 questions, one at a time, each with a recommended answer and "why it matters"; answers written into the spec; a coverage table at the end.
- `plan`: constitution check, `research.md` (decision, rationale, alternatives), `data-model.md`, `contracts/`, `quickstart.md`.
- `tasks`: phases (setup, foundation, one per user story, polish); `[P]` parallel and `[US1]` markers.
- `checklist`: "unit tests for English", checks the requirements, not the code; a person ticks the items.
- `analyze`: read-only consistency check across spec, plan and tasks (duplication, ambiguity, coverage gaps, terminology drift, constitution conflicts).
- `implement`: refuses while a checklist has unticked items, then runs the tasks.
- `converge`: compares code with the spec ("completion claims are not evidence"); gaps `missing`, `partial`, `contradicts`, `unrequested` become tasks; repeat implement and converge until converged.

Around it: opt-in `git` (branch per feature, local commits) and `github` (one issue per task, one way) extensions, `assess` (idea go / needs-clarification / kill) and `bug` (assess, fix, test) extensions, a YAML workflow engine with approve/reject gates that pause and resume, presets that override templates by priority, and 183 community extensions.

Its gates are prompt text, not programs; it does not run tests, review code, merge, read CI, or manage sprints or roles. Compasso does all of these.

## Ideas for Compasso

Ranked by value for the cost, against Compasso's principles (gates are scripts that stop, the tracker holds the work).

1. **Converge at feature close.** When a feature's last story merges, compare the merged code with the feature's acceptance and scope. Gaps: `missing`, `partial`, `contradicts`, `unrequested`. A closed story is not proof.
2. **Traceability by ID, checked by a script.** IDs on brief outcomes and feature acceptance lines, cited by stories; `plan-check` / `backlog-check` fail on an outcome with no feature or an acceptance line with no story.
3. **Project principles.** A versioned `.compasso/principles.md` written by the team; planner, reviewer and security receive it; a violation is a major finding. Different from learnings (from mistakes, scoped by path).
4. **Better questions.** In `feature` and `discover`: each question with a recommended answer and "why it matters"; at the end a coverage table by category (scope, data, UX, non-functional, integrations, edge cases) with resolved, deferred, open.
5. **Requirements quality check** before plan approval: vague words without numbers ("fast", "secure") become findings. The tester checks testability today, not ambiguity.
6. **Per-project overrides** of roles and templates: `.compasso/overrides/` that prepends or appends to a role without forking the plugin.
7. **Evidence against the idea in `discover`:** a "why this could fail" section and an explicit go / kill verdict in the brief.

Not worth taking: the 43 integrations, the workflow engine, catalogs and bundles, community MCP extensions. More surface, no gain for the sprint flow.

## Living spec of the product (agreed in principle)

Decided with the user on 2026-10-22: Compasso keeps a living spec of the product in the repository. It absorbs ideas 1 and 2.

- **Truth.** The spec is the source of truth for the product's behaviour; the tracker stays the source of truth for work. Principle 1 (docs/SPEC.md) is reworded to split the two.
- **Direction: spec-first plus flow-back.** Planning a feature or sprint writes the requirements as `planned`, in the plan's merge request. Each story's merge request flips what it delivered to `live`. If the build had to change a behaviour, the builder edits the requirement and the reviewer checks it against the code.
- **Layout.** One file per capability: `.compasso/spec/<capability>.yaml`, checked by a `spec-check` script (IDs unique, Given/When/Then, status), rendered by a script to `<capability>.md` in the project's language, with an index.
- **IDs.** A prefix per capability (`BIL-1`, `BIL-2`...), never reused. Statuses: `planned`, `live`, `retiring`, `retired`.
- **Lifecycle.** A story lists the IDs it delivers; `ship.sh` flips them to `live` in that story's merge request.
- **Link to stories.** Every acceptance line of a story cites an ID (`[BIL-3]`). `plan-check` fails on a planned requirement with no story or a story citing an unknown ID.
- **Converge.** Run by the reviewer role (its own budget run) when a feature's last story merges: the sprint flow when solo, the tech lead's flow poll in a team. `missing` and `partial` become stories in the sprint; `unrequested` and `contradicts` go to a person (the tech lead in a team), who decides whether the code is wrong (a story) or the spec is (a spec change). The feature closes only when converged.
- **Used by** `/compasso:present` and the sprint test guide. Not yet by bugs or the roles' context.
- **Brownfield.** The spec grows with the work: only the capabilities a feature touches are specified, from the code, when it is planned. No upfront pass.
- **Upgrade.** Stories already on the tracker build as today. Everything planned after the upgrade must cite IDs. Planned as 3.2.0, with its release notes and the updating agent's task.

- **Stages.** It applies in both `mvp` and `production` (decided 2026-10-22).
- **Idea 4** (better questions) ships in the same release (decided 2026-10-22).

### Next (paused by the user on 2026-10-22)

SPEC section 35, tests first, implementation, full suite and hand mutations, a person's yes before committing.
