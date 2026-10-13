# A team of agents

**When:** more than one agent works on the project: a tech lead's and one or more developers', on servers or on people's machines. Claude Code only for now.

**What you bring:** the repository, and one long-running Claude Code session per agent.

## Set it up

1. **The tech lead first.** Run `/compasso:setup` and choose **tech lead**. It turns the team on (`team.enabled: true`) and goes through the whole setup. Commit and merge `.compasso/project.yaml`.
2. **Each developer.** In its own checkout, with that configuration pulled, run `/compasso:setup` and choose **developer**.
   - *You decide:* its name, such as `ana`: lowercase letters, digits and hyphens.
   - It ends by printing a JSON block. It holds no secret.
3. **Join.** Paste the block into the tech lead's session. It creates the label `dev::ana`. A name already taken is refused, and that developer runs setup again with another.
4. **Start the poll** in every session, as setup says: `/loop 60m /compasso:work`.

A developer who joins later repeats steps 2 to 4.

## Day to day

- **The tech lead plans** as before (`/compasso:plan`, `/compasso:feature`). Every story names its developer, `dev: ana`, on the story or once on its feature.
  *You decide:* who gets what.
- **A developer builds** what carries its name, at its next poll, and nothing else. Before building it claims the story with a comment, so no other session builds the same one.
- **Questions.** When a developer cannot go on, it writes one comment of at most 250 characters on the story and raises `needs::lead`. It then moves to its next story.
- **The tech lead's poll** shows the questions, the bugs and stories with no developer, and each developer's load. The agent proposes an answer or a developer.
  *You decide:* every answer and every assignment.
- **Bugs** found by feature e2e, testers or the sprint's security pass are filed with no developer. Nothing builds one until the tech lead assigns it.
- **Work for a person** is a blocker, as always. When it closes, the tech lead closes the story it held or assigns it.
- **Sprint close** (regression, the security pass, the test guide, the report) is the tech lead's.

## Good to know

- A question and its answer can each wait one poll: up to two hours with the default.
- The poll is skipped while an agent is working.
- An agent with no persona only reads a team project. `/compasso:status` works for everyone.
- The persona is kept on the machine, per checkout, not in the repository.
- The tracker cannot stop a member from changing a label. The persona checks prevent mistakes; they are not a security boundary.
