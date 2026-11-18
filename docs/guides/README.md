# Guides

One guide per starting point, then two for the team that builds. Each says when it fits, what to bring, the steps in order, what you decide at each step, and what you end up with.

| You have | Guide |
|---|---|
| An idea for a new product and an empty repository | [Greenfield](greenfield.md) |
| An existing codebase and team, adopting Compasso | [Brownfield](brownfield.md) |
| A clickable prototype: a running web app, its code, or a Figma file | [Starting from a prototype](prototype.md) |
| A requirements or specification document | [Starting from requirements](requirements.md) |
| A first sprint the team already agreed | [Planning a known sprint](known-sprint.md) |
| One idea for a product that already exists | [One idea, one feature](one-idea.md) |
| A bug, or one small change | [A bug or a small change](bug-or-small-change.md) |
| Agents to set up: a tech lead and developers | [A team of agents](team.md) |
| A team set up, and work on the tracker | [Running the team](running.md) |
| A plan to present to a team or a client | Run `/compasso:present` at any point: one HTML page with the functional and technical solution, the sprints and the next sprint's stories |

Not sure? Run `/compasso:start`: it looks at what the repository holds and tells you which step comes next.

## What every path shares

- **Setup first.** `/compasso:setup` connects GitLab or GitHub. No other command runs until the tracker check passes.
- **A person plans, the agents build.** A person runs the steps up to the first plan, in a conversation. From there cron wakes the tech lead and the developers, one job per run, and they ask a person only through `needs::human` issues.
- **The stage sets the checks.** `mvp` goes fast: the pipeline's scans and a blocker-only review. `harden` and `production` add an audit, reviewers and more tests.
- **Small work.** A story fits in one session and at most a day, a feature at most half a sprint, an epic one sprint.
- **Files in the repository.** The brief, backlog, architecture, roadmap and first plan live in `.compasso/`, each with a decision record, and reach the default branch through a merge request.

On Codex, every `/compasso:<name>` command is typed `$compasso-<name>`.
