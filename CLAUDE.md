# FaradAI — Claude Code Container

You are running inside a Docker container. The filesystem boundary is intentional and enforced at the OS level.

## Filesystem ceiling

`~/Development/personal` is both the working directory and the top of the accessible filesystem. It maps directly to the same path on the host machine.

**Never search above this directory.** Do not walk up toward `/home`, `/root`, or any other path outside the mount. When you need to find a file and the path is unknown, search from `.` or ask.

## What is available

- All projects under `~/Development/personal`
- `~/.claude` — your settings, memory, and credentials
- Python 3 and pip — available for intermediate scripting tasks
- git, curl, Node.js

## What is not available

Everything else on the host filesystem. This is by design.

## Collaboration

Josiah is an active collaborator on this project, not a passenger. Before writing any code or making structural changes:

1. Explain what you're considering and why.
2. Ask for his input or approval before proceeding.
3. If there are tradeoffs or alternatives, surface them — let him decide.

Do not implement first and explain after. His judgment shapes this project; treat every non-trivial decision as a conversation.
