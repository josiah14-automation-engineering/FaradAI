# FaradAI — Claude Code Container

Start repository work at [AGENTS.md](AGENTS.md), then read the documents it
routes to for the current task. Return to that index whenever the task changes
scope or reaches an architecture, security, style, or verification decision.

You are running inside a FaradAI container. The filesystem boundary is intentional and enforced at the OS level.

## Filesystem ceiling

`~/Development/personal` is the project search root and the only mounted host
project tree. It maps directly to the same path on the host machine. Other
explicit configuration and credential mounts are listed in `README.md`; they
are not general search space.

**Never search above this directory.** Do not walk up toward `/home`, `/root`, or any other path outside the mount. When you need to find a file and the path is unknown, search from `.` or ask.

**Do not inspect or modify system paths** such as `/etc`, `/root`, `/usr`, or
`/var`. Do not search explicit host configuration mounts; inspect a non-secret
configuration file only when the task requires it. The filesystem mounts are
the primary boundary; these rules are a second layer.

**Do not read credential files.** This includes
`~/.claude/.credentials.json`, `~/.codex/auth.json`,
`~/.aider/oauth-keys.env`, `~/.local/share/opencode/auth.json`, and GitHub or
SSH credentials. Reading one — even incidentally during debugging — can send
the secret to the model provider as conversation context. Aider's
`~/.aider.conf.yml` and `~/.aider.model.settings.yml` contain model selection,
not credentials, and are safe to inspect when relevant.

## What is available

- All projects under `~/Development/personal`
- `~/.claude` — settings and memory; do not inspect its credential file
- Python 3 and pip — available for intermediate scripting tasks
- git, curl, Node.js

## What is not available

Host files not explicitly listed in the `README.md` mount table are unavailable.
This is by design.

## Git tools

Prefer atomic, well-scoped commits. Use `git add -p` to stage individual hunks when a file contains multiple unrelated changes — this keeps commits clean without needing to branch or stash.

For moving specific commits between branches: `git cherry-pick <sha>` applies a commit onto the current branch as a new commit. Add `-x` to record the source SHA in the commit message.

For exporting commits as files: `git format-patch` produces `.patch` files (one per commit) that can be applied elsewhere with `git am`, which preserves author and commit message. `git apply` applies the diff only, without committing.

## Collaboration

Follow the role, change-authority, mentoring, and collaboration rules in
[AGENT_WORKFLOW.md](AGENT_WORKFLOW.md).
