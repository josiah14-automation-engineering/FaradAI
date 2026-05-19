# FaradAI — Open Items

## Pre-open-source: community scaffolding

CONTRIBUTING.md, GitHub issue/PR templates, and a basic CI pipeline (shellcheck, hadolint, docker build smoke test). Deferred until the project is closer to publishing — premature for a personal tool in active development.

---

## Network access — acknowledged risk

The container has unrestricted outbound network access. A compromised agent could exfiltrate anything it can read. Options: `--network=none` with explicit allowances, a proxy layer, or prominent documentation of the risk. Currently documented in the security model section of the README. Revisit before publishing if a stronger posture is desired.
