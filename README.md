# FaradAI

A Docker container for running Claude Code (and aider) with a hard filesystem boundary. Named after the Faraday cage: the AI inside has full capability, but can only reach what you explicitly mount.

## Prerequisites

- Docker
- A Claude Code login session on the host (`claude login` — credentials live in `~/.claude/`)
- An `~/.aider.conf.yml` on the host with your OpenRouter API key (for aider)

## Build

```bash
./build.sh
```

Builds `faradai:latest` using your host user's username, UID, and GID — derived at runtime, nothing hardcoded.

## Run

```bash
./run.sh
```

Launches an interactive Claude Code session inside the container.

### Modes

An optional argument selects which tool to launch:

| Command | Result |
|---------|--------|
| `./run.sh` | Claude Code (default) |
| `./run.sh aider` | aider |
| `./run.sh tmux` | tmux split — Claude Code left, aider right |
| `./run.sh bash` | bare shell, useful for debugging |

### Resource limits

`run.sh` reads three environment variables to set container resource limits, with sensible defaults if unset:

| Variable | Default | Controls |
|----------|---------|----------|
| `FARADAI_MEMORY` | `4g` | `--memory` — max RAM |
| `FARADAI_CPUS` | `4` | `--cpus` — max CPU cores |
| `FARADAI_PIDS` | `512` | `--pids-limit` — max process count |

Override inline:
```bash
FARADAI_MEMORY=8g FARADAI_CPUS=8 ./run.sh
```

Or set permanently in your shell rc file (`~/.zshrc`, `~/.bashrc`, etc.):
```sh
export FARADAI_MEMORY=4g
export FARADAI_CPUS=4
export FARADAI_PIDS=512
```

`run.sh` also uses `$HOME` and `$USER` for mount paths — these are standard shell variables set automatically by your shell and require no configuration.

### Mounts

| Host | Container | Mode | Required for |
|------|-----------|------|--------------|
| `~/.claude/` | `~/.claude/` | read-write | Claude Code — settings, memory, conversation history |
| `~/.claude/.credentials.json` | `~/.claude/.credentials.json` | read-only | Claude Code — OAuth token, overlaid `:ro` on top of the directory mount to protect it from writes |
| `~/.claude.json` | `~/.claude.json` | read-write | Claude Code — top-level config file (sibling to `~/.claude/`, not inside it) |
| `~/.aider.conf.yml` | `~/.aider.conf.yml` | read-only | Aider — config and OpenRouter API key; `:ro` keeps the key out of agent write access |
| `~/.gitconfig` | `~/.gitconfig` | read-only | git commits — author identity |
| `~/.ssh/` | `~/.ssh/` | read-only | SSH-based git remotes (optional if you only use HTTPS) |
| `~/.tmux.conf` | `~/.tmux.conf` | read-only | tmux — user config (skipped if file does not exist on host) |
| `~/.tmux/plugins/` | `~/.tmux/plugins/` | read-write | tmux — TPM plugin installations; read-write so TPM can install plugins (skipped if directory does not exist on host) |
| `~/Development/personal` | `~/Development/personal` | read-write | Your project files — the primary work surface |

The working directory is `~/Development/personal`, matching the host path exactly so all project-relative references, memory files, and tooling behave identically inside and outside the container.

Credentials are delivered as mounted files rather than environment variables — any secret in the environment will appear in tool output if `env` is inspected. See [Security model](#security-model).

## What's in the image

- Ubuntu 24.04
- Node.js — runtime for Claude Code (npm not included; tools are pre-installed in the image)
- Claude Code CLI (`claude`)
- aider (via pipx venv, pre-installed)
- Python 3 + pip + venv — available for intermediate scripting tasks
- git, curl
- tmux (for backgrounding aider sessions alongside Claude Code)
- vim — available when shelling in for manual edits or troubleshooting
- Networking tools: `ping`, `netstat`/`ifconfig` (`net-tools`), `ip`/`ss` (`iproute2`), `dig`/`nslookup` (`dnsutils`), `nc` (`netcat-openbsd`)
- tmux plugin dependencies: `xclip`, `xsel` (X11 clipboard — used by tmux-yank and clipboard keybindings), `fzf` (fuzzy finder — used by session switcher plugins)

### tmux plugin support

`~/.tmux.conf` and `~/.tmux/plugins/` are mounted from the host if they exist, so your tmux config and TPM plugin state carry over into the container. The image includes the system dependencies needed by the most common TPM plugins.

Plugins with no system dependencies (tmux-sensible, tmux-resurrect, tmux-continuum, tmux-pain-control, tmux-open, tmux-copycat, tmux-powerline) work out of the box. Clipboard plugins (tmux-yank) work via `xclip`/`xsel`. `fzf`-based plugins work via the bundled `fzf`.

**Unsupported dependencies are the user's problem.** If your config requires tools not in the image (e.g., `wl-clipboard` for Wayland, nerd fonts, custom status bar binaries), those won't be available inside the container and the relevant config lines will silently fail or error. The fix is to extend the image with your own `Dockerfile` that builds `FROM faradai:latest` and adds what you need.

## Security model

**The Faraday cage protects the filesystem boundary, not the process environment.**

Credentials are kept out of environment variables and injected as mounted files instead:

- Claude Code: OAuth token in `~/.claude/.credentials.json` (`:ro` overlay)
- Aider: API key in `~/.aider.conf.yml` (`:ro`)

Any secret present as an environment variable is visible to the agent and will appear in tool output if commands like `env` are run. Prefer file-based credential delivery. If a key must be in the environment, scope it to a cost-limited key with a short rotation cycle.

## Aider configuration

Aider reads `~/.aider.conf.yml` on startup. The relevant section for OpenRouter:

```yaml
model: openrouter/inclusionai/ring-2.6-1t
api-key: openrouter=<your-key>
```

The `openrouter/` prefix is required by LiteLLM for provider routing. Because the file is mounted `:ro`, config changes must be made on the host, not from inside the container.

