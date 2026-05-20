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

AI coding assistants scan broadly by default. FaradAI constrains the agent's filesystem access to only the projects you mount — a hard OS-level boundary, not a behavioral guideline.

A Docker container for running Claude Code and aider. Named after the Faraday cage: the AI inside has full capability, but can only reach what you explicitly mount.

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

If no container is running, starts a new one and launches Claude Code (default). If a container named `faradai` is already running, attaches to it instead via `docker exec`.

This means you can open as many terminals as you like — tmux panes, terminal emulator splits, separate windows — and each one that runs `faradai <tool>` will land inside the same container.

### Modes

An optional argument selects which tool to launch (or attach to):

| Command | Result |
|---------|--------|
| `faradai` | Claude Code (default) |
| `faradai aider` | aider |
| `faradai bash` | bare shell, useful for debugging |
| `faradai update` | pull latest release from GitHub and reinstall |
| `faradai uninstall` | remove the container, image, and installed binaries |

### Resource limits

`faradai` reads three environment variables to set container resource limits, with sensible defaults if unset:

| Variable | Default | Controls |
|----------|---------|----------|
| `FARADAI_WORKDIR` | `~/Development/personal` | project directory mounted and used as working dir |
| `FARADAI_MEMORY` | `4g` | `--memory` — max RAM |
| `FARADAI_CPUS` | `4` | `--cpus` — max CPU cores |
| `FARADAI_PIDS` | `512` | `--pids-limit` — max process count |

Override inline:
```bash
FARADAI_WORKDIR=~/projects FARADAI_MEMORY=8g FARADAI_CPUS=8 faradai
```

Or set permanently in your shell rc file (`~/.bashrc`, `~/.zshrc`, etc.):
```sh
export FARADAI_WORKDIR=~/Development/personal
export FARADAI_MEMORY=4g
export FARADAI_CPUS=4
export FARADAI_PIDS=512
```

`faradai` also uses `$HOME` and `$USER` for mount paths — these are standard shell variables set automatically by your shell and require no configuration.

### Mounts

| Host | Container | Mode | Required for |
|------|-----------|------|--------------|
| `~/.claude/` | `~/.claude/` | read-write | Claude Code — settings, memory, conversation history |
| `~/.claude/.credentials.json` | `~/.claude/.credentials.json` | read-only | Claude Code — OAuth token, overlaid `:ro` on top of the directory mount to protect it from writes |
| `~/.claude.json` | `~/.claude.json` | read-write | Claude Code — top-level config file (sibling to `~/.claude/`, not inside it) |
| `~/.aider.conf.yml` | `~/.aider.conf.yml` | read-only | Aider — config and OpenRouter API key; `:ro` keeps the key out of agent write access (skipped if file does not exist on host) |
| `~/.gitconfig` | `~/.gitconfig` | read-only | git commits — author identity |
| `~/.ssh/` | `~/.ssh/` | read-only | SSH key files for SSH-based git remotes |
| `$FARADAI_WORKDIR` | `$FARADAI_WORKDIR` | read-write | Your project files — the primary work surface |

The working directory defaults to `~/Development/personal`, mounted at the same path inside the container so all project-relative references, memory files, and tooling behave identically inside and outside.

> **SSH agent forwarding:** `SSH_AUTH_SOCK` is not forwarded into the container. If you rely on an ssh-agent rather than key files directly, git over SSH will not work inside the container. HTTPS remotes are unaffected.

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
- Networking tools: `ping`, `netstat`/`ifconfig` (`net-tools`), `ip`/`ss` (`iproute2`), `dig`/`nslookup` (`dnsutils`), `nc` (`netcat-openbsd`)

## Security model

**The Faraday cage protects the filesystem boundary, not the process environment.**

Credentials are kept out of environment variables and injected as mounted files instead:

- Claude Code: OAuth token in `~/.claude/.credentials.json` (`:ro` overlay)
- Aider: API key in `~/.aider.conf.yml` (`:ro`)

Any secret present as an environment variable is visible to the agent and will appear in tool output if commands like `env` are run. Prefer file-based credential delivery. If a key must be in the environment, scope it to a cost-limited key with a short rotation cycle.

**The `:ro` mount on `~/.aider.conf.yml` is not a secrecy mechanism.** The agent can read the file directly if instructed to — for example, if you ask it to debug an aider configuration issue. If it does, the key will be transmitted to Anthropic's servers as part of the conversation context. This is a calculated risk: scope your OpenRouter key to a hard cost limit so that any exposure has a bounded blast radius.

### Network access

The container has unrestricted outbound network access. This is intentional: the agent may need to reach arbitrary sources — documentation, APIs, package registries — and restricting outbound would require predicting that in advance, which defeats the purpose of a general-purpose coding assistant.

The container can also reach services running on the host via the Docker bridge gateway. This too is intentional — useful for workflows involving local k3s clusters, development servers, or other host-side services you want the agent to interact with.

The meaningful protection is the absence of the Docker socket. Without `/var/run/docker.sock` mounted, the agent cannot escape the container by spawning new containers with unrestricted host mounts. That is the primary container escape vector, and it is not present here.

### Capabilities and privilege escalation

`--cap-drop ALL` removes Docker's default capability set (~14 caps, including `NET_RAW` and `SYS_CHROOT`). `--security-opt no-new-privileges` sets `prctl PR_SET_NO_NEW_PRIVS`, preventing any process in the container from gaining privileges via setuid binaries or filesystem capabilities. Use `--cap-add` if a specific tool needs a capability back.

## Troubleshooting

**Docker permission denied**
Your user is not in the `docker` group. Fix: `sudo usermod -aG docker $USER`, then log out and back in.

**Credential errors on first launch**
`~/.claude/.credentials.json` is missing or expired. Run `claude login` on the host to refresh it, then relaunch.

**Container name conflict (`faradai` already in use)**
A stopped container is holding the name. The `faradai` script handles this automatically via `docker rm -f faradai` before each new launch. If it persists: `docker rm -f faradai` manually.

**SSH key permissions rejected**
SSH requires key files to be `600`. Fix: `chmod 600 ~/.ssh/id_*`.

**aider not found inside the container**
The image predates the least-privilege install fix (Session 7). Rebuild: `./build.sh && ./install.sh`.

**Wrong model slug in `~/.aider.conf.yml`**
aider / LiteLLM requires the `openrouter/` provider prefix. Correct format: `model: openrouter/<provider>/<model>`. Edit the file on the host (it is mounted `:ro` inside the container).

**`gh` not authenticated inside the container**
`gh` requires manual login after each fresh install. Run `gh auth login` from inside the container (or via `faradai bash`) and follow the device-code flow. This is a known gap — credential passthrough for `gh` is not yet implemented.

---

## Upgrading

```bash
faradai update
```

Clones the latest release from GitHub, rebuilds the image, and reinstalls the CLI binary. The running container is not affected until the next launch.

**Updating pinned tool versions:** `@anthropic-ai/claude-code` and `aider-chat` are pinned in the Dockerfile. To update them, edit the version strings in the `RUN npm install` and `pipx install` lines and rebuild.

---

## Aider configuration

Aider reads `~/.aider.conf.yml` on startup. The relevant section for OpenRouter:

```yaml
model: openrouter/<provider>/<model>
api-key: openrouter=<your-key>
```

Use the model slug from OpenRouter's model directory. The `openrouter/` prefix is required by LiteLLM for provider routing. Because the file is mounted `:ro`, config changes must be made on the host, not from inside the container.

## Future work

The container pattern here is not specific to Claude Code or aider — any CLI-based AI coding agent can be dropped in by adding it to the Dockerfile and a mode to `entrypoint.sh`. If the project grows to justify the work, candidates include Goose, OpenHands, and others in the space. Contributions welcome if there's demand.

