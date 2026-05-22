# Changelog

All notable user-facing changes to FaradAI are documented here. For architectural reasoning behind decisions, see [DECISIONLOG.md](DECISIONLOG.md).

---

## [Unreleased]

## [0.1.0] — 2026-05-22

Initial release. Core features:

- `faradai` CLI — runs Claude Code and aider in a sandboxed Docker container with an OS-level filesystem boundary
- Subcommands: `claude`, `aider`, `bash`, `logs`, `status`, `version`, `update`, `uninstall`
- Resource limits: `FARADAI_MEMORY`, `FARADAI_CPUS`, `FARADAI_PIDS`
- Network control: `FARADAI_NETWORK_MODE=open|none`
- SSH agent forwarding with confirmation prompt
- `faradai update` pulls the latest tagged release with integrity verification; `--branch NAME` for pre-release testing
- `shellcheck` v0.11.0 included in the image
- 43 unit tests (bats)
