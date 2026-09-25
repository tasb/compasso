---
name: start
description: Compasso start - the entry point when you have ideas, requirements or a prototype but no sprints yet. Says where the product stands (setup, discover, backlog, roadmap, plan, build) and runs the next step. Use when the user invokes /compasso:start or $compasso-start, or has ideas and asks how to begin.
---

Find where the product stands and move it one step forward. Scripts are in `${CLAUDE_PLUGIN_ROOT}/bin`.

1. `bash ${CLAUDE_PLUGIN_ROOT}/bin/start.sh --repo .` Show its three lines as they are.

2. Say in one line what the user can bring to that stage, then run it when they agree:
   - **discover** (`${CLAUDE_PLUGIN_ROOT}/skills/discover/SKILL.md`): ideas in the conversation, a document (Markdown, PDF, Word), tracker issues, or a prototype (a running web app, its source code, or a Figma file).
   - **backlog**: a written brief; or skip discovery when the user already has requirements: the backlog stage reads the document directly and writes the brief from it.
   - **roadmap**, **plan**, **build**: the next command as `start.sh` names it.

3. When `start.sh` says there is no product code yet, repeat it at the backlog stage: the first feature is the walking skeleton (F-0).
