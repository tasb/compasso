# After the MVP: hardening

**When:** the MVP sprint has closed and you want more confidence before growing the product. Hardening is optional and never part of the story or sprint flow, so it never slows delivery.

## Steps

1. **`/compasso:harden <feature or epic>`** runs the **code set** by default. It needs no infrastructure:
   - **mutation testing:** small deliberate bugs in the feature's changed lines; any the tests don't catch is a gap;
   - **property-based tests** from the acceptance;
   - **flaky tests:** the suite run several times;
   - **test smells** in the feature's tests.

2. **`--set live`** adds checks against a running test environment. They need Docker and `harden.environment` in the config:
   - API fuzzing (reading requests only, unless the environment is marked disposable);
   - a ZAP security scan;
   - performance against your limits;
   - accessibility of the feature's pages.
   Before each run you confirm the URL. **Never point it at production.**

3. **Gaps become stories** for a later sprint, in no sprint yet. The next `/compasso:plan` or `/compasso:roadmap` offers them.

4. **A report** is posted on the feature: what ran, what it found, and the new stories.

## Tips

- Start with the features that matter most: sensitive ones, and the MVP's core flow.
- A mutant the tests miss is a missing test, not necessarily a bug. The stories say which it is.
