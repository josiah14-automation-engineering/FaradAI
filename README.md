# FaradAI

A Docker container for running Claude Code with a hard filesystem boundary. Named after the Faraday cage: the AI inside has full capability, but can only reach what you explicitly mount.

## Prerequisites

- Docker
- A Claude Code login session on the host (`claude login` — credentials are stored in `~/.claude`)

## Build

```bash
./build.sh
```

This builds the `faradai:latest` image using your host user's username, UID, and GID. No personal information is hardcoded.

## Run

```bash
./run.sh
```

This launches an interactive Claude Code session inside the container. Two directories from your host are mounted:

| Host | Container | Purpose |
|------|-----------|---------|
| `~/.claude` | `~/.claude` | Login credentials, settings, memory |
| `~/Development/personal` | `~/Development/personal` | Your project files |

The working directory is set to `~/Development/personal`, mirroring your host layout so paths behave identically inside and outside the container.

## What's in the image

- Ubuntu 24.04
- Node.js + npm
- Claude Code CLI (`claude`)
- Python 3 + pip
- git, curl

## Why

Claude Code has access to shell tools including filesystem search. Running it in a container with a scoped mount means the filesystem boundary is enforced at the OS level rather than relying on behavioral constraints.
