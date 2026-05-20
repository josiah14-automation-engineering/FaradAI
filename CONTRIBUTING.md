# Contributing to FaradAI

Thanks for your interest. FaradAI is a personal tool in active use, and contributions are welcome when they fit the project's goals: a minimal, secure, portable container for CLI-based AI coding agents.

This is a solo-maintained project. Reviews may take time, and not every contribution will be a good fit. Opening an issue before writing code is the best way to avoid wasted effort.

## Code of conduct

Be direct, good-faith, and respectful. This project follows the [Contributor Covenant v2.1](https://www.contributor-covenant.org/version/2/1/code_of_conduct/).

## Ways to contribute

- **Bug reports** — something broken or behaving unexpectedly
- **Documentation** — unclear instructions, missing edge cases, outdated content
- **Small, targeted fixes** — typos, broken commands, obvious gaps
- **New features** — open an issue first to discuss scope and fit

What tends not to be a good fit: large refactors, opinionated style changes, or features that add complexity without broad utility.

## Setting up your environment

**Prerequisites:** Docker, bash, git, and either `shellcheck` or `hadolint` for linting.

```bash
git clone https://github.com/josiah14-automation-engineering/faradai.git
cd faradai
./install.sh   # builds the image and installs the CLI
```

## Making changes

Fork the repo and create a branch named for your change:

```bash
git checkout -b fix/aider-mount-conditional
git checkout -b feat/uninstall-command
```

Keep commits small and focused — one logical change per commit. Write commit messages that describe *why*, not just *what*.

Run `shellcheck` on any shell script changes before committing:

```bash
shellcheck faradai install.sh build.sh entrypoint.sh
```

Run `hadolint` on any Dockerfile changes:

```bash
hadolint Dockerfile
```

## Testing

There is no automated test suite yet. Manually smoke-test any code change:

1. **Build:** `./build.sh` — should complete without errors
2. **Launch:** `faradai bash` — should drop into a shell inside the container
3. **Tool check:** `claude --version`, `aider --version`, `gh --version` should all return output
4. **Mount check:** confirm `$FARADAI_WORKDIR` is accessible inside the container

If you're adding a feature, include instructions in your PR for how to verify it.

## Submitting a pull request

1. Open an issue first if the change is anything beyond a small fix
2. Keep the PR focused — one concern per PR
3. Update relevant documentation (README if user-facing, BUILDLOG if architectural)
4. Describe what the change does and how you tested it

PRs that pass `shellcheck` and `hadolint` cleanly are much easier to review.

## Questions

Open a [GitHub issue](https://github.com/josiah14-automation-engineering/faradai/issues) for anything project-related. For anything else, reach out directly via the contact on my GitHub profile.
