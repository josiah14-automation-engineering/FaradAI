# FaradAI Build Log

---

## Session 1 — 2026-05-11

### Motivation

Josiah observed that a prior Claude Code session had invoked `find ~`, scanning broadly across his home directory. He identified this as an unacceptable intrusion and decided the correct architectural response was to run Claude Code inside a Docker container with only the relevant project directory mounted — creating a hard filesystem boundary rather than relying on behavioral constraints alone.

### Naming

Rather than a generic name like `containerized-ai`, Josiah proposed **FaradAI** — a portmanteau of *Faraday cage* (electromagnetic isolation) and *AI*. The analogy is precise: a Faraday cage doesn't weaken the signal inside, it constrains what can escape or be reached from outside. Directory name: `faradai`.

### Base Image & Dockerfile

- Base image: `ubuntu:24.04`, consistent with the `docker-emacs` 30.2 images in this repo.
- **Josiah caught** that Ubuntu 24.04 ships with a default `ubuntu` user at UID/GID 1000, which would clash when creating a host-mirrored user. He directed adding explicit `userdel`/`groupdel` cleanup before the new user is created.
- **Josiah directed** including Python 3 and pip, anticipating that Claude Code may invoke Python for intermediate tasks (data manipulation, scripting, etc.).

### Mount Layout

Initial plan used a generic `/workspace` mount. **Josiah redirected** this to mirror the host machine's actual layout: `~/Development/personal` mounted to the same path inside the container. This means project-relative paths, memory references, and tooling all behave identically inside and outside the container.

### Build Script

**Josiah specified** that `build.sh` must not hardcode any personal information (username, UID, GID). The script derives all three at runtime via `$(whoami)`, `$(id -u)`, and `$(id -g)`, making it portable to any host user without modification.

### Authentication

Josiah questioned how to auto-provide the Anthropic API key, noting he had logged in via `claude login` rather than setting an environment variable. Investigation confirmed that `claude login` stores OAuth credentials in `~/.claude/.credentials.json`. Since `run.sh` already mounts `~/.claude` into the container, authentication is inherited automatically — no API key env var is needed. The `-e ANTHROPIC_API_KEY` line was removed from `run.sh`.

---

## First Successful Run — 2026-05-11

Josiah confirmed Claude Code running inside the container. The filesystem boundary, user identity mirroring, `~/.claude` credential passthrough, and `~/Development/personal` mount all functioned as designed on the first attempt.

---

## Session 2 — 2026-05-13

### Aider Integration

Josiah added `aider` to the container and configured it with an OpenRouter API key (`OPENROUTER_API_KEY` env var), giving the container a second AI coding tool alongside Claude Code. Aider was confirmed functional via a smoke test against `openrouter/anthropic/claude-3-haiku`, which returned a response and cost breakdown on the first attempt.

### Memory Passthrough Confirmed

**Josiah verified** that the `~/.claude` mount carries not just credentials but also the full persistent memory system (`~/.claude/projects/.../memory/`). Memory files written in prior sessions are accessible inside the container, meaning context and collaboration preferences persist across container restarts without any additional mounting or configuration.

### Ring-2.6-1T Code Review

Ring-2.6-1T (via aider/OpenRouter) reviewed the FaradAI project files and produced a prioritized issue table. The high-severity finding was a security inconsistency: `run.sh` passes `OPENROUTER_API_KEY` as an environment variable despite the BUILDLOG explicitly documenting that env vars are visible to the agent. Additional findings covered `.dockerignore` absence, version pinning, resource limits, and minor shell style.

**Josiah reviewed the findings and accepted the env var exposure as a known tradeoff.** The `OPENROUTER_API_KEY` carries a hard cost limit, making the blast radius of any leak bounded and tolerable. The risk is acknowledged, not overlooked.

---

---

## Session 3 — 2026-05-18

### Fix: Missing `.claude.json` Mount

Claude Code reported "configuration file not found at `/home/josiah/.claude.json`" on container startup. **Josiah identified** that `run.sh` mounted `~/.claude/` (the directory) but not `~/.claude.json` (a sibling file at the same level). The two are distinct filesystem objects; mounting the directory does not capture the file beside it. The fix was a one-line addition to `run.sh`.

### Aider Credential Hardening

**Josiah directed** replacing the `-e OPENROUTER_API_KEY` environment variable with a file-based approach, mirroring how Claude Code credentials are handled via the `~/.claude` mount. Aider reads `~/.aider.conf.yml` natively; the key is stored there on the host and mounted read-only into the container. The `-e OPENROUTER_API_KEY` line and its `pass` invocation were removed from `run.sh` entirely.

This closes the env-var exposure vector documented in Session 2. The key is still technically file-readable if the agent looks directly at `~/.aider.conf.yml`, but it will no longer surface through incidental `env` output or tool call logging.

---

### Lesson: Environment Variables Are Not Secret from the Agent

During the aider smoke test, a broad `env | grep` command was used to check for relevant API keys. The full `OPENROUTER_API_KEY` value appeared in the tool output and was transmitted to Anthropic's servers as part of the conversation context. The key had a cost limit, so exposure was low-risk, but the pattern is worth noting.

**The Faraday cage protects the filesystem boundary, not the process environment.** Any secret present as an environment variable is visible to the agent and will be transmitted if it appears in tool output. Mitigations:

- Scope `env` greps to exactly the variable name you intend to expose.
- Keep secrets out of the container environment entirely when possible (e.g., inject only at the point of use, or store outside the mount).
- Prefer keys with tight cost limits and short rotation cycles for anything used inside AI coding sessions.

---

### Smoke Test: Credential Hardening (cont.)

Testing the `~/.aider.conf.yml` approach revealed a configuration error: the file used `openrouter-api-key` as the key name, which aider does not recognize. The correct format is `api-key: openrouter=<key>`, corresponding to aider's `--api-key PROVIDER=KEY` flag.

**Josiah caught** that reading `~/.aider.conf.yml` to diagnose the issue would transmit the API key to Anthropic's servers — the same exposure vector the file-based approach was designed to avoid. He redirected to a manual fix instead.

Note: the API key also appeared in tool output during the smoke test (`aider: error: unrecognized arguments: --openrouter-api-key=<key>`), demonstrating again that secrets surfacing in command output are captured in context regardless of how they entered the environment.

### Ring-2.6-1T Model Slug

OpenRouter model slug for Ring-2.6-1T confirmed: `openrouter/inclusionai/ring-2.6-1t`. Josiah looked this up directly on the OpenRouter model directory.

---

## Session 4 — 2026-05-18

### Aider Smoke Test (Session 3 cont.)

Aider re-tested after Josiah manually applied the `~/.aider.conf.yml` credential fix from Session 3. Test confirmed clean: Ring-2.6-1T responded via aider with no credential errors and no key exposure in output. File-based credential approach working as intended.

### Persistent Ring Session — tmux

Josiah proposed using aider to hold an interactive Ring-2.6-1T session in the background, enabling live comparison between Anansi and Ring on coding questions. The approach: start aider in a background tmux pane, communicate via `tmux send-keys` and `tmux capture-pane`.

`which tmux` confirmed tmux is not present in the container. **Josiah directed** adding it to the Dockerfile. Added `tmux` to the `apt-get install` block — one-line change, rebuild required.

---

## Session 5 — 2026-05-18

### Aider tmux Smoke Test

After rebuild, aider launched successfully in a detached tmux session. First real call to Ring-2.6-1T via the tmux pane failed with:

```
litellm.BadRequestError: LLM Provider NOT provided. You passed model=inclusionai/ring-2.6-1t
```

The model slug in `~/.aider.conf.yml` was `inclusionai/ring-2.6-1t` — missing the `openrouter/` provider prefix that LiteLLM requires for routing. The correct slug is `openrouter/inclusionai/ring-2.6-1t`. Because `~/.aider.conf.yml` is mounted `:ro`, the fix cannot be applied from inside the container; it must be made on the host. Worked around mid-session via `/model openrouter/inclusionai/ring-2.6-1t` inside aider.

This exposes a gap: `:ro` mounts protect credentials from agent writes but also block legitimate config corrections. The host-side fix to `~/.aider.conf.yml` is pending.

### Ring Analysis of FaradAI

With the model slug corrected, Ring-2.6-1T analyzed the FaradAI project files via the tmux aider session. Ring confirmed the core design is sound and flagged several improvement areas (detailed findings in ring-feedback.md if recorded). Key issues surfaced:

- Inconsistent mount modes: `~/.aider.conf.yml` `:ro` but `~/.claude` and `~/.claude.json` read-write
- No `.dockerignore`
- Hardcoded resource limits in `run.sh`
- No image versioning strategy

### `.credentials.json` Read-Only Overlay

Ring's mount inconsistency observation prompted a targeted fix. Josiah scoped the problem: `~/.claude` needs to remain read-write so the agent can update memory, history, and settings — but `~/.credentials.json` (the OAuth token) within it should be protected from writes.

Docker allows a more-specific volume mount to overlay a broader one. **Josiah directed** adding a second `-v` line mounting `~/.claude/.credentials.json` as `:ro` on top of the read-write `~/.claude` mount. The more specific path wins in Docker's mount resolution, giving per-file granularity without splitting the directory mount.

---

## Session 6 — 2026-05-19

### README Brought Current

The README had not been updated since Session 1 and was significantly behind: it listed only two mounts, made no mention of aider or tmux, and had no security or credential documentation. The README was rewritten to reflect the full mount table (all six mounts with modes and purposes), current tooling list, resource limits, the file-based credential model, and an aider config example with the correct model slug format. Open items from `ring-feedback.md` were consolidated into a table at the bottom.

### Closing All Open Items

All items from the `ring-feedback.md` priority table were addressed and committed individually:

**`.dockerignore`**
Added to exclude `.git`, `.aider.chat.history.md`, and documentation files from the build context sent to the Docker daemon.

**Version pinning**
`@anthropic-ai/claude-code` pinned to `2.1.143` and `aider-chat` pinned to `0.86.2` — the current latest at time of session. Prevents build drift across rebuilds.

**`sudo` removal**
Added an explicit `apt-get purge --auto-remove sudo` before the `USER` directive. **Anansi caught** a bug in the initial placement: the purge had been inserted after `USER ${USERNAME}`, where it would run as non-root and silently fail. Corrected before commit.

**SSH support**
Added `openssh-client` to the `apt-get install` block and `-v "${HOME}/.ssh:/home/${USER}/.ssh:ro"` to `run.sh`. The key mount alone was insufficient — the SSH binary was also absent from the image.

**Entrypoint design — `claude/aider/tmux/bash` mode selector**

The `ENTRYPOINT` open item prompted a design discussion. Three approaches were surfaced:

- **A — status quo arg override:** `./run.sh` defaults to claude, `./run.sh aider` runs aider. Simple but offers no discovery.
- **B — interactive select menu:** wrapper script prompts if no arg given.
- **C — tmux split as default:** leans into the dual-tool intent; `./run.sh tmux` opens both tools side by side.

**Josiah accepted all three as valid modes** and directed that claude be the default when no argument is provided. Implemented as `entrypoint.sh` — a wrapper script copied into the image at `/usr/local/bin/entrypoint.sh` and set as `ENTRYPOINT`. Modes: `claude` (default), `aider`, `tmux` (split session, claude left / aider right), `bash`. `run.sh` was updated to pass `"$@"` through as-is; the default is now handled in the entrypoint rather than the shell script.

A hard `ENTRYPOINT ["claude"]` was rejected because it would have broken the multi-tool arg pattern — subsequent arguments would be passed to `claude` rather than selecting a different tool.

### Remaining Open Item

The `~/.aider.conf.yml` model slug fix (`inclusionai/ring-2.6-1t` → `openrouter/inclusionai/ring-2.6-1t`) remains a host-side fix. The file is mounted `:ro` and cannot be corrected from inside the container.

---

## Solo Fix — 2026-05-19

**Josiah independently identified and corrected** a permissions bug in `entrypoint.sh`: the script was being `COPY`'d into the image after the `USER` directive, meaning it landed owned by the non-root user and was not executable by root — making it unusable as an `ENTRYPOINT`. Josiah caught this, diagnosed it without AI assistance, and committed the fix directly. No session needed.

---

## Session 7 — 2026-05-19

### Bug: `aider: not found` at Runtime

On first launch of the rebuilt container, `./run.sh aider` failed with `/usr/local/bin/entrypoint.sh: line 9: exec: aider: not found`.

Root cause: `pipx install aider-chat==0.86.2` was running as root (before the `USER` directive), so pipx dropped the binary into `/root/.local/bin` rather than `/home/${USERNAME}/.local/bin` — the path the `ENV PATH` line points to. The binary was installed but unreachable by the non-root user at runtime.

### Least-Privilege Install for Both Tools

**Josiah questioned** why `npm install -g @anthropic-ai/claude-code` was still running as root when the same problem could apply. It can — global npm writes to system paths by default. Fix: configure npm to use a user-local prefix before installing.

Both tools now install after `USER ${USERNAME}`:

```dockerfile
RUN npm config set prefix "/home/${USERNAME}/.local"
RUN npm install -g @anthropic-ai/claude-code@2.1.143
RUN pipx install aider-chat==0.86.2
```

The `ENV PATH` line already includes `/home/${USERNAME}/.local/bin`, so both binaries are found without further changes. No root access required for either tool at install time. Rebuild required.

### Layer Consolidation

**Josiah independently consolidated** the remaining root-context `RUN` blocks: `userdel`/`groupdel`, `groupadd`/`useradd`, and the `mkdir`/`chown` for the mount point were merged into a single chained `RUN`. He also pulled the `sudo` purge up into the initial `apt-get` step rather than leaving it as its own layer. Result: fewer image layers, smaller image.

### Rebuild Confirmed

Rebuild succeeded. Both tools reachable at runtime. Current session is running from inside this image.

---

## Session 8 — 2026-05-19

### Multi-Stage Build

Converted the Dockerfile to a two-stage build to achieve clean layer separation between build-time and runtime concerns.

**Builder stage** runs as root throughout. Rather than creating a user, `HOME`, `PIPX_HOME`, and `PIPX_BIN_DIR` are set explicitly so that `npm` and `pipx` install into `/home/${USERNAME}/.local` without requiring a `USER` directive. No UID/GID args needed in this stage. Packages: only what's needed to run the installs (`nodejs`, `npm`, `python3`, `python3-pip`, `python3-venv`, `pipx`). The three install commands (`npm config set prefix`, `npm install -g`, `pipx install`) are combined into a single `RUN` layer.

**Final stage** starts from a fresh `ubuntu:24.04`. All root operations — apt install, sudo purge, user creation, directory setup — are combined into a single `RUN`. `npm` and `pipx` are excluded; only the runtimes are needed (`nodejs` for claude, `python3` for the aider venv). Tools are brought in via `COPY --from=builder --chown`. Entrypoint is copied with `--chmod=755`, eliminating a separate chown/chmod layer.

**Honest note on sudo:** `ubuntu:24.04` the Docker image does not actually ship with sudo — it's a minimal rootfs. The `apt-get purge sudo || true` has always been defensive; sudo was never present in any layer. The real value of the multi-stage build is layer hygiene and clean build/runtime separation for open-sourcing, not eliminating an active sudo threat. This was surfaced during design and is documented in TODO.md.

**Trade-off:** apt runs twice (once per stage), so builds take longer. Acceptable given that version updates already require a full rebuild.

### Debugging Tools Added

**Josiah directed** adding vim and a standard set of networking tools to the final image for use when shelling in to troubleshoot:

- `vim`
- `iputils-ping` — `ping`
- `net-tools` — `netstat`, `ifconfig`
- `iproute2` — `ip`, `ss`
- `dnsutils` — `dig`, `nslookup`
- `netcat-openbsd` — `nc`

These are final-stage only; no reason to include them in the builder.

### Build Failure: DNS Resolution in Builder Stage

First build attempt failed with `Could not resolve 'archive.ubuntu.com'` during the builder stage's `apt-get install`. Root cause: Docker's isolated build network doesn't inherit the host's DNS configuration by default. The previous single-stage build had never triggered this because the apt layer was cached — the new builder stage had no cache and needed to actually reach the network.

Fix: added `--network=host` to `build.sh`. This makes the build container share the host's network stack directly, bypassing Docker's virtual network. Both stages now resolve external hostnames correctly during build.

### Package List Decisions

**Josiah raised** whether Node.js and Python were still needed in the final stage given that the tools are pre-installed by the builder. Conclusion:

- `nodejs` — required. The `claude` binary is a Node.js script; the runtime must be present for it to execute.
- `python3` — kept. Useful for agent scripting tasks independent of aider. The aider venv's Python is isolated and not available for general use.
- `npm`, `pipx` — excluded from final stage. Package managers are build-time only; the binaries and venvs are already in place via the builder copy.

---

## Session 9 — 2026-05-19

### Session 8 Smoke Tests

First launch of the Session 8 multi-stage image confirmed all tools reachable at correct versions:

- Claude Code v2.1.143 at `/home/josiah/.local/bin/claude` ✓
- aider v0.86.2 at `/home/josiah/.local/bin/aider` ✓
- All Session 6/8 additions present: `vim`, `tmux`, `ssh`, `ping`, `dig`, `nc`, `ip`, `netstat` ✓
- Memory persistence confirmed via `~/.claude` mount ✓

### `~/.aider.conf.yml` Slug Fix — Inconclusive

The model slug fix (`inclusionai/ring-2.6-1t` → `openrouter/inclusionai/ring-2.6-1t`) was attempted via host-side `sed -i`. The file is mounted `:ro` so it cannot be edited from inside the container. After Josiah applied the change on the host, the running container still showed the old slug at aider startup. Root cause unclear — `sed -i` replaces the file via inode swap; Docker `:ro` bind mounts should follow the path rather than the inode, but the update did not propagate. Alternatively, the sed pattern may not have matched the file's actual format.

Workaround: `/model openrouter/inclusionai/ring-2.6-1t` override inside aider continues to work. The issue only affects the startup default.

---

## Session 10 — 2026-05-19

### tmux Config Passthrough

Added support for mounting the user's `~/.tmux.conf` and `~/.tmux/plugins/` into the container.

**Motivation:** The container already runs tmux for the split-pane mode, but users arriving with their own tmux configs were getting bare tmux with no keybindings or plugins. The goal was to make the user's tmux environment carry over without requiring unpredictable image changes for every possible plugin dependency.

**Approach:** mount both, add common deps to the image, document the rest as the user's problem.

**Mounts added to `run.sh`** (both conditional — skipped if the path doesn't exist on host):
- `~/.tmux.conf` → read-only
- `~/.tmux/plugins/` → read-write (so TPM can install plugins into it)

The read-write mount on `~/.tmux/plugins/` means plugin installations persist on the host across container restarts — TPM doesn't need to re-clone on every launch.

**System packages added to the final stage:**
- `xclip` — X11 clipboard; used by tmux-yank and common clipboard keybindings
- `xsel` — X11 clipboard alternative; preferred by tmux-yank
- `fzf` — common companion tool for session/window switcher plugins

**Intentionally omitted:**
- `wl-clipboard` — Wayland clipboard; not useful in a container without a display server
- `powerline` (Python package) — not needed by `tmux-powerline` (the TPM plugin), which is pure bash
- `fonts-powerline` / nerd fonts — font rendering happens in the host terminal, not the container

**README updated** with the two new mount rows and a tmux plugin support section explaining what's covered and explicitly setting expectations that unsupported deps are the user's responsibility.

### Post-Commit Fixes — Session 10

**Josiah independently made three changes** after the Session 10 commit:

**zsh added to the image.** `zsh` was added to the final-stage apt install block and `useradd` was updated to pass `--shell /bin/zsh`, making zsh the default shell for the created user. Without this, the container shell defaults to bash even though the mounted `.zshrc` and user environment expect zsh.

**`~/.aider.conf.yml` mount made conditional.** The hardcoded `-v ~/.aider.conf.yml:...` line in `run.sh` was replaced with the same conditional array pattern used for the tmux mounts — skipped if the file doesn't exist on the host. This makes the container usable without an aider config (Claude Code-only setups). README prerequisite note updated to mark aider config as optional.

These changes follow the pattern established in this session: conditional mounts for optional host files rather than failing if the file is absent.

### Deep Aider Smoke Test — tmux

Deeper smoke test exercised the full tmux→aider→OpenRouter→Ring path:

1. Created a detached tmux session (`aider-smoke`)
2. Launched aider in it via `tmux send-keys`
3. Switched model via `/model openrouter/inclusionai/ring-2.6-1t`
4. Sent a live prompt; captured response via `tmux capture-pane`

Ring responded correctly — thinking block, answer, token/cost breakdown ($0.00012). The `tmux send-keys` / `tmux capture-pane` round-trip works as an async communication channel between the Claude Code session and the aider pane.

**Josiah confirmed** the `./run.sh tmux` split-pane mode (claude left / aider right) works as well. Session kept live after smoke test at Josiah's direction.

### Aider Credential Mount — Made Optional

`~/.aider.conf.yml` was previously an unconditional mount in `run.sh`, causing the container to fail for users without the file. Changed to a conditional mount using the same pattern as the existing tmux mounts: the `-v` line is only added if the file exists on the host.

Josiah decided against the stronger `pass`-injection approach (which would eliminate the persistent plaintext file entirely). Documented instead in the README security model section: the `:ro` mount is write-protection only, not secrecy — the agent can read the file if directed to, transmitting the key to Anthropic's servers. Mitigation: scope the OpenRouter key to a hard cost limit.

### zsh Added

Added `zsh` to the final stage `apt-get install` block and set it as the login shell via `--shell /bin/zsh` on the `useradd` line. No `~/.zshrc` mount — Josiah opted to keep the shell config self-contained in the image rather than carrying over host config.

---

## Session 11 — 2026-05-19

### tmux Removed — `docker exec` Pattern Adopted

**Josiah identified** a fundamental keybinding conflict with the tmux-in-container approach: because the host tmux config uses the same prefix key, host tmux intercepts it before the inner session ever sees it. The split-pane mode was effectively unusable.

**Decision:** strip tmux from the container entrypoint entirely and replace with a `docker exec` pattern. The container is given a stable name (`--name faradai`), allowing any number of host terminals — tmux panes, terminal emulator splits, separate windows — to attach via `docker exec -it faradai <tool>`. Multi-tool workflows are now handled at the host level, with whatever multiplexer the user already has, instead of inside the container.

### `faradai` Executable

`run.sh` was superseded and deleted. A new `faradai` script was created as the single host-side entrypoint. It checks whether a container named `faradai` is already running:

- **Running:** `exec docker exec -it faradai <args>` — attaches to the existing container
- **Not running:** starts a new container via `docker run` with the full mount table

`exec` replaces the shell process on success; `set -euo pipefail` exits on failure — no explicit `exit` needed after the exec branch.

An `install.sh` was added alongside it to `chmod +x` the script and copy it to `/usr/local/bin/faradai` via `sudo install`. Both scripts made executable in the repo.

The tmux conf and plugin mounts were removed from `run.sh` (and are absent from the new `faradai` script) since they are no longer needed.

### Image Cleanup — tmux and zsh Removed

With tmux no longer used for the user-facing split-pane mode, **Josiah directed** removing it and all packages that existed solely to support it: `tmux`, `xclip`, `xsel`, `fzf`, and `zsh`. The container shell reverts to `/bin/bash`. README and BUILDLOG updated to reflect the new `faradai` executable pattern, the removed mounts, and the trimmed image contents.

### tmux Re-added — Internal Use Only

`tmux` was added back to the final-stage image. Rationale: Anansi (Claude Code) uses tmux internally to background aider sessions and communicate with Ring via `tmux send-keys` / `tmux capture-pane`. This is not user-facing UX — it's a tool-use pattern for running a second AI agent alongside Claude Code without needing a separate terminal.

The distinction from the removed tmux mode: no user config mounts, no split-pane entrypoint, no keybinding conflicts. tmux is simply a binary available inside the container for programmatic use.

---

## Session 12 — 2026-05-19

### Ring Code Review — Second Pass

Ring-2.6-1T reviewed the post-Session-11 state of FaradAI via a non-interactive aider session backgrounded in tmux. Full findings in the pane capture; summary of decisions:

**GPL3 License chosen.** Josiah decided on GPL3 to ensure FaradAI remains FOSS — derivative works must remain open-source. GPL3 closes the "use our work, give nothing back" loophole without restricting non-commercial or community use. LICENSE file added.

**P0 — Network access:** Container has unrestricted outbound network access. Acknowledged as a known limitation of the current architecture; documented in the security model rather than technically restricted at this stage.

**P1 items addressed:**
- `--no-install-recommends` added to final-stage `apt-get install` to reduce image size
- Container detection switched from `docker ps | grep` to `docker inspect --format '{{.State.Running}}'` — more precise, no substring collision risk
- Orphaned container cleanup: `docker rm -f faradai 2>/dev/null || true` added before `docker run` in the `faradai` script. `--rm` handles normal exits but not OOM kills or host crashes; this covers the residual case where a stopped container's name blocks a new start

**P1 items deferred:**
- CONTRIBUTING.md, issue/PR templates, CI pipeline, test suite — premature for a personal tool at this stage

**P2 items addressed:**
- SSH mount clarified in README: `:ro` key files are mounted but SSH agent forwarding (`SSH_AUTH_SOCK`) is not set up; documented so users understand why agent-based git over SSH won't work inside the container

**P2 items skipped:**
- seccomp/AppArmor profiles — Docker's default seccomp profile is sufficient for a dev tool at this stage
- Code of conduct — premature; add if a community grows around the project

**Naming settled:** FaradAI is the canonical project name in prose and branding; `faradai` is used for commands, image names, and code. Already consistent across the codebase — no changes needed.

---

## Session 13 — 2026-05-20

### Network Restriction — Design Decision

The network access open item (documented in `TODO.md` and the README security model since Session 1) was reviewed and closed as resolved by design.

Three technical approaches were considered:

- **Host-side iptables allowlist** — most thorough, but fragile: Docker manages its own iptables rules aggressively and cloud APIs use CDN IPs that rotate, making domain-based allowlists unreliable.
- **Forward proxy (tinyproxy/squid)** — domain-level allowlist via `HTTP_PROXY`/`HTTPS_PROXY`; more stable than IP rules, but adds a host-side service to maintain and doesn't stop raw TCP connections that bypass the proxy.
- **Documentation only** — current approach; accepted risk with honest documentation.

**Unrestricted outbound was affirmed as intentional.** The agent may need to reach arbitrary sources — documentation, APIs, package registries — and restricting outbound would require predicting those in advance, which defeats the purpose of a general-purpose coding assistant.

**Bridge gateway access to host services was also affirmed as intentional.** The container can reach services on the host via the Docker bridge gateway (typically `172.17.0.1`). This is a feature: Josiah may run k3s clusters, local dev servers, or other host-side services he wants the agent to interact with. Restricting this would break legitimate workflows.

**The Docker socket absence is the real protection.** Without `/var/run/docker.sock` mounted, the agent cannot escape the container by spawning new containers with unrestricted host mounts — the primary container escape vector. Network access is not the meaningful boundary; filesystem isolation and socket absence are.

README security model updated with a dedicated network access section reflecting these decisions.

### README Polish

Several readability improvements made to the README:

- **Opening rewritten** to lead with motivation ("AI coding assistants scan broadly by default") before describing what the project is. aider elevated from parenthetical to equal billing alongside Claude Code.
- **ASCII art added** at the top — waves-and-cage motif (≋ characters surrounding a boxed name) evoking the Faraday cage metaphor.
- **SSH table row thinned** — three sentences of agent-forwarding caveat moved out of the table cell into a blockquote note below the mounts table.
- **`--network=host` note relocated** from the Security model's network section to the Build section, where it belongs as a build-time implementation detail.
- **Bridge gateway IP removed** — "typically `172.17.0.1`" dropped; the IP varies by Docker config and isn't actionable for the reader.
- **Aider config example generalized** — model slug changed from Ring-2.6-1T to a `openrouter/<provider>/<model>` placeholder with a note to consult OpenRouter's model directory.
- **Future work section added** at the bottom: the container pattern is not specific to Claude Code or aider; other CLI-based agents (Goose, OpenHands, etc.) are natural candidates if the project grows.

---

## Session 14 — 2026-05-20

### Work Planning and GitHub Issues

Josiah opened the session by reviewing all open TODO items and ordering them into a priority sequence for the session: strict mode fix, env var validation, cap-drop, lifecycle trap, Docker args passthrough, configurable workdir, builder cache cleanup, then two README documentation items.

**Josiah directed** creating GitHub issues for each task before starting work. `gh` is not installed in the container, so the commands were drafted and run from the host terminal. A low-priority TODO item was added to add `gh` to the image.

### Task 1: `install.sh` strict mode — stale finding

On inspection, `install.sh` already had `set -euo pipefail`. Ring's finding #19 was incorrect. The TODO item and ring-feedback-0.md entry were removed rather than acted on.

### Task 2: Env var validation in `faradai`

Added input validation for `FARADAI_MEMORY`, `FARADAI_CPUS`, and `FARADAI_PIDS` before they are interpolated into the `docker run` call.

- **Memory:** split into numeric part and unit via bash parameter expansion; `m` and `g` units supported; `k` excluded (container memory in kilobytes is not a realistic use case, and the equivalent 512g ceiling in kilobytes is unreadable); 512g sanity limit applied per-unit (512 for `g`, 524288 for `m`).
- **CPUs:** decimal-aware regex; `%.*` truncation for integer bound check since bash `(( ))` does not handle floats; 128-core sanity ceiling.
- **PIDs:** positive integer only.

**Josiah directed** compressing the two memory bounds checks into a single `if` with `||`, and breaking the resulting long line at 80 characters.

### Task 3: `--cap-drop ALL` and `--security-opt no-new-privileges`

Added both flags to the `docker run` invocation in the `faradai` script. A README section was added to the Security model explaining what each flag does and why both are needed together. Closes ring-feedback-0 finding #1.

### Task 4: Lifecycle trap for non-atomic container start

Added `trap 'docker rm -f faradai 2>/dev/null || true' INT TERM EXIT` immediately after the `docker rm -f` line. The trap is only active in the narrow window between removing the old container and `exec docker run` replacing the shell process — after a successful exec the shell is gone and the handler never fires. Closes ring-feedback-0 finding #2.

### Task 5: `FARADAI_DOCKER_ARGS` passthrough

Added `EXTRA_DOCKER_ARGS` array populated via `read -ra` word-split on `FARADAI_DOCKER_ARGS`, appended to `docker run` between the conditional mounts and the `-w` workdir flag. Paths with spaces in the variable are not supported (word-split only). Closes ring-feedback-0 finding #12.

### Task 6: Configurable project path via `FARADAI_WORKDIR`

Replaced the hardcoded `~/Development/personal` path across three files:

- **`faradai`**: added `FARADAI_WORKDIR` env var (default `${HOME}/Development/personal`); mount and `-w` flag now use it directly — same path both sides, preserving the mirror-layout design.
- **`Dockerfile`**: added `ARG WORKDIR_PATH=/home/${USERNAME}/Development/personal` in the final stage; `mkdir`, `chown`, and `WORKDIR` all thread through it.
- **`build.sh`**: passes `--build-arg WORKDIR_PATH` derived from `FARADAI_WORKDIR` so image and script stay in sync.

`entrypoint.sh` had no hardcoded paths — no changes needed. Closes ring-feedback-0 finding #7.

### Task 7: Builder stage cache cleanup

Added four cleanup steps at the end of the builder's `RUN` block, before `COPY --from=builder` pulls `~/.local` into the final image:

- `pipx runpip aider-chat cache purge` — clears pip's HTTP cache within the aider venv
- `npm cache clean --force` — removes npm's download cache
- `find ... -name "__pycache__" ... -exec rm -rf {} +` — removes compiled Python bytecode
- `rm -rf /home/${USERNAME}/.cache` — removes pip's global cache directory

pip, setuptools, and wheel remain inside the venv intentionally — removing them could break aider if it attempts to install packages at runtime. Closes ring-feedback-0 finding #8.
