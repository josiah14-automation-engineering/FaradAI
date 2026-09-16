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

### Go/Elvish/Podman migration environment

Enter the complete migration toolchain with `nix develop`; direnv users can allow the checked-in `.envrc`. Nix supplies Go, Elvish, Podman, Bats, and Hadolint. The root `go.mod` pins application and test libraries. The isolated `tools/go.mod` pins GolangCI-Lint and Trivy; invoke them from the repository root with `go tool -modfile=tools/go.mod TOOL`.

## Making changes

Fork the repo and create a branch named for your change:

```bash
git checkout -b fix/aider-mount-conditional
git checkout -b feat/uninstall-command
```

Keep commits small and focused — one logical change per commit. Write commit messages that describe *why*, not just *what*.

When splitting existing work into multiple commits, prefer patch/hunk-based methods (`git add -p`, `git apply`) over manually deleting or moving code in tracked files to isolate a subset of the changes — hand-editing risks losing or corrupting work that a diff-level operation avoids.

Run `shellcheck` on any Bash changes before committing:

```bash
shellcheck faradai faradai-docker install.sh build.sh entrypoint.sh uninstall-faradai
```

Compile-check Elvish changes and lint `Containerfile` changes:

```bash
elvish -compileonly build.elv
hadolint Containerfile
```

## Testing

Run the relevant automated suites:

```bash
nix develop --command go test ./...
env -u FARADAI_ENABLE_HEADROOM -u FARADAI_ENABLE_PONYTAIL \
  test/libs/bats-core/bin/bats test/unit.bats test/sourced.bats test/entrypoint.bats
```

Use `./build.elv` for the Podman image path and `./build.sh` for the retained
Docker path. For end-to-end checks of the installed Docker implementation,
follow [SMOKETEST.md](SMOKETEST.md).

## Submitting a pull request

1. Open an issue first if the change is anything beyond a small fix
2. Keep the PR focused — one concern per PR
3. Update the relevant documentation: README for current user behavior, DECISIONLOG for settled rationale, BUILDLOG for chronological lessons, and CHANGELOG for releases
4. Describe what the change does and how you tested it

PRs should pass the checks relevant to the files they change.

## Questions

Open a [GitHub issue](https://github.com/josiah14-automation-engineering/faradai/issues) for anything project-related. For anything else, reach out directly via the contact on my GitHub profile.
