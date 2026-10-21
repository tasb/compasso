# A team of agents

**When:** more than one agent works on the project: a tech lead's and one or more developers', on servers or on people's machines. Claude Code only for now.

**What you bring:** the repository, and one long-running Claude Code session per agent.

## Set it up

0. **Accounts.** Each agent needs a tracker account no person uses.
   - GitLab: a service account per agent (every tier; a group Owner or a project Maintainer creates it), added to the project as Developer, with a personal access token.
   - GitHub: a machine user (an ordinary account a person creates for automation), with write access to the repository and the GitHub Project. The project's agents share it.
1. **The tech lead first.** Run `/compasso:setup` and choose **tech lead**. It turns the team on (`team.enabled: true`) and goes through the whole setup.
   - *You decide:* the stage (`mvp` or `production`), the account and its commit email, how often the tech lead and the developers poll, and the queue.
   - Commit and merge `.compasso/project.yaml`.
2. **Each developer.** In its own checkout, with that configuration pulled, run `/compasso:setup` and choose **developer**.
   - *You decide:* its name, such as `ana` (lowercase letters, digits and hyphens), and its account and commit email.
   - The GitLab token goes into a file in your own terminal, never into the chat; setup prints the command.
   - It ends by printing a JSON block. It holds no secret.
3. **Join.** Paste the block into the tech lead's session. It creates the label `dev::ana` and adds the developer's account to `team.agents`; commit that change. A name already taken is refused, and that developer runs setup again with another.
4. **Start the poll** in every session, as setup says: the tech lead two sessions, `/loop 15m /compasso:work --merge` and `/loop 30m /compasso:work --flow`; developers `/loop 60m /compasso:work`.

A developer who joins later repeats steps 2 to 4.

## Day to day

- **The tech lead plans** as before (`/compasso:plan`, `/compasso:feature`). Every story names its developer, `dev: ana`, on the story or once on its feature.
  *You decide:* who gets what.
- **A developer builds** what carries its name, at its next poll, and nothing else. Before building it claims the story with a comment, so no other session builds the same one. It ends by opening the merge request with its findings, and a cost report when infrastructure changed, as comments, and stops.
- **The tech lead merges.** At its merge poll it reads each merge request in review, works out the risk itself and has the approver check it. It merges only what is up to date with the default branch and whose pipeline passed: one that is behind is brought up to date and merged at a later poll, one that conflicts or fails goes back to its developer. What needs no person it merges. What needs one gets `needs::approval`.
- **Stories wait for what they depend on to merge.** No story is built on another's unmerged branch; its developer takes other work meanwhile.
- **Findings are fixed in the story,** minors too, and posted on it. Only a minor finding whose fix needs a person (or an admin of an outside system) becomes a follow-up, labelled `owner::human`, in the sprint; the tech lead never gives it to a developer.
  *You decide:* approve or reject it with the tracker's review (GitHub: Approve or Request changes; GitLab: Approve, or a comment saying what to change). The tech lead merges after an approval; a rejection goes back to the same developer, on the same merge request.
- **When a person must approve.** In `mvp`: only an infrastructure change whose cost report says `increase` or `unknown`. In `production`: also sensitive paths, infrastructure, migrations and public API contracts, the build or dependencies, a large change to the product's code, low coverage, and anything security marks sensitive.
- **Questions.** When a developer cannot go on, it writes one comment of at most 250 characters on the story and raises `needs::lead`. It then moves to its next story.
- **The tech lead's poll** shows the merge requests in review, the questions, the bugs and stories with no developer, and each developer's backlog. The agent proposes an answer for every question.
  *You decide:* every answer. In `mvp` the agent assigns on its own, keeping each developer's backlog between 5 and 15 stories within the sprint; in `production` it proposes and you decide every assignment.
- **Bugs** found by feature e2e, testers or the sprint's security pass are filed with no developer. Nothing builds one until the tech lead assigns it.
- **Work for a person** is a blocker, as always. When it closes, the tech lead closes the story it held or assigns it.
- **Sprint close** (regression, the security pass, the test guide, the report) is the tech lead's.

## Good to know

- A question and its answer can each wait one poll: up to an hour and a half with the defaults.
- Each status is a label: `compasso::backlog`, `compasso::building`, `compasso::in-review`; `needs::lead` and `needs::approval` sit beside them.
- Switching `stage` to `production` is how you say the product is live: setup again, or an edit to the file, merged to the default branch.
- The poll is skipped while an agent is working.
- An agent with no persona only reads a team project. `/compasso:status` works for everyone.
- The persona is kept on the machine, per checkout, not in the repository.
- The tracker cannot stop a member from changing a label. The persona checks prevent mistakes; they are not a security boundary.
