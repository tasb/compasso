# Guides

One guide per starting point. Each says when it fits, what to bring, the commands in order, what you decide at each step, and what you end up with.

| You have | Guide |
|---|---|
| An idea for a new product and an empty repository | [Greenfield](greenfield.md) |
| An existing codebase and team, adopting Compasso | [Brownfield](brownfield.md) |
| A clickable prototype: a running web app, its code, or a Figma file | [Starting from a prototype](prototype.md) |
| A requirements or specification document | [Starting from requirements](requirements.md) |
| One idea for a product that already exists | [One idea, one feature](one-idea.md) |
| A sprint goal the team already agreed | [Planning a known sprint](known-sprint.md) |
| A bug, or one small change | [A bug or a small change](bug-or-small-change.md) |
| A sprint under way | [Running a sprint](running-a-sprint.md) |
| Merge requests to review, written by anyone | [Reviewing a merge request](reviewing.md) |
| An MVP that has shipped | [After the MVP: hardening](after-the-mvp.md) |

Not sure? Run `/compasso:start`: it looks at what the repository holds and tells you which step comes next.

## What every path shares

- **Setup first.** `/compasso:setup` connects GitLab or GitHub. No other command runs until the tracker check passes.
- **You approve.** A person approves every plan and, by default, every merge. Security review runs on every plan and every merge request and is never skipped.
- **Small work.** A story is at most one day (target half a day), a feature at most half a sprint, an epic one sprint.
- **Files in the repository.** The brief, backlog, roadmap and plan live in `.compasso/`, each with a decision record, and reach the default branch through a merge request.

On Codex, every `/compasso:<name>` command is typed `$compasso-<name>`.
