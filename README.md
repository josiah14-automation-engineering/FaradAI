```
≋≋≋≋≋≋≋≋≋≋≋≋≋≋≋≋≋≋≋≋≋≋≋≋≋≋≋≋≋≋≋
≋  ┌───────────────────────┐  ≋
≋  │                       │  ≋
≋  │     F a r a d A I     │  ≋
≋  │                       │  ≋
≋  └───────────────────────┘  ≋
≋≋≋≋≋≋≋≋≋≋≋≋≋≋≋≋≋≋≋≋≋≋≋≋≋≋≋≋≋≋≋
```

# FaradAI

**OS-level filesystem boundary for AI coding agents.**

AI coding assistants scan broadly by default. FaradAI constrains the agent's filesystem access to only the projects you mount — a hard OS-level boundary, not a behavioral guideline.

A Docker container for running Claude Code and aider. Named after the Faraday cage: the AI inside has full capability, but can only reach what you explicitly mount. In v1, the cage constrains the *filesystem* — network egress is open by default. Full network isolation (a credential broker that the agent talks to instead of the internet directly) is planned for v2.

## About this project

FaradAI is built with Claude Code as a coding assistant. [`BUILDLOG.md`](BUILDLOG.md) is a deliberate session-by-session record of every decision, tradeoff, and reasoning thread — proof that this is not AI running loose without thought or supervision. Every change reflects a human judgment call.

[`CHANGELOG.md`](CHANGELOG.md) covers user-facing release notes. [`BUILDLOG.md`](BUILDLOG.md) covers process and reasoning through the first release; [`DECISIONLOG.md`](DECISIONLOG.md) captures architectural decisions thereafter.

## Prerequisites

- Docker
- A Claude Code login session on the host (`claude login` — credentials live in `~/.claude/`)
- An `~/.aider.conf.yml` on the host with your OpenRouter API key (optional — for aider; skipped if the file does not exist)

## Install

```bash
./install.sh
```

Builds the image and copies the `faradai` CLI script to `/usr/local/bin/faradai`. After this, `faradai` is available as a system command.

`build.sh` (called by `install.sh`) uses `--network=host` so the build container can resolve external hostnames during `apt-get` and package installs. This applies to the build only — the runtime container has its own network namespace.

## Run

```bash
faradai
```

Mounts the current directory into the container and launches Claude Code (default). Prompts you to confirm the directory before mounting.

### Modes

An optional argument selects which tool to launch:

| Command | Result |
|---------|--------|
| `faradai` | Claude Code (default) |
| `faradai aider` | aider |
| `faradai bash` | bare shell, useful for debugging |
| `faradai update` | pull latest release from GitHub and reinstall |
| `faradai uninstall` | remove all faradai containers, the image, and installed binaries |

### Multi-project and multi-container usage

By default, `faradai` auto-detects whether a container named `faradai` is already running and attaches if so. Two flags give you explicit control:

| Invocation | Behaviour |
|---|---|
| `faradai` | auto-detect: attach if `faradai` is running, create if not |
| `faradai -n NAME [CMD]` | create container `faradai-NAME`; error if it already exists |
| `faradai -a [CMD]` | attach to running `faradai`; error if not running |
| `faradai -a NAME [CMD]` | attach to running `faradai-NAME`; error if not running |

`-n` and `-a` are mutually exclusive. This lets you run separate containers per project while keeping the default single-container workflow unchanged.

### Configuration

`faradai` reads environment variables to configure the container. Override inline or export from your shell rc file.

**Workspace**

| Variable | Default | Description |
|----------|---------|-------------|
| `FARADAI_WORKDIR` | current directory | project directory mounted and used as working dir |
| `FARADAI_TRUST_DIR` | `0` | set to `1` to skip the directory trust prompt |

**Resource limits**

| Variable | Default | Description |
|----------|---------|-------------|
| `FARADAI_MEMORY` | `4g` | `--memory` — max RAM |
| `FARADAI_CPUS` | `4` | `--cpus` — max CPU cores |
| `FARADAI_PIDS` | `512` | `--pids-limit` — max process count |
| `FARADAI_NETWORK_MODE` | `open` | network access: `open` (default, unrestricted) or `none` (no outbound network) |

**SSH**

| Variable | Default | Description |
|----------|---------|-------------|
| `FARADAI_ENABLE_SSH_AGENT` | `1` | forward host SSH agent socket into the container |
| `FARADAI_TRUST_SSH_AGENT` | `0` | set to `1` to skip the SSH agent forwarding confirmation prompt |
| `FARADAI_MOUNT_SSH_DIR` | `0` | mount `~/.ssh` read-only into the container |

**Docker extras**

| Variable | Default | Description |
|----------|---------|-------------|
| `FARADAI_DOCKER_ARGS` | _(unset)_ | extra flags appended to `docker run`; always permitted: `--env`/`-e`, `--label`/`-l`, `--hostname`; opt-in via vars below |
| `FARADAI_ALLOW_DEVICE` | `0` | set to `1` to permit `--device` in `FARADAI_DOCKER_ARGS` |
| `FARADAI_ALLOW_PUBLISH` | `0` | set to `1` to permit `--publish`/`-p` in `FARADAI_DOCKER_ARGS` |

**Debug**

| Variable | Default | Description |
|----------|---------|-------------|
| `FARADAI_DEBUG` | `0` | set to `1` to print resolved config and the `docker run` invocation before launching |

Example:
```bash
FARADAI_WORKDIR=~/projects FARADAI_MEMORY=8g FARADAI_CPUS=8 faradai
```

`faradai` also uses `$HOME` and `$USER` for mount paths — standard shell variables set automatically by your shell.

### Mounts

| Host | Container | Mode | Required for |
|------|-----------|------|--------------|
| `~/.claude/` | `~/.claude/` | read-write | Claude Code — settings, memory, conversation history |
| `~/.claude/.credentials.json` | `~/.claude/.credentials.json` | read-only | Claude Code — OAuth token, overlaid `:ro` on top of the directory mount to protect it from writes |
| `~/.claude.json` | `~/.claude.json` | read-write | Claude Code — top-level config file (sibling to `~/.claude/`, not inside it) |
| `~/.aider.conf.yml` | `~/.aider.conf.yml` | read-only | Aider — config and OpenRouter API key; `:ro` keeps the key out of agent write access (skipped if file does not exist on host) |
| `~/.gitconfig` | `~/.gitconfig` | read-only | git commits — author identity |
| `~/.config/gh/` | `~/.config/gh/` | read-write | GitHub CLI — auth tokens; created on the host if it does not exist so `gh auth login` inside the container persists across restarts |
| `$SSH_AUTH_SOCK` | `/ssh-agent` | read-only | SSH agent socket — forwarded automatically when present; set `FARADAI_ENABLE_SSH_AGENT=0` to disable |
| `~/.ssh/` | `~/.ssh/` | read-only | SSH key files — opt-in via `FARADAI_MOUNT_SSH_DIR=1`; not needed when agent forwarding is active |
| `$FARADAI_WORKDIR` | `$FARADAI_WORKDIR` | read-write | Your project files — the primary work surface |

The working directory defaults to the current directory (`pwd`) at launch time, mounted at the same path inside the container so all project-relative references, memory files, and tooling behave identically inside and outside.

> **SSH agent forwarding:** When `$SSH_AUTH_SOCK` is set and points to a live socket, FaradAI forwards it into the container at `/ssh-agent`. Common Git hosts (GitHub, GitLab, Bitbucket) are pre-registered in the image's `known_hosts`. Set `FARADAI_ENABLE_SSH_AGENT=0` to disable, or `FARADAI_MOUNT_SSH_DIR=1` to use key files directly instead.

#### Host SSH agent setup

FaradAI forwards your existing agent — it does not start one. The agent must be running on the host before you launch the container.

**Check if an agent is already running:**

```bash
echo "$SSH_AUTH_SOCK"          # should be a non-empty path
ls -la "$SSH_AUTH_SOCK"        # should show a socket: srwxr-xr-x ...
ssh-add -l                     # should list at least one loaded key
```

Most desktop environments (GNOME, KDE, Xfce) start an SSH agent automatically at login and `$SSH_AUTH_SOCK` will already be set. If `ssh-add -l` returns keys, you're done.

**If no agent is running**, start one and add your key for the current session:

```bash
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519      # adjust to your key filename
```

**To persist across shell sessions**, add to your `~/.bashrc` or `~/.zshrc`:

```bash
if [ -z "$SSH_AUTH_SOCK" ]; then
  eval "$(ssh-agent -s)"
fi
```

Then `ssh-add` your key once after each login. For a more robust solution that survives across terminal sessions without re-adding keys, install `keychain`:

```bash
sudo apt install keychain
# Add to ~/.bashrc or ~/.zshrc:
eval "$(keychain --eval --quiet ~/.ssh/id_ed25519)"
```

`keychain` starts one agent per user login session and reuses it across all terminals, including new ones opened after the initial login.

Credentials are delivered as mounted files rather than environment variables — any secret in the environment will appear in tool output if `env` is inspected. See [Security model](#security-model).

## What's in the image

- Ubuntu 24.04
- Node.js — runtime for Claude Code (npm not included; tools are pre-installed in the image)
- Claude Code CLI (`claude`)
- aider (via pipx venv, pre-installed)
- Python 3 + pip + venv — available for intermediate scripting tasks
- git, curl
- gh (GitHub CLI) — installed from GitHub's official apt repository
- vim — available when shelling in for manual edits or troubleshooting
- `HEALTHCHECK` — verifies `claude` and `aider` are runnable every 30s; useful for orchestration environments
- Networking tools: `ping`, `netstat`/`ifconfig` (`net-tools`), `ip`/`ss` (`iproute2`), `dig`/`nslookup` (`dnsutils`), `nc` (`netcat-openbsd`)

## Security model

**Default profile: personal/FOSS development.** FaradAI's defaults are optimized for convenience on personal and open-source projects — writable global `~/.claude`, read-only `~/.aider.conf.yml`, SSH agent forwarding, open outbound network. These are deliberate tradeoffs. If you are working with client code, proprietary data, or mixed-sensitivity workflows, see the [roadmap](ROADMAP.md) for the planned `FARADAI_PROFILE=strict` mode.

**The Faraday cage protects the filesystem boundary, not the process environment.**

Credentials are kept out of environment variables and injected as mounted files instead:

- Claude Code: OAuth token in `~/.claude/.credentials.json` (`:ro` overlay)
- Aider: API key in `~/.aider.conf.yml` (`:ro`)

Any secret present as an environment variable is visible to the agent and will appear in tool output if commands like `env` are run. Prefer file-based credential delivery. If a key must be in the environment, scope it to a cost-limited key with a short rotation cycle.

**The `:ro` mount on `~/.aider.conf.yml` is not a secrecy mechanism.** The agent can read the file directly if instructed to — for example, if you ask it to debug an aider configuration issue. If it does, the key will be transmitted to Anthropic's servers as part of the conversation context. This is a calculated risk: scope your OpenRouter key to a hard cost limit so that any exposure has a bounded blast radius.

### SSH agent forwarding

When `FARADAI_ENABLE_SSH_AGENT=1` (the default) and a live agent socket is present, FaradAI forwards it into the container. **Any process inside the container — including the AI agent — can use the forwarded socket to sign arbitrary SSH operations with any of your loaded keys.** This means the agent could, in principle, authenticate to GitHub as you, push to repositories, or initiate SSH connections to any host your keys grant access to.

On each fresh container start, FaradAI lists the loaded keys and prompts for confirmation before forwarding. Set `FARADAI_TRUST_SSH_AGENT=1` (e.g. in `.zshrc`) to skip this prompt if you always want forwarding. Set `FARADAI_ENABLE_SSH_AGENT=0` to disable forwarding entirely for a session.

For sessions where you do not need Git operations or SSH access inside the container, declining the forwarding prompt is the safest option.

### Network access

The container has unrestricted outbound network access by default. This is intentional for v1: the agent may need to reach arbitrary sources — documentation, APIs, package registries — and restricting outbound would require predicting that in advance, which defeats the purpose of a general-purpose coding assistant.

This is the current gap in the Faraday cage metaphor. Full network isolation — where the agent container talks only to a local credential broker rather than the internet directly — is planned for v2 (see [#30](ROADMAP.md)). For now, `FARADAI_NETWORK_MODE=none` is available as an opt-in for offline sessions where you know the agent won't need network access.

The container can also reach services running on the host via the Docker bridge gateway. This too is intentional — useful for workflows involving local k3s clusters, development servers, or other host-side services you want the agent to interact with.

The meaningful protection is the absence of the Docker socket. Without `/var/run/docker.sock` mounted, the agent cannot escape the container by spawning new containers with unrestricted host mounts. That is the primary container escape vector, and it is not present here.

### Capabilities and privilege escalation

`--cap-drop ALL` removes Docker's default capability set (~14 caps, including `NET_RAW` and `SYS_CHROOT`). `--security-opt no-new-privileges` sets `prctl PR_SET_NO_NEW_PRIVS`, preventing any process in the container from gaining privileges via setuid binaries or filesystem capabilities. `FARADAI_DOCKER_ARGS` does not allow `--cap-add` or `--privileged` — capability restoration requires editing the `faradai` script directly.

## Troubleshooting

**Docker permission denied**
Your user is not in the `docker` group. Fix: `sudo usermod -aG docker $USER`, then log out and back in.

**Credential errors on first launch**
`~/.claude/.credentials.json` is missing or expired. Run `claude login` on the host to refresh it, then relaunch.

**Container name conflict (`faradai` already in use)**
A stopped container is holding the name. The `faradai` script handles this automatically via `docker rm -f faradai` before each new launch. If it persists: `docker rm -f faradai` manually.

**SSH key permissions rejected**
SSH requires key files to be `600`. Fix: `chmod 600 ~/.ssh/id_*`.

**SSH push/pull fails inside the container**
Run `echo $SSH_AUTH_SOCK` inside the container — it should return `/ssh-agent`. If empty, the agent was not forwarded at launch. See [Host SSH agent setup](#host-ssh-agent-setup) for instructions. If your keys are passphrase-protected, run `ssh-add` on the host before starting the container.

**aider not found inside the container**
The image predates the least-privilege install fix (Session 7). Rebuild: `./build.sh && ./install.sh`.

**Wrong model slug in `~/.aider.conf.yml`**
aider / LiteLLM requires the `openrouter/` provider prefix. Correct format: `model: openrouter/<provider>/<model>`. Edit the file on the host (it is mounted `:ro` inside the container).

**`gh` not authenticated inside the container**
`~/.config/gh/` is mounted from the host. If you have previously run `gh auth login` on the host, credentials will be available inside the container automatically. If not, run `gh auth login` from inside the container — tokens will persist to the host mount and survive restarts.

**`install.sh` fails with "sudo is required but not available"**
`install.sh` needs `sudo` to copy the `faradai` binary to `/usr/local/bin`. Install sudo (`apt-get install sudo` on Debian/Ubuntu) or copy the binary manually: `cp faradai /usr/local/bin/faradai && cp uninstall-faradai /usr/local/bin/uninstall-faradai` as root.

---

## Development

[`BUILDLOG.md`](BUILDLOG.md) is a session-by-session record of every implementation decision and tradeoff from inception through v0.1.0-alpha.1 — the reasoning behind changes, not just the changes themselves. Reading it alongside the git history gives a complete picture of how and why the project reached its first release.

After v0.1.0-alpha.1, significant architectural and security decisions are captured in [`DECISIONLOG.md`](DECISIONLOG.md): a terse, indexed log of *why* non-obvious choices were made. [`CHANGELOG.md`](CHANGELOG.md) entries link to relevant [`DECISIONLOG.md`](DECISIONLOG.md) entries; DECISIONLOG entries note which version they affect.

Contributions are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md).

## Testing

Unit tests use [bats-core](https://github.com/bats-core/bats-core). Install it once:

```bash
git clone --depth=1 https://github.com/bats-core/bats-core test/libs/bats-core
```

Then run:

```bash
test/libs/bats-core/bin/bats test/unit.bats
```

Tests cover `_validate_memory/cpus/pids/network_mode`, the `_build_extra_docker_args` allowlist, and the `-n`/`-a` flag parser. Docker is mocked via `test/helpers/` — no running daemon required. `test/libs/` is gitignored.

---

## Upgrading

```bash
faradai update
```

Clones the latest commit from GitHub over HTTPS (no SSH key required), rebuilds the image, and reinstalls the CLI binary. The running container is not affected until the next launch.

**Updating pinned tool versions:** `@anthropic-ai/claude-code` and `aider-chat` are pinned in the Dockerfile. To update them, edit the version strings in the `RUN npm install` and `pipx install` lines and rebuild.

---

## Aider configuration

Aider reads `~/.aider.conf.yml` on startup. The relevant section for OpenRouter:

```yaml
model: openrouter/<provider>/<model>
api-key: openrouter=<your-key>
```

Use the model slug from OpenRouter's model directory. The `openrouter/` prefix is required by LiteLLM for provider routing. Because the file is mounted `:ro`, config changes must be made on the host, not from inside the container.

## Known issues and limitations

**Docker filesystem I/O overhead**
All file reads and writes go through Docker's overlay filesystem, which adds latency compared to native disk access. For most coding tasks this is imperceptible, but large `find` scans, heavy test suites writing many files, or build systems that hash large trees may be noticeably slower inside the container than on the host.

**No GPU passthrough**
The container runs with `--cap-drop ALL` and no `--device` flags by default. GPU access (e.g. for local model inference alongside the agent) requires `FARADAI_ALLOW_DEVICE=1` and the appropriate `--device` flag in `FARADAI_DOCKER_ARGS`. There is no first-class GPU profile yet.

**Local LSP limitations**
Language servers that rely on system-wide installations (e.g. a globally installed `pylsp` or `clangd`) will not be present inside the container unless they are added to the Dockerfile. LSPs that install into the project (e.g. via `npm install` or a virtualenv) work fine.

**Multi-user `docker rm` behavior**
`faradai` calls `docker rm -f faradai` before each new launch to clear any stopped container. On a shared machine where multiple users might run faradai containers, this could remove another user's stopped container if container names collide. Use `-n NAME` to give each session a unique name.

---

## Future work

The container pattern here is not specific to Claude Code or aider — any CLI-based AI coding agent can be dropped in by adding it to the Dockerfile and a mode to `entrypoint.sh`. If the project grows to justify the work, candidates include Goose, OpenHands, and others in the space. Contributions welcome if there's demand.

