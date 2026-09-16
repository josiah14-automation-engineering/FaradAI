# Agent Documentation Index

Use this file as the repository map, not a handbook. Read it before starting
work. Return when the task changes scope, before making architecture, security,
style, or verification decisions, and whenever the source of truth is unclear.
Then read only the documents relevant to the task.

## Required guidance

| When | Read | Main topics |
|---|---|---|
| Before any repository work | [AGENT_WORKFLOW.md](AGENT_WORKFLOW.md) | Expert-mentor role, change authority, teaching, collaboration, research, documentation maintenance |
| When Claude Code is running inside FaradAI | [CLAUDE.md](CLAUDE.md) | Filesystem ceiling, secret files, available tools, Git practices, repository-document routing |

## Work by area

| When | Read | Main sections or topics |
|---|---|---|
| Understanding current behavior or user-facing architecture | [README.md](README.md) | Platform support, installation, modes, configuration, mounts, agent setup, security model, troubleshooting, development, testing, upgrades, limitations |
| Changing Go | [GO_STYLE_GUIDE.md](GO_STYLE_GUIDE.md) | Tooling, packages, naming, control flow, FaradAI boundaries, executable specifications, Go tests |
| Changing Elvish | [ELVISH_STYLE_GUIDE.md](ELVISH_STYLE_GUIDE.md) | Structure, command resolution, values, functions, failure handling, portability, security, verification |
| Changing the image or Podman/OCI behavior | [CONTAINER_STYLE_GUIDE.md](CONTAINER_STYLE_GUIDE.md) | Build context, Containerfile construction, metadata, users, runtime policy, portability, verification |
| Preparing a contribution | [CONTRIBUTING.md](CONTRIBUTING.md) | Scope, development environment, branches, checks, testing, pull requests |
| Verifying a built image manually | [SMOKETEST.md](SMOKETEST.md) | Tool versions, mounts, confinement, resource limits, authentication, SSH, aider round-trip |
| Understanding why an architectural or security choice exists | [DECISIONLOG.md](DECISIONLOG.md) | Build reproducibility, runtime lifecycle, credentials, mounts, integrations, language/runtime migration, agent governance |
| Looking for prior experiments, failures, or lessons learned | [BUILDLOG.md](BUILDLOG.md) | Initial design, hardening, reviews, testing, releases, Nix investigation, IDE research, ARM64, Go/Elvish/Podman migration |
| Choosing or scoping future work | [ROADMAP.md](ROADMAP.md) | Platform support, current work, post-migration work, deferred and rejected work, research |
| Checking released behavior | [CHANGELOG.md](CHANGELOG.md) | User-facing additions, changes, fixes, security notes by release |
| Reviewing historical shell findings | [ring-review.md](ring-review.md) | Architecture, shell style, correctness findings; historical context, not current authority |

If documents disagree, verify current behavior in code and tests, then consult
`DECISIONLOG.md` for intent. Update the stale document with the same change.
