# Brownfield: adopting Compasso on an existing codebase

**When:** the product exists, has code, tests and probably a CI pipeline and a tracker full of issues.

**Bring:** the repository, access to its tracker, and the team's current test and build commands (Compasso detects them; you confirm).

## Steps

1. **`/compasso:setup`.**
   - It detects `test`, `lint`, `typecheck`, `build` and `e2e` from the repository's manifests and CI. You confirm or correct each.
   - It finds the coverage command and the report it writes. Coverage is measured on **changed lines only**, so an old codebase with low coverage is not punished; below 80% is a warning, never a block.
   - **Test frameworks:** it shows, per language, what you already use for unit, API, browser e2e, coverage and property-based tests. Compasso's default fills only an area where you have nothing, and is added by the first story that needs it. Your frameworks are never replaced.
   - **Test paths:** check `test_paths` matches your layout. The builder may never change files there.
   - **Sensitive paths:** name the folders for authentication, payments, personal data and secrets (`risk.sensitive_paths`). A change there always needs a person, and security plans abuse cases for stories that touch them.
   - **Pipeline:** on GitLab, add the generated file to your existing `.gitlab-ci.yml` with one `include`. On GitHub, it writes `.github/workflows/compasso.yml` next to your workflows, and `tracker.sh protect` (after you agree) sets the branch rules.
   - It creates Compasso's labels and issue templates. Templates you already have are kept.

2. **Choose how to plan the first sprint.**
   - **The team already knows the goal:** `/compasso:plan`. See [Planning a known sprint](known-sprint.md).
   - **The work is scattered across tracker issues:** `/compasso:discover` with the issue numbers, then `/compasso:backlog` and `/compasso:roadmap`. The issues become features with rough hours and an MVP line, or a "next release" line.
   - **One feature to start with:** `/compasso:feature <issue>`. See [One idea, one feature](one-idea.md).

3. **Build** with `/compasso:sprint` or story by story with `/compasso:story <iid>`.

## What changes for the team

- Stories are at most a day. Big existing issues are split by the planner; the originals stay as features.
- Every merge request gets a review and a security review, whoever wrote it. `/compasso:review <mr>` works on merge requests written by people too.
- Lessons from things that went wrong land in `docs/learnings/`, and each role only sees the lessons for the paths it touches.
- Nothing merges on its own unless you set `approvals.merge` to `agent` or `risk`.

## Tips

- Start with one feature, not a whole sprint, to see the flow on your codebase before committing the team to it.
- If your CI already runs the tests, the Compasso pipeline duplicates them at first. Keep both until you trust it, then remove your copy.
- Stories that touch old code without tests get failing tests first, which adds tests where you most need them.
