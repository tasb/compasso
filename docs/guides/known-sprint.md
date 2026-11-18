# Planning a known sprint

**When:** the team already agreed what the first sprint delivers. `/compasso:plan` is how the first plan reaches the tracker; after it, the tech lead agent splits each later feature into stories on its own.

**Bring:** the sprint goal in one sentence, and the features it needs.

## Steps

1. **`/compasso:plan`.**
   - **With a roadmap**, it takes the roadmap's next sprint (goal and features) and asks you to confirm.
   - **Without one**, it asks for the goal and proposes the sprint number and dates.
   It also offers open stories that are in no sprint yet. The after-MVP list is never offered: in `harden` and `production` the tech lead turns it into stories.

2. **Features and questions.** For each feature: goal, scope, acceptance. Questions come in rounds in this conversation; each answer is recorded as a decision.

3. **Stories.** Each feature is split into stories of at most a day, with acceptance, Verify commands, test types (`unit`, `e2e`), paths touched, dependencies and the developer who builds it (`dev: <name>`). Leave the developer out and the runner assigns the story to the developer with the fewest ready ones.
   - **Blockers** are created for outside work, each assigned to a person, with steps.
   - **plan-check** refuses stories over the limit, dependency cycles and a sprint over capacity. It shows the build order, the critical path and which stories touch the same paths.

4. **Reviews.** Security reviews the plan and writes abuse cases into stories on sensitive paths. The tester refuses stories with nothing observable to test.

5. **Approval.** You approve the plan (`approvals.plan: human`, the default). With `trust.verify_approval: true` you also approve its Verify commands for this machine.

6. **Push and record.** The milestone, epic, features, stories and blockers go to the tracker. The plan and its decision record go into a `plan/S<n>` merge request; merge it to keep them in the repository.

Then the team builds it: [Running the team](running.md).
