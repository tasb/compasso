# Greenfield: a new product from an idea

**When:** you have an idea, or a handful of them, and an empty repository.

**Bring:** the idea in a few sentences; who it is for; any deadline or constraint you already know.

## Steps

1. **Create the repository and the tracker project** (GitLab or GitHub), then run `/compasso:setup`.
   Setup notices there is no code yet. It leaves the test commands empty and skips the CI pipeline, because the walking skeleton will create them.
   *You decide:* sprint length, capacity, approval modes, models.

2. **`/compasso:discover`.** Tell it the idea. It asks up to 3 rounds of short questions: users, the problem in their words, what the MVP must prove, constraints.
   Security reviews what data and access the product will handle.
   *You get:* `.compasso/product/brief.md` and a merge request with it and its decision record.
   *You decide:* approve the brief.

3. **`/compasso:backlog`.** The planner turns the brief into features: user outcomes, each at most half a sprint, with rough hours and dependencies.
   Because the repository is empty, the first feature is **F-0 Walking skeleton**: the stack, unit and e2e test runners, CI, and one page or endpoint running end to end. Every MVP feature depends on it.
   Its tests use Compasso's defaults for that language: for example Vitest, Playwright and fast-check for TypeScript, or pytest, Playwright and Hypothesis for Python.
   *You decide:* the stack (proposed in one line with its reason), and where the **MVP line** goes: the smallest set of features that proves what the brief says.
   *You get:* `.compasso/backlog.yaml`, features on the tracker in no sprint (MVP ones labelled `mvp`), and a merge request.

4. **`/compasso:roadmap`.** Features are placed into sprints by dependency and capacity, MVP first. Work after the MVP line never delays it.
   *You decide:* one goal per sprint, and any moves (a demo date, someone's holiday).
   *You get:* `.compasso/roadmap.yaml` with the MVP sprint marked, and a merge request.

5. **`/compasso:plan`.** It takes the roadmap's first sprint, starting with F-0, and splits it into one-day stories.
   *You decide:* owners where the planner can't assign them, the Verify commands each story may run, and approval of the plan.

6. **`/compasso:sprint`** builds it. See [Running a sprint](running-a-sprint.md).

7. **After F-0 is merged, run `/compasso:setup` again.** Now it finds the test, lint, build and e2e commands and generates the CI pipeline. From here on every merge request runs verify, e2e, coverage and the security scans.

8. **At each sprint close,** `/compasso:roadmap` re-places what is ahead with the velocity you actually reached. `/compasso:plan` then plans the next sprint.

## Tips

- Keep the MVP line honest: if the brief's "The MVP must prove" has three items, the MVP needs only the features that prove those three.
- Mark sensitive features (sign-in, payments, personal data) in the backlog. Security then writes their abuse cases into the stories when they are planned.
- Only the next sprint is split into stories. Don't ask for stories for sprint 4; they would be stale by then.
