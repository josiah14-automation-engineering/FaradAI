# FaradAI — Open Items

## Code quality

**Add `gh` (GitHub CLI) to the image** [LOW]
`gh` is not present in the container, requiring GitHub operations (e.g. creating issues) to be run from the host. Add `gh` to the final-stage apt install block.

---

## Pre-open-source: community scaffolding

CONTRIBUTING.md, GitHub issue/PR templates, and a basic CI pipeline (shellcheck, hadolint, docker build smoke test). Deferred until the project is closer to publishing — premature for a personal tool in active development.
