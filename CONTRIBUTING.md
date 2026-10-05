# Contributing

Compasso is opinionated about how software gets delivered: small stories, tests first, security review that is never skipped, a person approving by default. Issues and pull requests are welcome. A change that works against those opinions is likely to be declined, even when the code is good.

## Toolchain

```
bash (3.2 or later)  git  jq  yq (mikefarah v4)  bats-core  perl
```

`glab` and `gh` are only needed to try Compasso against a real tracker; the tests use fakes of both (`tests/fake/`). Hardening's live checks need Docker. The engine is bash, jq and YAML: there is nothing to build.

## The checks

```bash
bats tests/                     # the whole suite, offline
bats tests/github.bats          # one file
```

Scripts must run on macOS's bash 3.2. In bats, write `[[ ... ]] || false`: bash 3.2 ignores a failing `[[ ]]` in the middle of a test.

## How change happens here

- **Small and single-purpose.** One behaviour per change. Adjacent improvements become their own issue.
- **An abstraction needs a current consumer.** Prefer deleting to configuring.
- **Scripts decide, agents judge.** Anything a machine can check belongs in `bin/` with a test, not in a skill's prose. Skills and roles say what to run and what to decide.
- **Both trackers, both harnesses.** A tracker command exists in `bin/tracker/gitlab.sh` and `bin/tracker/github.sh` with the same options and output shape. A skill works on Claude Code and Codex (`bin/install-codex.sh` rewrites it; `tests/install-codex.bats` checks it).
- **Roles are edited in `roles/`, never in `agents/`.** Run `bin/gen-agents.sh` after changing a role; the tests fail while `agents/` is out of date. No role gets the Agent tool.
- **Hooks stay fast and scoped.** `bin/hook.sh` exits at once outside a Compasso repository; guards fail closed, the other hooks fail silently. A new rule comes with tests for what it refuses and what it still allows (`tests/hooks.bats`).
- **Security review stays mandatory.** No change may add a path that skips it, or lets an agent merge with an open security finding.
- **Update the docs with the behaviour.** `docs/SPEC.md` records design decisions with their date; `README.md` says how to use what shipped.

## Tests

- Write the failing test first, and make sure it fails for the reason you expect.
- Prove the test can fail: break the behaviour on purpose, watch the test go red, then restore it.
- No test is weakened to make a build pass. If a behaviour is retired, turn its test around so the old behaviour fails.
- Cover both directions: what a gate refuses, and what it still lets through.
- A tracker change is tested against the fakes, then tried once against a real project before it is called done.

## Large data

Never pass JSON that can grow (a plan, a sprint's items, descriptions, a page's data) as a command-line argument or an environment variable: Linux limits each one to 128 KB, and a large project fails or, worse, produces an empty file. Use `jq --slurpfile name <(printf '%s' "$json")` (then `$name[0]`), stdin, or a file. The tests include plans and descriptions over 1 MB.

## Languages

A language is `templates/locales/<language>.yaml`, `templates/issue_templates/<language>/` and `templates/brief/<language>.md`. `tests/locale.bats` fails while the new language lacks a text English has, or drops a `{marker}`. Never add text for people to a script: add a key to every locale and use it through `bin/i18n.jq`.

## Formats

Work items, comments and records are read by people in a hurry. Keep them clear, direct and short: one idea per line, no filler, no process narration. The formats live in `templates/` and `bin/render.jq`; change them there, not inline.

## Commits

One concern per commit, with a message that says what the change does and why. Describe the behaviour that shipped, not the journey.

## Releases

A release sets `version` in `.claude-plugin/plugin.json` and adds the matching section to `CHANGELOG.md` in one commit, then tags that commit with the version (an annotated tag: `--follow-tags` does not push lightweight ones):

```bash
git commit -am "Release 1.1.0" && git tag -a 1.1.0 -m "Release 1.1.0" && git push origin main --follow-tags
```

Claude Code updates an installed plugin only when this version changes: a change merged without a new version never reaches people who already installed Compasso. `tests/release.bats` fails when the version has no section in the changelog.
