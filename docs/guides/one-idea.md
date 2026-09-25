# One idea, one feature

**When:** the product exists and you have one new idea or one feature request, not a whole new product. For a new product built from one idea, see [Greenfield](greenfield.md).

**Bring:** the idea in a sentence, or the number of the tracker issue that describes it.

## Steps

1. **`/compasso:feature "<the idea>"`** or **`/compasso:feature <issue number>`.**
   - The planner reads the code and the lessons for planning, then asks what it needs in this conversation: at most 5 short questions a round, at most 3 rounds. Anything still open becomes a written assumption.
   - It splits the feature into one-day stories with dependencies, and adds blockers for anything outside the team: a credential, another team's API, a decision. Each blocker is assigned to a person, with step-by-step instructions.
   - Security reviews the plan, and the tester checks each story can be tested.
   *You decide:* the answers, the owners (agent, human or either), the Verify commands the stories may run, and approval of the plan.

2. **It joins the current sprint.** plan-check checks the sprint's capacity with the feature added; if it doesn't fit, you choose what moves out.

3. **The tracker gets the record:** the questions and answers and the plan are posted on the feature, and its stories are created.

4. **It builds** straight away through the sprint flow, for this feature only. When all its stories are merged, the tester writes e2e tests for the feature's acceptance.

## Tips

- Without a sprint in `.compasso/plan.yaml`, run `/compasso:plan` first: a feature always lands in a sprint.
- An idea bigger than half a sprint is really several features. Put it through `/compasso:backlog` instead.
