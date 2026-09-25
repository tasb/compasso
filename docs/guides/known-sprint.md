# Planning a known sprint

**When:** the team already agreed what the next sprint delivers. This was Compasso's original starting point.

**Bring:** the sprint goal in one sentence, and the features it needs.

## Steps

1. **`/compasso:plan`.**
   - **With a roadmap**, it takes the roadmap's next sprint (goal and features) and asks you to confirm.
   - **Without one**, it asks for the goal and proposes the sprint number and dates.
   It also offers stories waiting in no sprint: follow-ups from reviews and hardening gaps.

2. **Features and questions.** For each feature: goal, scope, acceptance. Questions come in rounds in this conversation; each answer is recorded as a decision.

3. **Stories.** Each feature is split into stories of at most a day, with acceptance, Verify commands, test types (unit, e2e), paths touched, dependencies and an owner.
   - **Blockers** are created for outside work, each assigned to a person.
   - **plan-check** refuses stories over the limit, dependency cycles and a sprint over capacity. It shows the build order, the critical path and which stories can't run in parallel because they touch the same paths.

4. **Reviews.** Security reviews the plan and writes abuse cases into stories on sensitive paths. The tester refuses stories with nothing observable to test.

5. **Approval.** You approve the plan, and whether its Verify commands may run on this machine.

6. **Push and record.** The milestone, epic, features, stories and blockers go to the tracker. The plan and its decision record go into a `plan/S<n>` merge request; merge it to keep them in the repository.

Then [run the sprint](running-a-sprint.md).
