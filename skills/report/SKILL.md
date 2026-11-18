---
name: report
description: Compasso report - build the sprint's HTML report (delivery, flow and waiting, quality, agent effort and cost) from the tracker and the stories' metrics, and open it. Use when the user invokes /compasso:report or $compasso-report.
---

Build the current sprint's report. Scripts are in `${CLAUDE_PLUGIN_ROOT}/bin`.

**Persona.** `bash ${CLAUDE_PLUGIN_ROOT}/bin/persona.sh gate --repo . --skill report` first. On a non-zero exit, show its message and stop: this checkout's persona may not run this command.

1. **Tracker gate.** `bash ${CLAUDE_PLUGIN_ROOT}/bin/tracker.sh check --repo .` Stop on a non-zero exit. `git fetch` and read the default branch, where the metrics files of stories merged before 4.0.0 are.

2. **Collect.** The agents' effort comes from the runners' jobs: each machine's runner writes its own `.compasso/runs/runner/events.jsonl` (each job, its stories, its time and, when the harness reports them, its tokens and cost). Ask the user whether to include the developers' machines. With a yes, give them numbered steps to copy each developer's file here, under `.compasso/runs/report/events-<name>.jsonl` (for example `scp <machine>:<checkout>/.compasso/runs/runner/events.jsonl .compasso/runs/report/events-<name>.jsonl`), and wait for them. Then `bash ${CLAUDE_PLUGIN_ROOT}/bin/metrics.sh collect --repo . --out .compasso/runs/report/S<n>.json`, with `--events <file>` for this machine's file and each copied one. Without `--events` it reads only this machine's jobs: say so in the summary.

3. **Render.** `bash ${CLAUDE_PLUGIN_ROOT}/bin/report.sh --data .compasso/runs/report/S<n>.json --out .compasso/runs/report/S<n>-report.html` and open it for the user.

4. **Summarise** in the conversation: hours done of planned, stories done and what the open ones wait on, the median wait for approval, security findings still open, and agent time (and cost, when known) against the estimates, by job. Point out the biggest wait.
