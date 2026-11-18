---
name: status
description: Compasso status - a read-only readout of where the project stands, as the runner sees it - the stage, the default branch's pipeline, what waits for a person, the merge requests, each developer's stories, the job bin/run.sh would start next for the tech lead and each developer, and this machine's last runs. Changes nothing. Use when the user invokes /compasso:status or $compasso-status.
---

A read-only readout. It changes nothing: no tracker state or label, no file, no git fetch. Scripts are in `${CLAUDE_PLUGIN_ROOT}/bin`.

**Persona.** `bash ${CLAUDE_PLUGIN_ROOT}/bin/persona.sh gate --repo . --skill status` first. On a non-zero exit, show its message and stop: this checkout's persona may not run this command.

1. Run `bash ${CLAUDE_PLUGIN_ROOT}/bin/status.sh --repo .`. When it warns that a newer Compasso is installed than the one running, show that warning first.
2. Show its output as it is. Exit 1 means the tracker could not be read: show its message with this machine's runs.
3. When something waits for a person, list those issues first, with their links: the person answers there and closes the issue, and the runner goes on by itself. Do not start any job: this command only reports.
