# Greenfield: a new product from an idea

**When:** you have an idea, or a handful of them, and an empty repository.

**Bring:** the idea in a few sentences; who it is for; any deadline or constraint you already know.

## Steps

1. **Create the repository and the tracker project** (GitLab or GitHub), then run `/compasso:setup`.
   Setup notices there is no code yet. It leaves the test commands empty and skips the CI pipeline, because the walking skeleton will create them.
   *You decide:* the stage (`mvp` for a product nobody uses yet), sprint length, capacity, models, and whether this checkout is the tech lead of a team ([A team of agents](team.md)).

2. **`/compasso:discover`.** Tell it the idea. It asks up to 3 rounds of short questions: users, the problem in their words, what the MVP must prove, constraints.
   Security reviews what data and access the product will handle.
   *You get:* `.compasso/product/brief.md` and a merge request with it and its decision record.
   *You decide:* approve the brief.

3. **`/compasso:backlog`.** The planner turns the brief into features: user outcomes, each at most half a sprint, with rough hours and dependencies.
   Because the repository is empty, the first feature is **F-0 Walking skeleton**: the stack, unit and e2e test runners, CI, and one page or endpoint running end to end. Every MVP feature depends on it.
   Its tests use Compasso's defaults for that language: for example Vitest, Playwright and fast-check for TypeScript, or pytest, Playwright and Hypothesis for Python.
   *You decide:* the stack (proposed in one line with its reason), and where the **MVP line** goes: the smallest set of features that proves what the brief says.
   *You get:* `.compasso/backlog.yaml`, features on the tracker in no sprint (MVP ones labelled `mvp`), and a merge request.

4. **`/compasso:architect`.** The technical solution for the backlog: components, integrations, data, observability, environments, and each decision with what was not chosen. Security reviews it.
   *You decide:* answers on load, hosting, integrations and sign-in, and approval.

4b. **`/compasso:roadmap`.** Features are placed into sprints by dependency and capacity, MVP first. Work after the MVP line never delays it.
   *You decide:* one goal per sprint, and any moves (a demo date, someone's holiday).
   *You get:* `.compasso/roadmap.yaml` with the MVP sprint marked, and a merge request.

5. **`/compasso:plan`.** It takes the roadmap's first sprint, starting with F-0, and splits it into one-day stories.
   *You decide:* which developer gets what (or leave it to the runner), and approval of the plan.

6. **The team builds it.** Set up the developers and add each agent's crontab line ([A team of agents](team.md), [Running the team](running.md)). The developers build the stories; the tech lead reviews, merges, and splits each later feature into stories on its own.

7. **After F-0 is merged, run `/compasso:setup` again** in the tech lead's checkout. Now it finds the test, lint, build and e2e commands and generates the CI pipeline: every merge request runs verify and the security scans (and e2e and coverage in `production`), and, with `staging.deploy` set, every merge to the default branch deploys to staging.

8. **When the plan changes,** `/compasso:roadmap` re-places what is ahead with the velocity you reached.

## Tips

- Keep the MVP line honest: if the brief's "The MVP must prove" has three items, the MVP needs only the features that prove those three.
- Mark sensitive features (sign-in, payments, personal data) in the backlog. Security then writes their abuse cases into the stories when they are planned.
- Only the next feature is split into stories, when a developer needs work. Stories for sprint 4 written today would be stale by then.
