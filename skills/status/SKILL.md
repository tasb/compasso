---
name: status
description: Compasso status - a read-only readout of where the sprint or one story stands. For the sprint, what can be built now, what waits and on whom, the features, the plan on the default branch, and the local runs. For a story, its tracker state, what it waits on, how far its local run got, and the step to resume from. Changes nothing. Use when the user invokes /compasso:status [iid] or $compasso-status.
---

A read-only readout. It changes nothing: no tracker state or label, no file, no approval, no git fetch. Scripts are in `${CLAUDE_PLUGIN_ROOT}/bin`.

1. Run `bash ${CLAUDE_PLUGIN_ROOT}/bin/status.sh --repo .`, adding `--iid <iid>` when the user names a story or bug, or `--milestone S<n>` for a sprint other than the one in `.compasso/plan.yaml`.

2. Show its output as it is. It exits 1 when the tracker could not be read; its local part is still valid, so show it with the tracker's message. Exit 2 means there is no plan: point to `/compasso:plan`, or ask which sprint (`--milestone`).

3. Add only what the readout implies, in one line at most: the command that moves things forward (`/compasso:story <iid>` for a story that can be built now or a run to resume, `/compasso:sprint` for a batch). Do not start it: this command only reports.
