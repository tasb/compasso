---
name: report
description: Compasso report - build the sprint's HTML report (delivery, flow and waiting, quality, agent effort and cost) from GitLab and the stories' metrics, and open it. Use when the user invokes /compasso:report or $compasso-report, and at sprint close.
---

Build the current sprint's report. Scripts are in `${CLAUDE_PLUGIN_ROOT}/bin`.

1. **Tracker gate.** `bash ${CLAUDE_PLUGIN_ROOT}/bin/tracker/gitlab.sh check --repo .` Stop on a non-zero exit. `git fetch` and read the default branch, where merged stories' metrics files are.

2. **Collect.** `bash ${CLAUDE_PLUGIN_ROOT}/bin/metrics.sh collect --repo . --out .compasso/runs/report/S<n>.json`.

3. **Render.** `bash ${CLAUDE_PLUGIN_ROOT}/bin/report.sh --data .compasso/runs/report/S<n>.json --out .compasso/runs/report/S<n>-report.html` and open it for the user.

4. **Summarise** in the conversation: hours done of planned, stories done and what the open ones wait on, the median wait for approval, security findings still open, and agent time against the estimates. Point out the biggest wait.

At sprint close (the sprint flow's step 5) the same files go to `docs/releases/S<n>-report.json` and `docs/releases/S<n>-report.html` in the test guide's merge request, and the epic's comment links the report next to the guide.
