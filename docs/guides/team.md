# A team of agents

**When:** you want the agents to work on their own: one tech lead and one or more developers, each an agent with its own checkout, on a server or a person's machine. The runner only works for a team.

**What you bring:** the repository, one machine (or one checkout) per agent with cron, and one tracker account per agent.

## Set it up

1. **Accounts.** Each agent needs a tracker account no person uses.
   - GitLab: a service account per agent (every tier; a group Owner or a project Maintainer creates it), added to the project as Developer, with a personal access token.
   - GitHub: a machine user (an ordinary account a person creates for automation), with write access to the repository and the GitHub Project. The project's agents share it.
2. **The tech lead first.** In the tech lead's checkout, run `/compasso:setup` and choose **tech lead**.
   - *You decide:* the developers' names (`team.developers`, such as `[ana, rui]`: lowercase letters, digits and hyphens), how many ready stories each keeps waiting (`team.queue.min`), the stage, the staging deploy command and address, the people the agents ask (`people.ask`), the runner's periods, and the account with its commit email.
   - The GitLab token goes into a file in your own terminal, never into the chat; setup prints the command.
   - Setup creates a `dev::<name>` label for each developer.
3. **Commit and merge** `.compasso/project.yaml`, the pipeline file and the issue templates to the default branch.
4. **Each developer.** In its own checkout, with that configuration pulled, run `/compasso:setup` and choose **developer**.
   - *You decide:* its name, one of `team.developers`, and its account with its commit email.
5. **Start every agent** with its crontab line: see [Running the team](running.md#start-each-agent).
6. **Main stays green.** Ask a project Maintainer to make the tracker refuse a merge whose pipeline failed. GitLab (Settings > Merge requests): "Pipelines must succeed". GitHub: the ruleset `tracker.sh protect` sets.

**A developer who joins later:** add the name to `team.developers`, merge it, run `tracker.sh ensure-labels --repo .` in the tech lead's checkout, then steps 4 and 5 for the new developer.

## Who does what

| Persona | Does | Never |
|---|---|---|
| Tech lead | Reviews and merges, delivers features to staging, plans features into stories, assigns, reverts a red default branch, asks people | Builds a story |
| Developer | Builds and reworks what carries its name, opens the merge request | Merges, plans, changes scope or settings |
| Default (no persona) | Only reads a team project: `/compasso:status`, `/compasso:report`, `/compasso:present` | |

- The tech lead decides everything except scope, cost and secrets. Those become a `needs::human` question.
- A developer that needs something only a person can give (a secret, access, a scope decision) asks once and moves on to other work.
- The persona is kept on the machine, per checkout, not in the repository. The tracker cannot stop a member from changing a label, so the persona checks prevent mistakes; they are not a security boundary.
- Each status is a label: `compasso::backlog`, `compasso::building`, `compasso::in-review`. `compasso::rework` marks a merge request sent back; `needs::human` marks a story waiting for a person.
