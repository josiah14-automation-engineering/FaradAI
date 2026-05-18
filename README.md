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

Launches an interactive Claude Code session inside the container. To run aider instead:

```bash
./run.sh aider
```

Any arguments passed to `run.sh` replace the default `claude` entrypoint.

### Mounts

| Host | Container | Mode | Purpose |
|------|-----------|------|---------|
| `~/.claude/` | `~/.claude/` | read-write | Settings, memory, conversation history |
| `~/.claude/.credentials.json` | `~/.claude/.credentials.json` | read-only | OAuth token — overlaid `:ro` on top of the directory mount |
| `~/.claude.json` | `~/.claude.json` | read-write | Claude Code config file |
| `~/.aider.conf.yml` | `~/.aider.conf.yml` | read-only | Aider config including OpenRouter API key |
| `~/.gitconfig` | `~/.gitconfig` | read-only | Git identity |
| `~/Development/personal` | `~/Development/personal` | read-write | Your project files |

The working directory is `~/Development/personal`, matching the host path exactly so all project-relative references work identically inside and outside the container.

### Resource limits

`run.sh` applies `--memory=4g` and `--cpus=4` to bound what the container can consume.

## What's in the image

- Ubuntu 24.04
- Node.js + npm
- Claude Code CLI (`claude`)
- aider (via pipx)
- Python 3 + pip + venv
- git, curl
- tmux (for backgrounding aider sessions alongside Claude Code)

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

## Open items

| # | Severity | Issue |
|---|----------|-------|
| 1 | Medium | No `.dockerignore` — build context may include `~/.claude/` and other sensitive dirs |
| 2 | Medium | No version pinning on `claude-code` and `aider-chat` — rebuild results may drift |
| 3 | Low | SSH key not mounted — SSH-based git remotes will fail |
| 4 | Low | No `ENTRYPOINT` in Dockerfile — runtime command supplied entirely by `run.sh` |
| 5 | Low | `sudo` not explicitly removed from the image |
