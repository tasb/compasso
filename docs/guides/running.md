# Running the team

**When:** the team is set up ([A team of agents](team.md)) and the first plan is on the tracker. From here the agents work on their own; a person adds the crontab lines, answers questions, tests on staging and decides when the stage changes.

## Start each agent

On each agent's machine, in its checkout:

1. Run `bin/cron.sh --repo .` (setup runs it for you at the end). It prints one line.
2. `crontab -e`, paste the line, save.
3. `crontab -l` shows it.
4. After the first period (`run.lead_minutes`, 15 by default, for the tech lead; `run.dev_minutes`, 10, for a developer), `tail .compasso/runs/runner/cron.log` shows a run. `nothing to do` is a run.
5. On macOS, if the log shows `Operation not permitted`, give `cron` Full Disk Access (System Settings > Privacy & Security), then wait for the next run.

The line starts `~/.compasso/bin/compasso-run`, which runs the newest Compasso installed on the machine, so a plugin update needs no new line. It carries the PATH of the shell you ran `cron.sh` in: cron's own has no `glab`, `gh`, `jq`, `yq` or `claude`. Run `cron.sh` again after installing one of them somewhere new.

To stop an agent, remove its line (`crontab -e`).

## What a run does

Each run reads the tracker once and picks one job. With nothing to do it exits and no model starts.

- **A developer** reworks its merge request when the tech lead sent it back or its pipeline failed; otherwise it continues a story it started; otherwise it builds its next ready story. Bugs come first, the most severe first, then the earliest sprint.
- **The tech lead**, first match wins:
  1. unblocks a story whose question a person closed;
  2. reverts the merge that turned the default branch red, as a `compasso::fix-main` merge request, and reopens the stories it closed;
  3. reviews every merge request with a green pipeline, one pass, blockers only, and merges it or sends it back;
  4. in `harden`, audits the whole code once;
  5. in `harden` and `production`, turns the after-MVP list into stories;
  6. asks people to test a feature on staging once all its stories are merged, then closes it;
  7. assigns a story to the developer with the fewest ready ones, while one has fewer than `team.queue.min`;
  8. splits the next `compasso::new` feature into stories.

Steps 1, 2 and 7 run in the shell, without a model. The others run one headless session for at most `run.job_minutes`.

A run that fails, times out or changes nothing counts against its job. After `run.failures` (2) in a row, a person is asked, and that job is skipped until the question is closed. Other jobs go on.

## Answer a question

Every question from the agents is a `needs::human` issue assigned to the people in `people.ask`, in the project's language. It says what is needed, why (the command, the error, the link) and what the team does meanwhile.

1. Open the issue.
2. Do the numbered steps. They are actions on your side: add a CI variable, grant access, decide a scope question, read a log.
3. When a step asks for a decision, write it as a comment on the issue.
4. Close the issue. Closing it is always the last step.

On its next run the tech lead removes `needs::human` from the story the question held, and a developer picks it up again. Until then only that story waits.

A delivery is a question too: "test this feature on staging", with the staging address and one step per acceptance line. A problem you find there is a bug: file it from the Bug template, with a `severity::` label.

## See where things stand

`/compasso:status` reads the tracker and this machine's runner files, and changes nothing:
- the stage and the default branch's last pipeline;
- what waits for a person;
- each open merge request: green and waiting for review, sent back, draft, or failing;
- each developer's stories and bugs, and what blocks them;
- the next job of the tech lead and of each developer;
- this machine's last runs, and the jobs skipped until a person answers.

Each job's session log is in `.compasso/runs/runner/logs/`, and every run is one line of `.compasso/runs/runner/events.jsonl`, with the session's tokens and cost when the harness reports them. `/compasso:report` reads these lines for the agents' effort.

Before each run the runner brings its checkout to the default branch as origin has it. Keep the agent's checkout for the agent: with uncommitted changes in it, the runner leaves it as it is and the next jobs run on an old configuration.

## Change the stage

`stage` in `.compasso/project.yaml` decides how much each change is checked before it merges:

- **`mvp`**, for a product nobody uses yet: the pipeline's secret and SAST scans, and the tech lead's blocker-only review. Everything else goes to one after-MVP list, and none of it becomes work in the MVP. The pipeline leaves out e2e and coverage.
- **`harden`**: as `mvp`, plus one audit of the whole code. The after-MVP list becomes stories under one hardening feature.
- **`production`**: a reviewer and a security agent read every merge request with the tech lead. The tester writes each story's tests. The pipeline runs e2e and coverage. Agent sessions run only allowlisted tools (`run.allow` adds more).

To change it:

1. Edit `stage` (or run `/compasso:setup` in the tech lead's checkout).
2. Run `bin/ci.sh --repo .`: the pipeline gains or drops e2e and coverage.
3. Commit both and merge them to the default branch.
4. Nothing else: each runner brings its checkout up to date before its next run.

In `harden`, the tech lead's machine records the audit as done in `.compasso/runs/runner/audited`. Delete that file to audit again.

## Good to know

- Sprints stay. A story keeps its sprint, and the tech lead plans and assigns a later sprint's work without waiting for the current one to end.
- With `trust.verify_approval: false` (the default), anyone who can edit a story chooses commands the agents run. Set it to `true` when people outside the team can edit the tracker; each new Verify command then waits for a person's approval on that machine (`bin/trust.sh`).
- `/compasso:report` builds the sprint's HTML report at any time.
