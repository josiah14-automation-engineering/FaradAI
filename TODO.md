# FaradAI — Open Items

## Documentation

**Troubleshooting section in README** [MEDIUM]
Common failure modes — Docker permission denied, credential errors, SSH forwarding limitations, container name conflicts — have no documented resolution path.

**Upgrade/update instructions** [MEDIUM]
Users with an existing installation have no documented path to update the image or the `faradai` CLI script.

---

## Code quality

**Add `gh` (GitHub CLI) to the image** [LOW]
`gh` is not present in the container, requiring GitHub operations (e.g. creating issues) to be run from the host. Add `gh` to the final-stage apt install block.

---

## Pre-open-source: community scaffolding

CONTRIBUTING.md, GitHub issue/PR templates, and a basic CI pipeline (shellcheck, hadolint, docker build smoke test). Deferred until the project is closer to publishing — premature for a personal tool in active development.
