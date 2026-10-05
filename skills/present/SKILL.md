---
name: present
description: Compasso present - build one self-contained HTML presentation of the solution from Compasso's files - the problem and goals, the functional solution (features, MVP line, prototype screens), the technical solution (stack, components diagram, integrations, data, observability, security), the decisions, the sprints, and the next sprint's user stories with links to the tracker. Use when the user invokes /compasso:present or $compasso-present, or asks for a presentation of the solution or plan.
---

Build the solution presentation. Scripts are in `${CLAUDE_PLUGIN_ROOT}/bin`. `RUN` is `.compasso/runs/present`. It writes one HTML file and changes nothing else.

1. **What exists.** `bash ${CLAUDE_PLUGIN_ROOT}/bin/start.sh --repo .` The presentation uses whatever exists and says on the page what is missing; for the full picture, the product needs a brief and a backlog (`/compasso:discover`, `/compasso:backlog`), a technical solution (`/compasso:architect`), sprints (`/compasso:roadmap`) and a planned next sprint (`/compasso:plan`). Say which are missing and ask whether to build now or run them first.

2. **Language.** The page's labels come in the project's `language` (`templates/locales/`). Only to change a label, or for a language Compasso does not ship, write `RUN/ui.json` with the labels to replace (`{"key": "text"}`; the keys are under `ui.presentation` in `${CLAUDE_PLUGIN_ROOT}/templates/locales/en.yaml`) and pass `--ui RUN/ui.json`.

3. **Build.** `bash ${CLAUDE_PLUGIN_ROOT}/bin/present.sh --repo . --out docs/compasso/presentation.html [--ui RUN/ui.json]`.

4. Hand back: the file's path, what it covers (sections) and what it says is missing, and that it is self-contained: it opens offline, prints one section per page, and can be sent as it is. It is regenerated the same way whenever the plan changes. Offer to commit it in a merge request with `bash ${CLAUDE_PLUGIN_ROOT}/bin/plan-pr.sh --repo . --title "Solution presentation" --branch docs/presentation --include docs/compasso/presentation.html`.
