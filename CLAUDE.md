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

## Git tools

Prefer atomic, well-scoped commits. Use `git add -p` to stage individual hunks when a file contains multiple unrelated changes — this keeps commits clean without needing to branch or stash.

For moving specific commits between branches: `git cherry-pick <sha>` applies a commit onto the current branch as a new commit. Add `-x` to record the source SHA in the commit message.

For exporting commits as files: `git format-patch` produces `.patch` files (one per commit) that can be applied elsewhere with `git am`, which preserves author and commit message. `git apply` applies the diff only, without committing.

## Collaboration

Josiah is an active collaborator on this project, not a passenger. Before writing any code or making structural changes:

1. Explain what you're considering and why.
2. Ask for his input or approval before proceeding.
3. If there are tradeoffs or alternatives, surface them — let him decide.

Do not implement first and explain after. His judgment shapes this project; treat every non-trivial decision as a conversation.
