# One idea, one feature

**When:** the product exists, the team is running, and you have one new idea or one feature request, not a whole new product. For a new product built from one idea, see [Greenfield](greenfield.md).

**Bring:** the idea: who gets what, what is in scope, and how you will know it works.

## Steps

1. **File it as a Feature** from the Feature issue template: goal, scope and acceptance lines (Given/When/Then). It needs the labels `type::feature` and `compasso::new`; the GitLab template sets both, on GitHub add `compasso::new` yourself.
2. **Put it in a sprint** by giving it that sprint's milestone (`S<n>`). The tech lead plans features from the earliest sprint first, and a later sprint's when nothing earlier is left.
3. **The tech lead splits it** into stories when a developer runs short of ready work: vertical slices, each one merge request, with acceptance, Verify commands and test types. It then marks the feature `compasso::building`.
4. **The developers build it** like any other story. When all its stories are merged and the default branch is green, the tech lead asks the people in `people.ask` to test it on staging, then closes it.

## Good to know

- The tech lead decides how to split the feature. A question about scope, cost or a secret becomes a `needs::human` issue, and the feature waits for your answer.
- An idea bigger than half a sprint is really several features. Put it through `/compasso:backlog` instead.
- `/compasso:status` shows the tech lead's next job: `plan` with the feature's number once it is next.
