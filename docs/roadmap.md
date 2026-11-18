# Roadmap after 4.0.0

Decided on 2026-11-18: first the 4.0.0 pilot on GoSales (one week, measured against the month before). The pilot's numbers (jobs, tokens, reworks, questions, reverts, bugs found on staging) decide the order below and whether each step is still worth it.

## Where this comes from

Two pieces of writing, read against 4.0.0:

- [How the Claude Code team thinks about verification](https://claude.dev/blog/how-the-claude-code-team-thinks-about-verification/): you delegate only what you can verify; a person defines "done" and reviews the evidence instead of every diff; end-to-end tests first, because they are hard to fool; checks stay out of reach of the changes they judge; every commit says how it was verified, "none" included; a new gate starts in observe mode; tune one reviewer rather than stacking them; a miss becomes a rule only when it recurs, and rules are pruned.
- [Our Architecture of an AI Software Factory](https://www.supermodular.ai/blog/ai-software-factory-architecture): a control plane decides what runs next and whether its output is accepted, and an executor runs one turn; every deliverable has deterministic checks, and an unknown check is a fail; agents hold no credentials and have no merge tool; a ledger per task and commit trailers trace a revert back to the step that caused it; gates start human and come out one at a time on evidence: promotion is proposed, demotion is automatic.

4.0.0 already has the shape: `bin/run.sh` and `bin/next.jq` with the tracker are the control plane, each job is a fresh session with a time limit, `needs::human` is the structured question, two failures in a row go to a person, and `events.jsonl` is a ledger.

Two axes, kept apart:

- **Stage** (`mvp`, `harden`, `production`): how much risk the product can take.
- **Autonomy per step** (human, observe, agent): how much the team trusts the automation, on evidence. 4.0.0 has only the first axis; the second is what makes Compasso a software factory.

## 4.1 Checks out of reach of the change

1. A pipeline check fails a merge request that changes the pipeline, `.compasso/project.yaml`, `CLAUDE.md` or `AGENTS.md`; a person merges such a change.
2. The tracker is the broker: agents' accounts are Developers, and only the tech lead's account (Maintainer) merges to the protected default branch. Setup checks it and says how to fix it.
3. Commit trailers: `Compasso-Job: build:12` and `Compasso-Verified: verify.sh | none`. A red-main revert names the job that caused it; the report counts unverified commits.
4. Flaky tests: never skipped, slept on or retried. Fix the cause, or delete the test and say why.

## 4.2 Verify by running the change

1. Before `deliver`, a job runs the feature's acceptance lines on staging with Playwright (`prototype.image`) and attaches screenshots and traces to the question: the person reviews evidence, and tests by hand only what they want.
2. In `mvp` too: one end-to-end check per feature, on staging, rather than per merge request. The MVP stays fast and gains a check that is hard to fool.
3. Guidance for property tests (invariants, round trips) and differential tests (old against new) in rewrites and migrations.

## 4.3 Gates per step, with a trust ladder

1. `gates:` in the configuration for plan, merge, deliver and the second rework: `human | observe | agent`. The stage only sets the defaults.
2. The report shows each gate's evidence: send-backs, questions, reverts and bugs found on staging, per step.
3. Promotion is proposed to a person once a step crosses its threshold with a minimum sample; demotion is automatic (a red-main revert moves the merge gate back to human). Different thresholds up and down, so a gate does not flap.
4. Locked gates: a merge that touches protected paths stays human.

## 4.4 Rules from misses

1. A tech lead job mines rework comments and reverts; a lesson is written only for a pattern seen at least twice, and lessons that no longer apply are pruned.
2. In `production`, try one reviewer with a checklist of lessons with diff-readable triggers, and security only on sensitive paths, instead of the reviewer and security on every merge request. Measure against reverts and bugs before switching.

## Not planned

A control-plane service, a microVM per turn, a credential broker of our own, a web UI, and workflows described in YAML. They are another product; the steps above get most of the gain inside the bash-and-tracker design. Declarative workflows come back only if the pilot shows `bin/next.jq` is what holds the team back.
