# Brownfield: adopting Compasso on an existing codebase

**When:** the product exists, has code, tests and probably a CI pipeline and a tracker full of issues.

**Bring:** the repository, access to its tracker, and the team's current test and build commands (Compasso detects them; you confirm).

## Steps

1. **`/compasso:setup`.**
   - It detects `test`, `lint`, `typecheck`, `build` and `e2e` from the repository's manifests and CI. You confirm or correct each.
   - It finds the coverage command and the report it writes. Coverage is measured on **changed lines only**, so an old codebase with low coverage is not punished; below 80% is a warning, never a block.
   - **Test frameworks:** it shows, per language, what you already use for unit, API, browser e2e, coverage and property-based tests. Compasso's default fills only an area where you have nothing, and is added by the first story that needs it. Your frameworks are never replaced.
   - **Test paths:** check `test_paths` matches your layout. In `production` the tester writes files there and the developer never changes them.
   - **Sensitive paths:** name the folders for authentication, payments, personal data and secrets (`risk.sensitive_paths`). Security plans abuse cases for stories that touch them.
   - **Stage:** a product people already use is usually `production`: a reviewer and a security agent read every merge request, and the pipeline runs e2e and coverage.
   - **Pipeline:** on GitLab, add the generated file to your existing `.gitlab-ci.yml` with one `include`. On GitHub, it writes `.github/workflows/compasso.yml` next to your workflows, and `tracker.sh protect` (after you agree) sets the branch rules.
   - It creates Compasso's labels and issue templates. Templates you already have are kept.
   - **Staging and people:** the command that deploys the default branch to staging, its address, and who answers the agents' questions (`people.ask`).

2. **Choose how to plan the first sprint.**
   - **The team already knows the goal:** `/compasso:plan`. See [Planning a known sprint](known-sprint.md).
   - **The work is scattered across tracker issues:** `/compasso:discover` with the issue numbers, then `/compasso:backlog` and `/compasso:roadmap`. The issues become features with rough hours and an MVP line, or a "next release" line.
   - **One feature to start with:** file it as a Feature. See [One idea, one feature](one-idea.md).

3. **Set up the team and start the runner.** See [A team of agents](team.md) and [Running the team](running.md).

## What changes for the team

- Stories are at most a day. Big existing issues are split by the planner; the originals stay as features.
- The tech lead agent reviews and merges every merge request a developer agent opens, once its pipeline is green. Merge requests written by people are not reviewed by Compasso, though the pipeline's scans run on them.
- The agents ask people through `needs::human` issues assigned to `people.ask`, with the evidence and numbered steps.
- Lessons land in `docs/learnings/`, and each role only sees the lessons for the paths it touches.

## Tips

- Start with one feature and one developer, to see the flow on your codebase before committing the team to it.
- If your CI already runs the tests, the Compasso pipeline duplicates them at first. Keep both until you trust it, then remove your copy.
- Stories that touch old code without tests get tests first, which adds tests where you most need them.
