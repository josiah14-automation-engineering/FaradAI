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

### `gh` added to the image

Added the GitHub CLI (`gh`) to the final stage. `gh` is not in Ubuntu's default repositories, so the install adds GitHub's official apt source and GPG keyring, installs `gh`, then removes both the keyring and source list entry — they are only needed for installation, not for running the binary, and the container is rebuilt rather than apt-upgraded in place. Closes the LOW TODO item.

### `install.sh` now builds the image

`install.sh` previously only installed the CLI binary; users had to remember to run `build.sh` first. Josiah identified this as a UX gap and directed combining them: `install.sh` now calls `build.sh` before copying the binary. The `chmod +x` line was removed — the execute bit should already be set in the repo. README updated to collapse the separate Build and Install sections, and upgrade instructions simplified to a single `./install.sh` step.

### Tasks 8 & 9: README — Troubleshooting and Upgrade sections

Added a **Troubleshooting** section covering: Docker permission denied, expired credentials, container name conflict, SSH key permissions, aider not found (pre-fix image), and wrong model slug format.

Added an **Upgrading** section covering: `git pull` → `build.sh` → `install.sh` workflow, note that a running container is not affected until the next launch, and how to update pinned tool versions in the Dockerfile.

### Community scaffolding — CONTRIBUTING.md and GitHub templates

Added pre-open-source community scaffolding. Both items were preceded by web research into FOSS standards (Contributor Covenant, GitHub issue forms docs, curl/Podman patterns).

**`CONTRIBUTING.md`** — ~600 words. Covers: code of conduct (Contributor Covenant v2.1 link), ways to contribute, environment setup, making changes (shellcheck/hadolint), manual smoke test, PR process, and contact. Solo-maintainer caveat included. Explicitly calls out what doesn't fit (large refactors, opinionated style changes).

**GitHub templates** (`.github/`)
- `ISSUE_TEMPLATE/config.yml` — disables blank issues, links to Discussions for questions
- `ISSUE_TEMPLATE/01-bug-report.yml` — YAML form with required fields: container platform (dropdown), host OS, steps to reproduce, expected/actual behavior, error output (rendered as shell). `Additional context` field prompts for env vars without requesting secrets.
- `ISSUE_TEMPLATE/02-feature-request.yml` — YAML form: desired behavior, motivation, alternatives considered.
- `PULL_REQUEST_TEMPLATE.md` — description, related issue, changes list, testing notes, checklist (shellcheck, hadolint, smoke test, docs).

YAML issue forms chosen over markdown templates: Docker failure modes are systematic (platform dropdown is high-value), required fields prevent vague reports, auto-labeling reduces solo-maintainer triage burden.

### CI pipeline — `.github/workflows/ci.yml`

Added a GitHub Actions CI pipeline preceded by web research into Actions best practices (2025/2026). Three jobs:

- **`lint-shell`** — `shellcheck` on all four shell scripts; runs in parallel with lint-dockerfile
- **`lint-dockerfile`** — `hadolint/hadolint-action@v3.1.0` on the Dockerfile; runs in parallel with lint-shell
- **`build`** — depends on both lint jobs; builds the image via `docker/build-push-action@v5` with GHA layer cache (`type=gha,mode=max` captures all stages including builder); runs a smoke test verifying `claude`, `aider`, and `gh` are reachable inside the container

`--network=host` is passed through via `driver-opts: network=host` on `setup-buildx-action@v3`, matching what `build.sh` does locally to ensure `apt-get` can resolve external hostnames during build.

Smoke test uses `--entrypoint /bin/bash` so it runs without triggering claude authentication.

---

## Session 15 — 2026-05-20

### Build retry — IPv6 ETIMEDOUT resolved

The npm ETIMEDOUT build failure from Session 14 was transient. A second build attempt succeeded without changes. IPv6 flakiness was the cause; no Dockerfile fix was needed.

### Bug: `faradai` with no args drops into bash when container is already running

`faradai` with no arguments launches claude when starting a fresh container (the `docker run` branch defers to `entrypoint.sh`, which defaults to `claude`). But when the container was already running, the `docker exec` branch used `"${@:-bash}"` — a different default. One-character fix: changed to `"${@:-claude}"` so both paths agree.

### Full smoke test — first run against Session 14 image

Smoke test run against the newly built image. Results:

- `claude`, `aider`, `python3`, `git` — correct versions ✅
- `gh` — not found ❌ (see below)
- Mounts — all present and correct ✅
- `CapPrm`/`CapEff` both `0000000000000000` ✅
- `NoNewPrivs: 0` ❌ (see below)
- Memory limit active at 16 GiB ✅

**`gh` not found** — root cause: the smoke test ran against the *old* container, which had been started before the Session 14 rebuild. The `faradai` script attaches to a running container rather than starting a new one, so the new image wasn't picked up. Fix: `docker rm -f faradai && faradai` to restart against the new image. The Dockerfile is correct; no code change needed.

**`NoNewPrivs: 0`** — `--security-opt no-new-privileges` (without `:true`) is silently ignored by Docker. The correct form is `--security-opt no-new-privileges:true`. Fixed in `faradai`.

### tmux → aider round-trip smoke test — PASS

Full path exercised: tmux session → aider → OpenRouter → Ring-2.6-1T.

- Model loaded from `~/.aider.conf.yml` without slug mismatch ✅
- Response received ✅
- Token/cost line present (`$0.00018`) ✅
- No credential errors ✅

Two interactive one-time prompts fired during the session: an analytics opt-in and a release notes notice. These are benign for interactive use but would block a fully non-interactive invocation. Known workarounds: `--no-check-update` suppresses the release notes check; `AIDER_ANALYTICS_DISABLE=true` suppresses the analytics prompt without requiring a per-user config file. Not addressed at this stage — noted as a known issue.

---

## Session 16 — 2026-05-20

### Full Smoke Test — All Green

Ran all SMOKETEST.md sections against the current image. Results:

- `claude` 2.1.143, `aider` 0.86.2, `gh` 2.92.0, `python3` 3.12.3, `git` 2.43.0 ✅
- Mounts — `~/Development/personal` mounted, credentials file present at `600` ✅
- `CapPrm`/`CapEff` both `0000000000000000` ✅
- `NoNewPrivs: 1` ✅
- Memory limit: 16 GiB ✅
- `gh auth` — initially not logged in; Josiah ran `gh auth login` from the host terminal and authenticated as `josiah14` (scopes: `repo`, `read:org`, `gist`); re-test passed ✅
- tmux → aider round-trip ✅ (see below)

### tmux → aider Round-Trip — "What's New?" Prompt Workaround

The smoke test script sends `/model` and the test prompt immediately after launching aider. Aider's interactive "Would you like to see what's new in this version?" prompt fired before aider reached its `>` prompt, intercepting both commands as invalid Y/N answers. Recovery: sent `n` to dismiss the prompt; aider reached `>` and accepted subsequent commands normally.

Ring-2.6-1T responded with "hello" and a cost line (`$0.00018`). Round-trip confirmed working.

This is the same one-time-prompt issue noted in Session 15. Fully non-interactive scripts driving aider via tmux need to account for this prompt — either by dismissing it first or by suppressing it via `--no-check-update`. Not addressed at this stage.

---

## Session 17 — 2026-05-20

### Uninstall and Reinstall Confirmed

**Josiah confirmed** that a clean uninstall followed by `./install.sh` produces a working container. Full smoke test run against the freshly installed image.

### Full Smoke Test — All Green

- `claude` 2.1.143, `aider` 0.86.2, `gh` 2.92.0, `python3` 3.12.3, `git` 2.43.0 ✅
- Mounts — `~/Development/personal` mounted, `.credentials.json` present at `600` ✅
- `CapPrm`/`CapEff` both `0000000000000000` ✅
- `NoNewPrivs: 1` ✅
- Memory limit: 16 GiB ✅
- `gh auth` — logged in as `josiah14` (scopes: `repo`, `read:org`, `gist`) ✅
- tmux → aider round-trip ✅

### tmux → aider Round-Trip — Prompt Caveat Documented

The "Would you like to see what's new in this version?" prompt intercepted the first round-trip attempt, swallowing the `/model` command and test message as invalid Y/N answers. **Josiah directed** retrying with an explicit `n` to dismiss the prompt before sending further input — round-trip succeeded on the second attempt. Ring responded with "hello" and a cost line.

SMOKETEST.md updated: added a caveat block before the round-trip script explaining the prompt behaviour, and updated the script to send `n` and extend the initial sleep to 6 seconds to give aider time to show the prompt before the dismissal keystroke fires.

---

## Session 18 — 2026-05-20

### Dockerfile: `apt-get purge sudo || true` Removed

Closed ring-feedback-0 finding #9. The `apt-get purge sudo 2>/dev/null || true` line was removed from the Dockerfile. The BUILDLOG already documented (Session 8) that `ubuntu:24.04` the Docker image does not ship with sudo — making this line a no-op that silently masked potential dpkg failures. The `userdel`/`groupdel` `|| true` patterns were retained; those are genuinely conditional on whether the ubuntu user exists in a given base image version.

### `faradai update` Subcommand

Closed ring-feedback-0 finding #10. Added a `faradai update` subcommand. On invocation it creates a temp directory under `/tmp` via `mktemp`, registers a `trap ... EXIT` to remove it, clones the repo from GitHub into it, and runs `install.sh`. Cleanup happens whether the install succeeds or fails. The Upgrading section of the README was rewritten to lead with `faradai update` rather than the manual `git pull && ./install.sh` workflow. Modes table updated to include `update` and `uninstall`.

---

## Session 19 — 2026-05-20

### `HEALTHCHECK` Added to Dockerfile

Closed ring-feedback finding #1. Added a `HEALTHCHECK` directive to the final stage: checks that both `claude --version` and `aider --version` exit cleanly every 30 seconds, with a 15-second start period and 3 retries before marking unhealthy. Placed after the `USER` directive so it runs as `${USERNAME}` rather than root — the tools are installed under that user's home directory and should be verified in that context. Primarily useful for orchestration environments; has no effect on interactive `faradai` usage.

**Post-commit correction:** initial placement was before `USER ${USERNAME}`, which would have run the check as root. Caught on review and moved after the `USER` directive.

### `FARADAI_DEBUG` Env Var

Closed ring-feedback-0 finding #11. Added `FARADAI_DEBUG` support to the `faradai` script. When set to `1`, prints the resolved config (workdir, memory, cpus, pids) to stderr and enables `set -x`, causing bash to print the full `exec docker run ...` invocation with all arguments before executing. Follows the existing env-var-driven config pattern rather than introducing a positional `--debug` flag. Help text and README env vars table updated.

### `install.sh` sudo Availability Check

Closed ring-feedback-0 finding #15. Added a `command -v sudo` guard at the top of `install.sh` that exits with a clear error message if sudo is not available, rather than failing mid-install with an unhelpful `command not found`. Troubleshooting entry added to README with the manual fallback for root-capable environments without sudo.

---

## Session 20 — 2026-05-20

### Smoke Test — All Green

Full SMOKETEST.md run against the current image (gh authenticated as `josiah14` from the previous session):

- `claude` 2.1.143, `aider` 0.86.2, `gh` 2.92.0, `python3` 3.12.3, `git` 2.43.0 ✅
- Mounts — `~/Development/personal` mounted, `.credentials.json` present at `600` ✅
- `CapPrm`/`CapEff` both `0000000000000000` ✅
- `NoNewPrivs: 1` ✅
- Memory limit: 16 GiB ✅
- `gh auth` — logged in as `josiah14` ✅
- tmux → aider round-trip ✅ (Ring responded "hello", cost line present, no credential errors)

### GitHub Issues — All Closed

All 8 open GitHub issues closed with `gh issue close` comments referencing the resolving commits:

| Issue | Commit(s) |
|-------|-----------|
| #1 — validate resource env vars | `d681ea2` |
| #2 — cap-drop + no-new-privileges | `a838909`, `141b260` |
| #3 — lifecycle interrupt trap | `6cc8610` |
| #4 — FARADAI_DOCKER_ARGS passthrough | `b97a05a` |
| #5 — FARADAI_WORKDIR | `1448128` |
| #6 — builder cache cleanup | `2cc2b9f` |
| #7 — troubleshooting section | `730ab6f` |
| #8 — upgrade/update instructions | `730ab6f`, `863895f` |

### Ring Feedback Files — Consolidated and Closed

`ring-feedback-0.md` (Ring-2.6-1T's original 19-finding automated review) and `ring-feedback.md` (the accumulated human-reviewed consolidated assessment) were triaged and retired.

**Josiah reviewed each remaining unresolved item and made the following calls:**

- **#4 (`--network=host` during build)** — won't change; required for DNS resolution in the builder stage and applies only at build time, not to the running container.
- **#5 (image digest pinning)** — deferred; added to TODO under "Hardening."
- **#6 (API key readable inside container)** — won't fix; inherent tradeoff of file-based credential delivery to an autonomous agent, documented in the security model.
- **#16 (`docker rm -f` affects other users)** — won't fix; single-user host assumption is a known design scope.
- **#17 (no prune/cleanup mechanism)** — deferred; added to TODO under "Hardening."
- **#18 (no known-issues/limitations section)** — deferred; added to TODO under "Hardening."
- **ring-feedback.md remaining items #1–#3** (no `--pull`, no SSH agent forwarding, HEALTHCHECK) — removed; `--pull` and SSH agent forwarding are won't-fixes, HEALTHCHECK is resolved.

`ring-feedback-0.md` deleted. `ring-feedback.md` blanked. `TODO.md` updated with a new "Hardening (deferred)" section covering the three deferred items.

---

## Session 21 — 2026-05-20

### Ring Assessment 1 Triage

Ring-2.6-1T assessment 1 (2026-05-20) produced 18 findings. Josiah triaged all 18:

- 12 findings carried forward to TODO (ordered by severity)
- 4 flagged won't-fix: `--network=host` during build (required for DNS), credentials readable inside container (inherent tradeoff, documented), `docker rm -f` multi-user risk (single-user host assumption), `--pull` flag (previously accepted; reconsidered and added to TODO)
- 1 disputed: Ring flagged no `.dockerignore` but one exists — stale context
- 1 stale: Ring found `install.sh` missing `set -euo pipefail` but it was already present

`ring-feedback.md` written fresh with all 18 findings (summary table + detailed sections).

### Lesson: Don't Send Keystrokes Before the `>` Prompt Is Live

During the Ring review session, a pre-emptive `n` keystroke (intended to dismiss aider's "Would you like to see what's new?" prompt before it appeared) was sent while aider was still in its pager view scrolling through the loaded files. By the time aider finished initializing and reached the `>` input prompt, the queued `n` was submitted as the actual user prompt to Ring. Ring received a single character, had all project files in context, and rewrote CLAUDE.md in a friendlier tone. The change was reverted via `git checkout`.

**Rule:** never send keystrokes to an aider tmux session until `tmux capture-pane` confirms the bare `>` prompt is live. The "What's new?" prompt appears *after* the `>` prompt, not before it — so there is no race to win by sending early. The correct sequence is: wait for `>`, then optionally dismiss the prompt if it appears, then send the actual prompt.

### Ring #1: FARADAI_DOCKER_ARGS Allowlist

Closed ring-feedback assessment 1 finding #1 (CRITICAL). `FARADAI_DOCKER_ARGS` was word-split and appended to `docker run` with no validation, allowing injection of `--privileged`, `-v`, `--cap-add`, `--network=host`, etc. — completely defeating the `--cap-drop ALL` and `no-new-privileges` hardening.

Fix: added per-flag validation loop after the `read -ra` word-split. Tokens not starting with `-` (values following a flag) pass through. Tokens starting with `-` are checked against an allowlist: `--env`/`-e`, `--label`/`-l`, `--device`, `--publish`/`-p`, `--hostname`. Any flag not on the list exits with a clear error and the permitted list.

Smoke-tested against safe flags (pass) and dangerous flags (`--privileged`, `--cap-add=SYS_ADMIN`, `-v`, `--network=host`, `--pid=host`) — all blocked correctly.

Help text, resource limits table in README, and capabilities section updated to document the allowlist and remove the misleading `--cap-add` suggestion.

### Ring #2: Memory Validation Rewrite

Closed ring-feedback assessment 1 finding #2 (HIGH). The original two-step validation (strip one trailing character, then check numeric) was hard to reason about and had two real edge cases: `4.5g` was incorrectly rejected (Docker accepts decimal memory values), and `0g` incorrectly passed.

Replaced with a single anchored regex `^([0-9]+(\.[0-9]+)?)([mgMG])$` using `BASH_REMATCH`, which validates the entire string in one shot. A zero check follows: if the integer part is 0 and there is no meaningful decimal (e.g. `0`, `0.0`, `0.00`), the value is rejected; `0.5g` passes. The existing 512g bounds check is retained, using the integer part for the comparison.

Smoke-tested across 14 cases covering valid values, double-unit inputs, zero variants, missing units, and bounds limits — all correct.

### Ring #3: Dockerfile Base Image Digest Pinning

Closed ring-feedback assessment 1 finding #3 (HIGH). Both `FROM ubuntu:24.04` stages in the Dockerfile were using a floating tag — a re-published tag would silently change the base image on the next rebuild.

Both stages pinned to `ubuntu:24.04@sha256:c4a8d5503dfb2a3eb8ab5f807da5bc69a85730fb49b5cfca2330194ebcc41c7b`. Digest fetched from the Docker Hub registry API (`docker-content-digest` response header). The tag is retained alongside the digest for readability — Docker resolves via the digest; the tag is ignored at pull time.

### Ring #7 / #8 / #18: Pre-flight, Entrypoint Help, Uninstall Cleanup

Three polish fixes done together as pre-public-release prep.

**#7 — Docker binary pre-flight check (`faradai`):** Added `command -v docker` guard immediately before the first `docker inspect` call. `--help`, `update`, and `uninstall` still work without Docker present; any path that reaches the container lifecycle code now fails cleanly with `faradai: docker is not installed or not in PATH`.

**#8 — `entrypoint.sh` help consistency:** Extracted usage text into a `_usage()` function. Added `--help|-h|help)` case that prints usage and exits 0. The `*` catch-all now prefixes the unrecognised command before printing usage and exiting 1 — matching the pattern of the host-side `faradai --help`.

**#18 — `uninstall` removed from in-container help:** `uninstall` was listed in `entrypoint.sh`'s help output despite being a host-only command. Removed. The host-side `faradai --help` still documents it.

---

## Session 22 — 2026-05-21

### GPT-5.5 External Review — Triage and TODO Integration

Josiah brought in an external GPT-5.5 review of the FaradAI codebase, which produced 15 findings (P0–P14) with a proposed execution order. Josiah directed integrating these into the TODO, with duplicates dropped and priorities assigned.

**Josiah identified** that the suggested execution order was largely sound and directed using it as the basis for insertion. Triage decisions:

- **#15 (SSH forwarding missing from Troubleshooting)** — marked superseded by the incoming P1 (SSH agent forwarding implementation). If the whole SSH model changes, the doc fix becomes moot.
- **P6 (gate `--publish`/`--device`)** — confirmed not a duplicate of resolved #1. #1 fixed flag injection via allowlist; P6 is a refinement requiring explicit opt-in env vars for the two boundary-widening flags within that allowlist.
- **P14 (seccomp/AppArmor)** — landed in a new "Explicitly not prioritized" section rather than deferred, consistent with GPT's own recommendation to defer.
- **P11, P12, P13** — placed in a new "v2 (deferred)" section, not mixed with v1 hardening items.
- **GPT's YAML-flattening concern** — investigated and disproved; the workflow file was already well-formed.

New items added to TODO: #19–#28 (open), #29 (hardening deferred), #30–#32 (v2 deferred).

### CI Fix — Branch Targeting and Missing Script (#19)

`ci.yml` referenced `main` in both `on.push.branches` and `on.pull_request.branches`; the repo default branch is `master`. CI had not been triggering on any push or PR.

**Anansi caught** a second issue while inspecting the file: `uninstall-faradai` was absent from the `shellcheck` target despite being a shell script in the repo. Both issues fixed together:

- `branches: [main]` → `branches: [master]` (both triggers)
- `shellcheck faradai install.sh build.sh entrypoint.sh` → added `uninstall-faradai`

#19 resolved and marked in TODO.

### SSH Agent Forwarding Implementation (#20)

Implemented SSH agent forwarding as the default transport for Git authentication inside the container, replacing the previous behavior where `~/.ssh` was the only available path.

**What shipped:**

- `faradai` script: `FARADAI_ENABLE_SSH_AGENT` defaults to `1`; when `$SSH_AUTH_SOCK` is set and points to a live socket, the script mounts it into the container at `/ssh-agent` and sets `SSH_AUTH_SOCK=/ssh-agent` in the container environment.
- `faradai` script: `FARADAI_MOUNT_SSH_DIR` defaults to `0`; `~/.ssh` directory mount is now an explicit opt-in, not the default path.
- `Dockerfile`: `openssh-client` installed; `ssh-keyscan` bakes GitHub, GitLab, and Bitbucket into `~/.ssh/known_hosts` at image build time so agent forwarding works without mounting `~/.ssh`.
- `build.sh`: already passes `USER_UID`/`USER_GID` as build args, so the container user's UID matches the host user's UID — socket permissions work without any extra steps.
- `README.md`: added "Host SSH agent setup" section under the SSH forwarding callout explaining how to check for, start, and persist an agent across sessions, including the `keychain` option.

**Josiah directed** closing out the BUILDLOG and TODO after confirming the implementation was complete and the only remaining steps were rebuild and smoke test (his side).

---

## Session 23 — 2026-05-21

### Full Smoke Test — All Green (gh auth gap identified)

Full SMOKETEST.md run against the current image. Results:

- `claude` 2.1.143, `aider` 0.86.2, `gh` 2.92.0, `python3` 3.12.3, `git` 2.43.0 ✅
- Mounts — `~/Development/personal` mounted, `.credentials.json` present at `600` ✅
- `CapPrm`/`CapEff` both `0000000000000000` ✅
- `NoNewPrivs: 1` ✅
- Memory limit: 16 GiB ✅
- `gh auth` — not logged in ❌ (see below)
- SSH agent — socket at `/ssh-agent`, 7 keys loaded ✅
- tmux → aider round-trip ✅ (Ring responded "hello", cost line present)

**`gh auth` not persisted:** `gh auth login` stores tokens in `/home/josiah/.config/gh/hosts.yml` inside the container's writable layer — not on a host-mounted path. Credentials are lost on rebuild or restart. **Josiah ran `gh auth login` himself** from the host terminal (device-flow, one-time code `D0DA-1B65`), authenticating as `josiah14` with scopes `repo`, `read:org`, `gist`. Re-test passed. Added as TODO [#33] (low priority): mount a host-side `~/.config/gh/` to persist across sessions.

### GitHub Issues Created for All Open TODO Items

**Josiah directed** creating GitHub issues for every open item in TODO.md. Seven labels created (`priority: high/medium/low`, `security`, `dockerfile`, `deferred`, `v2`) and 23 issues filed across all severity tiers, deferred hardening items, and v2 architectural work.

### CI Fix — Hadolint Dockerfile Violations

**Josiah provided CI error output** showing four hadolint failures that were blocking the `build` job:

- **DL3008 (line 10):** builder stage `apt-get install` without pinned versions
- **DL3015 (line 10):** builder stage missing `--no-install-recommends`
- **DL4006 (line 40):** piped `RUN` in final stage without `SHELL pipefail` guard
- **DL3008 (line 40):** final stage `apt-get install` without pinned versions

All four addressed in a single Dockerfile edit:

- Builder stage `apt-get install`: added `--no-install-recommends`; pinned `nodejs=18.19.1+dfsg-6ubuntu5`, `npm=9.2.0~ds1-2`, `python3=3.12.3-0ubuntu2.1`, `python3-pip=24.0+dfsg-1ubuntu1.3`, `python3-venv=3.12.3-0ubuntu2.1`, `pipx=1.4.3-1`
- Final stage: added `SHELL ["/bin/bash", "-o", "pipefail", "-c"]` before the first `RUN`; pinned all 14 Ubuntu packages and `gh=2.92.0`

Package versions sourced from the running container's dpkg database and the Ubuntu 24.04 package index. The `gh` pin is sourced from GitHub's stable apt channel and is the currently-installed version; it may need bumping when GitHub releases a new `gh` version and drops the old one from their channel.

TODO items #34, #35, #36 marked resolved.

---

## Session 24 — 2026-05-21

### CI Green — Hadolint Fixes Confirmed

CI passed on the first push following the Session 23 hadolint fixes. All three jobs (`lint-shell`, `lint-dockerfile`, `build`) green. No further Dockerfile or workflow changes needed.

### Full Smoke Test — All Green

Full SMOKETEST.md run against the current image.

- `claude` 2.1.143, `aider` 0.86.2, `gh` 2.92.0, `python3` 3.12.3, `git` 2.43.0 ✅
- Mounts — `~/Development/personal` mounted, `.credentials.json` present at `600` ✅
- `CapPrm`/`CapEff` both `0000000000000000` ✅
- `NoNewPrivs: 1` ✅
- Memory limit: 16 GiB ✅
- `gh auth` — not logged in on fresh container start (known, TODO #33); **Josiah ran `gh auth login`** from host terminal (device flow, code `B1DF-6B75`), authenticated as `josiah14` (scopes: `repo`, `read:org`, `gist`); re-test passed ✅
- SSH agent — socket at `/ssh-agent`, 7 keys loaded ✅
- tmux → aider round-trip ✅ (Ring responded "hello", $0.00018, no credential errors)

### entrypoint.sh: Arg Passthrough (#38)

Fixed `entrypoint.sh` to forward remaining args to the selected tool via `"${@:2}"` in each `exec` call. Enables patterns like `faradai claude --resume` and `faradai aider --no-git`. No filtering applied — args go to the tools inside the container, not to Docker itself, so the container boundary is unaffected. Updated `faradai` help text to document the passthrough syntax. **Josiah verified** with `faradai aider --no-git`. Closes #38.

### Ring Assessment 2 Triage

Ring-2.6-1T reviewed the current codebase and produced 6 new findings. All 6 triaged and added to TODO as #37–#42.

Ring also flagged incidental fixes for already-tracked issues #6 (fragile container state detection) and #24 (CPU/PID zero validation) as bonus changes while touching the same code paths — noted in #41's TODO entry.

Summary of findings by severity:

- **Medium:** #37 (no image pre-flight check), #38 (entrypoint drops args after command), #41 (update uses SSH clone + fall-through bug)
- **Low:** #39 (no logs/status subcommands), #40 (no version flag), #42 (CI smoke test bypasses entrypoint)

Josiah noted these findings are less critical than previous review rounds — the core hardening work is paying off.

---

## Session 25 — 2026-05-21

### faradai Script Refactor

Extracted inline validation blocks and the DOCKER_ARGS allowlist loop into named functions (`_validate_memory`, `_validate_cpus`, `_validate_pids`, `_build_extra_docker_args`), pulled `_usage` into a function, and reorganised the script body into clearly labelled sections (functions → dispatch → pre-flight → attach → start → validate → mounts → debug → run). No behaviour changes to existing functionality.

Also resolved in the same pass:

- **#6 (fragile container state detection)** — replaced `docker inspect ... | grep -q true` with `[[ "$(docker inspect --format '{{.State.Running}}' ...)" == "true" ]]`.
- **Update fall-through bug (#41 partial)** — added `exit 0` after `install.sh` in the `update` case; previously execution fell through to `docker run` after a successful update.
- **#25 (`--publish`/`--device` gating)** — both flags removed from the base allowlist; now require explicit opt-in via `FARADAI_ALLOW_DEVICE=1` / `FARADAI_ALLOW_PUBLISH=1`. Error message updated to explain the opt-in. Two new env vars documented in help text.
- **Mount array if-blocks condensed** — nested conditionals flattened to single-line `[[ ]] &&` assignments where the body fits on one line.

### Rash Migration Considered — Deferred

Josiah raised whether it was time to migrate `faradai` to rash (Racket-based Lisp shell) in keeping with the Lisp-at-each-layer philosophy. Decision: not yet.

The script is almost entirely Docker flag orchestration — conditional array building, exec replacement, fork/exec patterns. These are first-class in bash and awkward to express cleanly in most alternatives. The refactor removed the main source of bash pain (inline validation); what remains reads well at 181 lines.

The inflection point for a migration would be if the script grew real complexity: profile switching, config file parsing, per-project policy. That would make bash start to fight back, and a Lisp shell would start paying for its runtime dependency. That complexity does not exist yet.

The polyparadigm angle (rash as a curriculum target) is a valid separate motivation — the script is a well-understood, appropriately-sized port target. But that is a learning exercise, not a maintenance need. Deferred.

---

## Session 26 — 2026-05-21

### pwd Workdir Default, Explicit Container Naming, Trust Prompt (#43)

Addressed three usability gaps that made `faradai` awkward across multiple simultaneous projects.

**Workdir default changed to `$(pwd)`**

`FARADAI_WORKDIR` previously defaulted to `~/Development/personal`. Changed to the current working directory at invocation time. Users who want a fixed path still set `FARADAI_WORKDIR` explicitly; users who run `faradai` from their project directory get the right mount automatically. Also removes `WORKDIR_PATH` from the Dockerfile, `build.sh`, and CI — the image no longer pre-creates a workdir since Docker auto-creates bind-mount targets at runtime.

**Container naming via `-n` / `-a` CLI flags**

The initial draft used a `FARADAI_NAME` environment variable. **Josiah redirected** to CLI flags, reasoning that naming is per-invocation intent rather than a persistent preference.

Initial design: `-n NAME` creates `faradai-NAME`, errors if the container already exists. No env var.

**Josiah then added `-a [NAME]`** for explicit attachment to a named (or default) container, making create vs. attach intent unambiguous at the call site rather than relying on implicit auto-detect for named containers.

Final flag matrix:
- `faradai [CMD]` — auto-detect default `faradai` container (attach if running, create if not); backward compatible
- `faradai -n NAME [CMD]` — create `faradai-NAME`; error if any container by that name exists
- `faradai -a NAME [CMD]` — attach to running `faradai-NAME`; error if not running
- `faradai -a [CMD]` — attach to default `faradai`; error if not running

`-n` and `-a` are mutually exclusive. Error messages in both directions include the corrective hint (`faradai -a NAME` / `faradai -n NAME`), acting as in-band documentation.

The flag parser uses a manual `case` loop rather than `getopts` to avoid a known bash edge case where `getopts` consumes `--help` as an unknown option before the subcommand dispatch can see it.

**Trust prompt**

Added a `mount <path>? [y/N]` prompt before every fresh container start, mirroring the trust model Claude Code uses for new directories. Fires for all subcommands (`faradai`, `faradai bash`, `faradai aider`, `faradai claude`). The only path that skips it is `exec docker exec` on an already-running container (which exits the script before reaching the prompt). Bypass via `FARADAI_TRUST_DIR=1` for scripts and environments where the prompt is unnecessary.

**`uninstall-faradai` updated**

All single-container `docker inspect faradai` calls replaced with `--filter "name=faradai"` queries, which match both `faradai` and any `faradai-*` containers. Running-container check now lists all matching containers; removal step uses `xargs -r docker rm -f` to handle the multi-container case.

---

## Session 27 — 2026-05-21 18:05 UTC

### Full Smoke Test — All Green

Full SMOKETEST.md run against the current image (pre-rebuild; Session 26 changes not yet reflected in the running container).

- `claude` 2.1.143, `aider` 0.86.2, `gh` 2.92.0, `python3` 3.12.3, `git` 2.43.0 ✅
- Mounts — workdir mounted, `.credentials.json` present at `600` ✅
- `CapPrm`/`CapEff` both `0000000000000000` ✅
- `NoNewPrivs: 1` ✅
- Memory limit: 16 GiB ✅
- PID limit: 1024 ✅ — Josiah has `FARADAI_PIDS=1024` set in `.zshrc` (above the script default of 512)
- CPU limit: 8 cores ✅ — Josiah has `FARADAI_CPUS=8` set in `.zshrc` (above the script default of 4)
- `gh auth` — logged in as `josiah14` ✅
- SSH agent — socket at `/ssh-agent`, 7 keys loaded ✅
- tmux → aider round-trip ✅ (Ring responded "hello", $0.00018, no credential errors)

### Ring Bash Review

Ring-2.6-1T reviewed the bash scripting across all five shell scripts (`faradai`, `uninstall-faradai`, `build.sh`, `install.sh`, `entrypoint.sh`) for best practices, shellcheck compliance, and cleanup opportunities. Produced a prioritized findings table.

**P1 — Bug (already correct):** Ring flagged `_remaining+=("${_args[@]}")` appending all args instead of the current one. The file already had `_remaining+=("${_args[_i]}")` — Ring caught it in its thinking pass but the written code was already correct. No change needed.

**Fixes applied:**

- `_build_extra_docker_args` — `xargs -r` (GNU-only) in `uninstall-faradai` replaced with `while IFS= read -r ... done < <(...)` process substitution; portable to macOS/BSD.
- `build.sh` — `$(dirname "$0")` replaced with `$(cd "$(dirname "$0")" && pwd)` to resolve symlinks correctly; `install.sh` already used this pattern.
- `faradai` — Added explanatory comments to the zero-memory check, CPU float validation, `_is_running || _is_running=""` pattern, and the `set -- "${array[@]+...}"` bashism.
- `faradai` — `_is_cmd` changed from integer `0`/`1` to string `false`/`true` for type consistency with its string comparison.
- `faradai` — Added actionable error message to `git clone` failure in the `update` case.
- `uninstall-faradai` — `_confirm_kill`/`_confirm` renamed to `_confirm_containers`/`_confirm_removal` for clarity.
- `uninstall-faradai` — `echo "Done."` moved to after both `sudo rm` calls so it doesn't print prematurely if sudo prompts for a password.
- Various whitespace: blank lines added between `done`/`for` and following `if`/`case` blocks for readability (**Josiah directed** these hygiene fixes).

### bats Test Ticket Created

Created GitHub issue #39 (TODO item #44) for adding bats-core unit tests covering the validation functions and flag parser. Docker interaction explicitly out of scope — CI smoke test covers that surface.

### SMOKETEST.md Updated

Added PID and CPU limit checks to the Resource limits section. Josiah's system has `FARADAI_PIDS=1024` and `FARADAI_CPUS=8` set in `.zshrc` — both confirmed active in the cgroup checks above.

## Session 28 — 2026-05-22 01:52 UTC

### Name Transparency — README Update

Opus raised that the "Faraday cage" name implies network isolation that FaradAI v1 does not provide — default egress is fully open. **Josiah confirmed** the name is aspirationally accurate: v2 broker mode (#30, #32) is the path to making it true. Updated README in two places to document this gap honestly:

- Intro blurb: clarified that v1 constrains the filesystem, not network; noted v2 broker plan
- Network access section: added an explicit paragraph naming this as the current gap in the metaphor, with a pointer to the v2 plan and a reminder that `FARADAI_NETWORK_MODE=none` is available for offline sessions

### SSH Agent Forwarding — Threat Model + Confirmation Prompt

Opus flagged that SSH agent forwarding deserved louder treatment in the security model: the AI agent inside the container has full signing authority over all loaded keys and can initiate arbitrary SSH operations (git push, SSH connections) as the user.

**Changes:**

- `faradai` script: added a confirmation prompt before forwarding the agent. Lists loaded keys via `ssh-add -l`, then asks `"forward SSH agent into container? [y/N]"`. Declining skips forwarding without aborting the container start. New `FARADAI_TRUST_SSH_AGENT` env var (default `0`) bypasses the prompt — **Josiah** chose `0` as default and will add `FARADAI_TRUST_SSH_AGENT=1` to his `.zshrc`.
- README: added `FARADAI_TRUST_SSH_AGENT` to the SSH env var table; added `### SSH agent forwarding` subsection in the security model with an explicit callout on key signing authority
- `_usage()` help text updated with new variable

### Rash Migration Ticket

Added GitHub issue #40 and TODO item [#45] for eventual migration of complex Bash scripting to Rash (Racket-hosted shell DSL). Deferred until v1 feature set stabilizes. See Session 25 for the stay-in-Bash reasoning.

## Session 29 — 2026-05-22 02:27 UTC

### README Stale Workdir Reference Fixed

Found one remaining `~/Development/personal` reference in the README mounts section (line 127) that was missed during the #43 workdir-default change. Updated to "current directory (`pwd`) at launch time."

### Rash vs scsh — Language Evaluation

Extended the language rewrite discussion (first opened in Session 25). scsh was raised as an alternative to Rash: already in the polyparadigm plan, more mature, fewer sharp edges. After examination the case for scsh doesn't hold:

- **Same glibc problem** — scsh compiles to a dynamically-linked binary with the same distribution constraints as Rash, and less tooling around solving it.
- **No substrate backstop** — Rash sits on Racket, which is actively maintained. If Rash the DSL moves slowly, the substrate is healthy. scsh has no equivalent; if it stalls, it stalls all the way down.
- **Lower learning value** — Racket is a live, interesting ecosystem. scsh is closer to a historical curiosity as a polyparadigm target.

The glibc issue itself is solvable: build on an old-glibc Docker base (e.g. `ubuntu:20.04`) or Alpine/musl in CI, and the binary runs widely. Go's `CGO_ENABLED=0` remains the path of least resistance for distribution, but Rash isn't disqualified on glibc grounds alone.

**Revised ranking:** Rash over scsh. Reasoning and Opus's Nim/Zig/Rash analysis added as comments on GitHub issue #40.

## Session 30 — 2026-05-22 02:41 UTC

### Pre-flight Checks and Validation Guards (#9 #23 #24 #37)

Four medium-priority defensive fixes applied in a single pass; commit f4c80c8.

- **[#37] Image pre-flight** — `docker image inspect faradai:latest` check added to the docker pre-flight section; clear error directs user to `./install.sh` rather than surfacing a cryptic Docker message.
- **[#23] FARADAI_WORKDIR existence validation** — `[ -d "${FARADAI_WORKDIR}" ]` check added immediately after workdir resolution; exits with a descriptive error if the directory does not exist.
- **[#24] Zero validation for CPU and PID** — `_validate_cpus` now rejects zero via awk float comparison; `_validate_pids` now rejects zero via an integer `if` block. **Josiah caught** that the initial `|| true` on the PID check was an antipattern (masking `(( ))`'s non-zero exit when the condition is false); replaced with a proper `if` block.
- **[#9] uninstall-faradai sudo guard** — `command -v sudo` guard added at the top of `uninstall-faradai`, matching the pattern already in `install.sh`.

All four GitHub issues closed with commit reference.

### faradai update: SSH → HTTPS (#41 #28)

The `update` subcommand cloned via `git@github.com:...` (SSH), which fails for any user without a GitHub SSH key configured. Switched to `https://github.com/...` — no credentials required for a public repo clone. Error message updated to reference network connectivity rather than SSH keys. README Upgrading section corrected to say "over HTTPS (no SSH key required)" rather than "latest release". Closes both #41 and #28 (docs/behavior mismatch).

### Low-Priority One-Liners (#13 #14 #26)

Three low-priority single-line fixes applied in one pass:

- **[#13] Docker daemon check** — `docker info` pre-flight added after the binary check; gives a clear "Docker daemon is not running" error instead of a swallowed socket error.
- **[#26] `--init` flag** — `--init` added to `docker run`; prevents zombie process accumulation in long-lived containers where AI tooling spawns subprocesses.
- **[#14] OCI labels** — `org.opencontainers.image.title` and `org.opencontainers.image.source` added to the Dockerfile final stage; `docker image inspect` now shows provenance.

All three GitHub issues closed with commit reference.

---

## Session 31 — 2026-05-22

### Smoketest — All Checks Passed

Full smoketest run against a fresh container:

- Tools: claude 2.1.143, aider 0.86.2, gh 2.92.0, python 3.12.3, git 2.43.0
- Mounts: workdir correct, `~/.claude/.credentials.json` present and `rw-------`
- Capability drop: all caps `0000000000000000`; `NoNewPrivs: 1`
- Resource limits: 16 GiB RAM, 8 CPUs, 1024 PIDs
- gh auth: logged in as josiah14
- SSH agent forwarding: `/ssh-agent` socket present, keys accessible

**Josiah noted** that the smoketest's `ssh-add -l` step prints key fingerprints and email labels into the conversation context. Logged a suggestion to replace it with `ssh-add -l | wc -l` to confirm keys are loaded without exposing identity metadata.

---

## Session 32 — 2026-05-22

### Persist gh auth across container restarts (#33)

`gh auth login` writes tokens to `~/.config/gh/hosts.yml` inside the container's writable layer, losing them on every restart. Fixed by mounting the host's `~/.config/gh/` read-write into the container. A `mkdir -p` call before `docker run` ensures the directory exists on the host even for users who have never run gh outside the container, so `gh auth login` inside the container always persists. README mounts table and SMOKETEST updated accordingly.

**Verified:** `ls ~/.config/gh` on the host showed `config.yml` and `hosts.yml` populated from the earlier `gh auth login` run inside the container. `gh auth status` on the host confirmed token intact and active.

### Add FARADAI_NETWORK_MODE=open|none (#27)

`FARADAI_NETWORK_MODE` env var added with `open` (default, no `--network` flag) and `none` (`--network none`) modes. Validation follows the existing `_validate_*` pattern. `broker` mode remains deferred to v2. README env var table updated; network section already anticipated the feature.

**Verified:** `FARADAI_NETWORK_MODE=none faradai bash` → `ping www.google.com` returned `Operation not permitted`. Launching without the var confirmed outbound network still works.

---

## Session 33 — 2026-05-22

### Add bats unit tests for validation and flag-parsing (#44)

40 tests in `test/unit.bats` covering:

- **Flag parser** — `-n`/`-a` mutual exclusivity, `-n` without NAME, `-a` not consuming a known command as a container name, `-a` consuming an unknown word as a container name
- **`_validate_memory`** — rejects 0g/0m/0.0g, non-numeric, >512g; accepts 0.5g, 512g, 4g, 512m
- **`_validate_cpus`** — rejects 0, negatives, non-numeric, >128; accepts 4, 2.5, 128
- **`_validate_pids`** — rejects 0, non-integer, float; accepts 512, 1
- **`_validate_network_mode`** — rejects unknown modes; accepts open, none
- **`_build_extra_docker_args`** — permits --env/-e/--label/--hostname; denies --volume/--network/--device/--publish without opt-in; permits --device/--publish/-p with opt-in env vars

Docker mocked via `test/helpers/docker` stub on `$PATH`. `test/libs/` gitignored; local install: `git clone --depth=1 https://github.com/bats-core/bats-core test/libs/bats-core`. CI clones bats-core in a `unit-tests` job that gates the `build` job. All 40 tests pass.

### Add logs, status, and version subcommands (#39 #40)

Three subcommands added in one pass:

- **`faradai logs`** — dispatches to `docker logs <container>` after the daemon check; extra args passed through (e.g. `-f`, `--tail 100`). Placed before the image pre-flight so it works even when the image is stale or absent.
- **`faradai status`** — dispatches to `docker inspect` with a formatted template showing container name, state, started-at, and image. Clear error if the container doesn't exist.
- **`faradai version` / `faradai --version`** — prints `faradai <version>`; dispatched before the docker pre-flight so it works with no daemon. Version string embedded as `_FARADAI_VERSION="0.1.0"` at the top of the script. Both `logs`, `status`, and `version` added to `_KNOWN_CMDS` so they are not misinterpreted as container names after `-a`.

### Fix smoketest ssh-add fingerprint exposure (#46)

`ssh-add -l` in SMOKETEST.md printed key fingerprints and email labels into the conversation context. Replaced with `ssh-add -l | wc -l` — confirms at least one key is loaded without exposing identity metadata.

### Fix CI smoke test to exercise entrypoint.sh (#42)

The existing CI smoke test used `--entrypoint /bin/bash`, bypassing `entrypoint.sh` entirely. Added a second step, "Smoke test (entrypoint dispatch)", that runs `claude --version`, `aider --version`, and `bash -c "echo ok"` through the real entrypoint — covering all three dispatch branches. Original tool-availability step retained and renamed for clarity.

---

## Session 34 — 2026-05-22

### Known issues and limitations section in README

Added a "Known issues and limitations" section to README covering: Docker filesystem I/O overhead, no GPU passthrough, local LSP limitations, and multi-user `docker rm` name collision. Also updated the stale `gh` auth troubleshooting entry — it previously said credentials weren't persisted, which was true before #33 was fixed.

---

## Session 35 — 2026-05-22

### Bump Node 18 → 22 LTS, consolidate apt layers, add --shm-size (#54 #43)

Node 18 reached end-of-life in April 2025. Switched both builder and final stages to NodeSource `node_22.x` channel; pinned to `nodejs=22.22.2-1nodesource1` after verifying the installed version in a running container.

The NodeSource addition introduced two extra `apt-get update` calls (one per repo added). Consolidated: both NodeSource and gh CLI repos are now registered back-to-back before a single combined `apt-get update` + `apt-get install` covering all packages. `gnupg` (used only for keyring import) is purged with `apt-get autoremove` at the end of the layer — it was previously left installed in the final image unnecessarily.

Also added `--shm-size=1g` to `docker run`. Claude Code is Electron-based and the default Docker 64 MB `/dev/shm` causes crashes and silent failures.

**Josiah noted** the build was noticeably slower after the initial NodeSource switch, which prompted the apt consolidation. Build time recovered after the restructure. New container verified working.

### Fix CI linting failures introduced by Node 22 changes

Two hadolint warnings surfaced in CI after the Dockerfile restructure:

- **DL4006** — builder stage had pipes but no `SHELL` directive. Added `SHELL ["/bin/bash", "-o", "pipefail", "-c"]` to the builder stage.
- **DL3008** — `ca-certificates`, `curl`, and `gnupg` were unpinned in the builder stage; `ca-certificates` and `gnupg` unpinned in the final stage. Pinned all. `gnupg` version required querying the exact digest-pinned base image directly (`docker run --rm ubuntu:24.04@sha256:...`) — the host's apt repos had a different version (`2.2.27`) than the image (`2.4.4-2ubuntu17.4`).

A shellcheck SC2015 warning on the `&&/||` chain in `_validate_cpus` was also caught and fixed — rewritten as a proper `if` statement.

---

## Session 36 — 2026-05-22

### Rename TODO.md → ROADMAP.md; README overhaul; CHANGELOG and DECISIONLOG (#47 #48)

**TODO → ROADMAP:** Renamed `TODO.md` to `ROADMAP.md` via `git mv`. Two internal README links updated.

**README overhaul:**
- Added bold tagline: "OS-level filesystem boundary for AI coding agents."
- Added `## About this project` section near the top — explicitly calls out `BUILDLOG.md` as proof of intentional human oversight, not unsupervised AI.
- Added `## Development` section — explains the BUILDLOG/DECISIONLOG split (see below) and links to `CONTRIBUTING.md`.
- Fixed `ring-feedback.md` finding #15 (issue #47): added SSH troubleshooting entry pointing users to the Host SSH agent setup section. Ring flagged "SSH push/pull fails inside the container" — the forwarding itself works and has been verified; the failure mode is passphrase-protected keys not being loaded via `ssh-add` before launch, not a forwarding bug.

**CHANGELOG.md (#48):** Created. Josiah's intent for `v0.1.0-alpha.1` is to get the release infrastructure right before populating the log; the file is minimal by design.

**Delete `ring-feedback.md`:** All 18 Ring findings have been fixed, triaged to GitHub issues, or explicitly accepted. The file no longer serves a tracking function; GitHub issues are the source of truth.

### Decision: BUILDLOG → DECISIONLOG after v0.1.0-alpha.1

The question arose: after the first release, should ongoing decisions continue in BUILDLOG, or move to GitHub issues?

**GitHub issues** were considered — standard engineering practice, richer metadata (labels, milestones, assignees). Rejected for two reasons: (1) they live on GitHub's servers, not in the repo, making migration to GitLab or another host lossy or complex; (2) issues are task-oriented and don't naturally capture architectural reasoning the way a decision log does.

**Keeping BUILDLOG indefinitely** was rejected because the session-log format accumulates unboundedly and becomes unwieldy.

---

## Session 37 — 2026-05-22 16:19 UTC

### Code fixes: combined short flags, USER subshell, uninstall data notice (#42 #46 #55)

**#55** — `USER="$(whoami)"` replaced with `USER="${USER:-$(whoami)}"`. `$USER` is set by the shell in all normal environments; the subshell only fires as a fallback.

**#42** — `_build_extra_docker_args` rejected combined short-flag forms like `-eFOO=bar`. The existing check matched `"${arg}" == "${flag}"` or `"${arg}" == "${flag}="*` but not the combined form. Added a third branch: if `${flag}` is a single-char flag (regex `^-[^-]$`) and `${arg}` starts with that flag followed by one or more characters, it's permitted. Two new bats tests added: one confirming `-eFOO=bar` passes, one confirming an unknown combined flag `-xFOO` is still rejected. Test suite now 42 tests.

**#46** — `uninstall-faradai` now prints a "not removed" notice after `Done.` listing `~/.claude/`, `~/.claude.json`, `~/.config/gh/`, and the source directory. An initial draft used `$(pwd)` in an echo statement which expanded to a hardcoded path at write time (not at runtime as intended) — caught before commit, replaced with a static string. README Upgrading section also updated with a table of what persists.

### faradai update overhaul: tag-based default, integrity check, --branch opt-in (#44)

The original `update` command cloned from master HEAD with no integrity check. The new implementation:

- **Default:** `git ls-remote --tags --sort=-version:refname` resolves the latest `v*` semver tag without a full clone, then `git clone --depth=1 --branch <tag>` fetches exactly that ref. After cloning, `git describe --exact-match --tags HEAD` verifies the cloned HEAD carries the expected tag — ensures `install.sh` runs from a known immutable ref, not an arbitrary commit that happened to land on the branch tip between the query and the clone.
- **`--branch NAME`:** clones the tip of the named branch with `--depth=1` and skips the integrity check (branch tips are mutable by design). Prints a stability warning. Covers master, develop, or any feature branch — useful for testing unreleased changes.

**Code style issue:** The first draft of the update block was rejected by Josiah: missing blank lines between `if` blocks, all logic inlined in the dispatch block, and `|| { echo ...; exit 1; }` chains instead of `if !` patterns. Rewritten to comply with Google Shell Style Guide conventions: blank lines between logical blocks, `if`/`if !` error handling throughout, and three extracted functions:

- `_update_faradai([--branch NAME])` — top-level function with a doc comment explaining both code paths; dispatch block collapses to a single call.
- `_resolve_latest_tag(repo)` — queries the remote and prints the latest tag, returns 1 if none found.
- `_verify_update_tag(update_dir, expected)` — verifies the cloned HEAD matches the expected tag.

**SC2064 trap pattern:** `_update_faradai` uses a local variable `update_dir` for the temp dir. `trap 'rm -rf ...' EXIT` with single quotes would capture the variable name, not the value, causing the cleanup to silently fail after the function returns. Used double quotes with a `# shellcheck disable=SC2064` comment to expand the path immediately at trap-set time — the standard pattern when cleanup must outlive the local variable's scope.

### Add shellcheck v0.11.0 to image

`shellcheck` is used heavily during development for linting shell scripts, but was not available inside the container. Ubuntu 24.04 includes shellcheck only in the `universe` component, which is not enabled in the base Docker image. Rather than enabling universe for one tool, installed the static binary from GitHub releases:

- Builder stage: `ARG SHELLCHECK_VERSION=v0.11.0`, single `RUN curl | tar` to extract the binary to `/tmp/shellcheck`. Uses `.tar.gz` (not `.tar.xz`) to avoid needing `xz-utils`. Separate RUN layer for cache efficiency — changes only when `SHELLCHECK_VERSION` changes.
- Final stage: `COPY --chmod=755 --from=builder /tmp/shellcheck /usr/local/bin/shellcheck`. The `--chmod=755` is explicit because Docker `COPY` does not guarantee preserving the execute bit across stages.

CI smoke test updated to verify `shellcheck --version`. README "What's in the image" updated.

---

## Session 38 — 2026-05-22 17:04 UTC

### Dual code review: Ring-2.6-1T and Opus; triage and issue logging

Ran Ring-2.6-1T (via aider) and Opus independently on the full codebase. Each finding was validated against the actual source before logging.

**Discarded findings (not real):**
- Opus: "update clones master with no integrity check" — fixed this session before the review ran.
- Opus: "README says working directory defaults to ~/Development/personal" — not in the file; hallucination.
- Opus: "no shellcheck/hadolint CI" — both have been in CI since session 33; Ring confirmed them present.

**Real findings logged as GitHub issues:**

- **#59** — Username mismatch footgun (Opus). `USERNAME` is baked into the image at build time; the runtime script constructs mount paths from `$USER`. If a different host user runs `faradai`, all mounts land at paths that don't exist inside the container. Failure is a confusing permission error. Promoted to **Now** — likely to affect new users immediately.
- **#60** — `trap _cleanup` is dead code (Opus). Set at line 345 immediately before `exec docker run` at line 402. Once `exec` replaces the process, the trap is gone. Container has `--rm` so Docker handles cleanup regardless. The comment acknowledges the "narrow window" but in that window no container exists yet, so `_cleanup` would silently no-op.
- **#61** — `-v` flag unhandled; `-a -v` footgun (Ring + Opus). `-v` is not in the subcommand dispatch or `_KNOWN_CMDS`. `faradai -v` falls through to docker. `faradai -a -v` creates a container named `faradai--v`.
- **#62** — bats-core unpinned in CI (Ring). CI clones `--depth=1` with no tag pin; can drift.
- **#63** — `build.sh` symlink handling (Ring). `dirname "$0"` resolves to the symlink's directory, not the target's.
- **#64** — Three documentation gaps (Ring + Opus): tmux not listed in "What's in the image"; URL casing inconsistency (`faradai` vs `FaradAI`); `.credentials.json :ro` is not explicitly noted as "not a secrecy mechanism" the way `~/.aider.conf.yml` is.

ROADMAP updated: #59 moved to **Now**; #60–64 added to **Later**.

---

## Session 39 — 2026-05-22 18:29 UTC

### Cage framing clarification in README; remove version assumptions

Opus flagged that "the AI inside has full capability, but can only reach what you explicitly mount" overstates the guarantee since network egress is open by default. Two changes:

**Intro paragraph:** Reworded the cage metaphor sentence to be precise: "the cage is the filesystem boundary plus the absence of the Docker socket." Added that the agent can reach the internet freely. Described the container as running CLI-based AI coding agents generally, not just Claude Code and aider — the pattern is not specific to either. Removed "v1"/"v2" version references from the intro (and throughout README and ROADMAP) since the version roadmap isn't settled.

**Security model / network section:** Made the cage boundary limitation more prominent ("This is the current boundary of the Faraday cage metaphor"), explicitly named both constraints (filesystem + no Docker socket), and linked the credential broker roadmap items (#29, #30, #31) directly rather than just referencing "v2."

**Opus "update clones master" finding:** This was a stale finding — the tag-based update with integrity verification was implemented earlier in this session before the review ran. No change needed.

**Resolution:** BUILDLOG.md is frozen as a historical record after `v0.1.0-alpha.1`. Significant architectural and security decisions made post-release are captured in `DECISIONLOG.md` — a terse, indexed log with one entry per decision. Task-level work continues to live in GitHub issues and commit messages. CHANGELOG and DECISIONLOG cross-reference each other.

---

## Session 40 — 2026-05-22 18:35 UTC

### Username mismatch pre-flight check (#59)

`USERNAME` is baked into the image at build time. The faradai script constructs all mount paths from `$USER` at runtime. If the host user running faradai differs from the user the image was built for, mounts land at paths that don't exist inside the container — the failure mode is a confusing permission error with no clear cause.

**Fix:** Added `org.opencontainers.image.faradai.username="${USERNAME}"` to the Dockerfile `LABEL` block. At runtime, `_check_image_user()` reads that label via `docker image inspect --format`, compares it to `$USER`, and exits with a clear message if they differ. Images predating the label (empty value) pass silently for backward compatibility.

**Implementation note:** The function is called immediately after the image existence check in the docker pre-flight section, before any mount path construction. Extracted as a standalone function following the existing `_validate_*` / `_check_*` pattern.

**Tests:** Three bats tests added (46/46 pass):
- label matches user → passes
- label mismatches user → exits 1 with clear error
- label absent → skips silently

One test failure during development: the initial test used `MOCK_IMAGE_USER="${USER}"` and `MOCK_IMAGE_USER="otheruser"` without explicitly setting `$USER`, relying on the test environment's value. The mismatch test exited 1 but without the expected message, suggesting a different exit path was reached first. Fixed by making both tests hermetic: explicitly set `USER="testuser"` in the test env so the comparison is fully predictable regardless of the host user.

The docker mock's `image)` case was extended to echo `MOCK_IMAGE_USER` when set, allowing `_check_image_user` to be unit-tested without a real image.

---

## Session 41 — 2026-05-22

### Rash language spike (#40)

**Trigger:** Josiah observed that `faradai` at 442 lines is well past the 150–200 line threshold where shell scripts start becoming maintenance liabilities. Issue #40 (migrate to Rash) was already open; this session was an exploratory spike to evaluate whether the move would be worthwhile.

**Approach — intentional AI code generation for discernment:** Rather than writing the spike by hand, Josiah had Claude generate a full Rash rewrite of `faradai` across several passes. The explicit intent was to get a feel for what the language switch would look like in practice — using AI generation to compress the exploration time — while making clear that any actual rewrite would be written by Josiah himself. AI-generated code aids discernment; it does not replace judgment.

The spike went through three passes:
1. Direct translation — establish baseline
2. Shell-first — minimize Racket, use shell line syntax wherever possible
3. Racket-only-where-it-wins — identify the genuine high-value areas; leave everything else as shell lines

**What Rash actually is:** The key discovery is that Rash's target audience runs the other direction from what was hoped. Rash is Racket with shell pipeline syntax for command invocation — not a shell with Racket available for complex logic. Control flow (`when`, `unless`, `match`, `define`, `let`, `with-handlers`) is always Racket/Lisp. An ops engineer reading the file would still be reading mostly Lisp. Shell syntax only applies at the command-invocation layer.

**Where Racket genuinely wins:**
- Validation (`_validate_memory`, `_validate_cpus`, etc.) — real regex, real numeric types, no `awk` for float comparison, no `BASH_REMATCH` gymnastics. The clearest win.
- `_build_extra_docker_args` — iterating a word-split list with prefix matching is clean with `for/or`; gnarly in bash.
- Optional mount list building + `run-pipeline` — conditional flag lists built as Racket lists splice automatically into the `docker run` invocation, replacing bash array quoting.

**Line count:** At equivalent writing density (reasonable spacing and comments), the Rash spike lands at 402 lines vs. the bash original at 442 — roughly 40 lines / 9% reduction. The savings are real but modest.

**Portability note surfaced:** The bash script already uses `read -ra`, `(( ))` arithmetic, and `[[ =~ ]]` with `BASH_REMATCH` — none guaranteed on bash 3.2, which is what macOS ships. The "it's just bash" portability story already has an asterisk. Rash's `raco exe` can produce a ~56MB self-contained binary with no host Racket dependency, similar to a Go binary but without the glibc concern.

**Open questions** documented in a comment on issue #40 (see also `spike/rash-migration` branch):
- Exit code propagation from interactive `docker run` via `run-pipeline`
- Shell lines inside Racket forms (`lambda`, `match` bodies) — relies on Linea reader applying throughout, unverified
- `&permissive` inside `#{}` capture blocks — validity unconfirmed
- Packaging story (source + bundled Racket vs. compiled `raco exe`)
- Whether Python would be a better call — equivalent validation wins, universally readable control flow, smaller adoption ask

**Outcome:** Spike committed to `spike/rash-migration`, findings and open questions posted to issue #40. No decision made on the migration; deferred until v1 feature set stabilizes per the original issue.

---

## Session 42 — 2026-05-23

### CLI grammar change: `-n`/`-a` → `-c`/`-a`/`-n`

The original CLI grammar had `-n NAME` doing double duty as both a name selector and an implicit mode selector (create mode). `-a` optionally consumed the next positional token as a container name, which required a hardcoded `_KNOWN_CMDS` list to distinguish container names from subcommand tokens.

**Josiah directed** replacing this with orthogonal flags:
- `-c` — create mode
- `-a` — attach mode
- `-n NAME` — name selector, independent of mode

This eliminated `_KNOWN_CMDS` entirely and the lookahead logic in the `-a` case. The simplification was immediately visible: the parser went from a complex multi-case loop with lookahead to a clean flag parser where each flag does exactly one thing.

README, `_usage`, and all stale error messages updated to reflect the new grammar.

### External refactoring assessment and plan

Josiah shared a GPT refactoring assessment alongside Sonnet's own assessment. Both identified the same core issues (no `main()`, split dispatch hidden ordering, interactive prompts tangled with config, final `docker run` coupled to every builder), but GPT's assessment was stronger in two places:

1. **`$USER` ordering bug** — `_check_image_user` runs before `USER="${USER:-$(whoami)}"`, so an unset `$USER` produces a false-positive mismatch error. Sonnet missed this; GPT caught it.
2. **Single `DOCKER_RUN_ARGS` accumulator** — GPT proposed replacing per-category arrays (`NETWORK_ARGS`, `GH_CONFIG_ARGS`, etc.) with named appender functions that all write to a single `DOCKER_RUN_ARGS` array. Cleaner than Sonnet's "keep arrays separate" position.

**`REFACTOR-cli-phases.md` created** — a detailed three-pass refactor plan authored by Sonnet capturing the full architectural intent, test strategy (including what new tests become possible with a source-vs-execute guard), open decisions, and risk notes. Explicitly a forward-planning document distinct from BUILDLOG, CHANGELOG, and DECISIONLOG.

### Refactoring execution — TDD throughout

Josiah directed a strict TDD approach: write failing tests first, confirm they fail, implement, confirm they pass. Three passes executed in this session:

**Pass 0 — test catch-up.** The existing test suite had three stale failures from the CLI grammar change. Fixed, and added tests for all new flag combinations: `-c`, `-a -n NAME`, `-c -n NAME`, `-n NAME` alone (auto mode), and the new `-a`/`-c` mutual exclusion. Reorganised the flag parser test section into four logical groups: mode flags, `-n` validation, flag combinations, stop-at-first-non-flag. Added two baseline tests that were missing entirely (bare `faradai`, `-a` alone). Suite went from 46 to 62 tests.

**Pass 1 — CLI parser extraction.** Extracted the inline flag parsing block into `_parse_cli_flags`. Key decisions made during this pass:

- **Stop-at-first-non-flag:** New parser stops at the first non-flag token and captures everything after as `_CMD_ARGS`. Old parser collected all non-flag tokens into `_remaining` and continued processing — meaning `faradai bash -c` would process `-c` as a flag. Tests confirmed the new behavior and pinned it.
- **`-n` validation improved:** Added rejection of empty strings and whitespace-only names (the existing check only caught flag-looking tokens). Used `[[ -z "${arg//[[:space:]]/}" ]]` to catch all whitespace classes including tabs. Added rejection of duplicate `-n` flags (previously silent last-wins).
- **Rename to `_parse_cli_flags`:** Josiah's idea — the name is self-documenting at the call site, making the `# ── flag parsing ──` section header redundant. Removed it.
- **`_die` helper introduced** for consistent error formatting, to be reused by later phase functions.

Tests added per discovery: empty NAME, whitespace NAME, tab NAME, duplicate `-n`, flag-after-subcommand doesn't set mode (two cases), flag order independence.

**Pass 2 — phase extraction.** Wrapped the entire bottom half in `main()`, added a source-vs-execute guard, and extracted all phase functions:

`_init_defaults`, `_dispatch_meta_commands`, `_preflight_docker`, `_dispatch_docker_metadata_commands`, `_ensure_image_ready`, `_resolve_workdir`, `_resolve_container_state`, `_maybe_attach_existing`, `_confirm_trust_workdir`, `_prepare_container_name_for_create`, `_setup_cleanup_trap`, `_load_runtime_config`, `_debug_print_plan`.

Created `test/sourced.bats` — a new test file that sources `faradai` (safe only after the source-guard exists) and tests phase functions directly, bypassing docker mock limitations. Added 36 tests covering `_init_defaults`, `_parse_cli_flags` (direct global inspection), `_dispatch_meta_commands`, `_maybe_attach_existing` (with `_CONTAINER_RUNNING` stubbed directly — no docker mock needed), `_resolve_workdir`, `_dispatch_docker_metadata_commands`, and `_load_runtime_config`.

**Key discovery during Pass 2 — `set -e` and last-statement function exit codes:**

`[[ condition ]] && cmd` as the **last statement in a function** makes the function's exit code 1 when the condition is false. Under `set -e`, the caller then exits. This is silent and confusing — the function "works" if followed by any other statement, but returns failure when it's the tail.

The symptom: every test expecting exit 0 failed after extracting `_load_runtime_config`. `[[ NETWORK_MODE == "none" ]] && NETWORK_ARGS=(--network none)` was the last line — harmless at the top level of the old script (more code followed it), but fatal as the tail of a function.

Fix: `if [[ condition ]]; then cmd; fi`. Two lines instead of one, zero ambiguity about exit code. Applies to any `[[ ]] && cmd` or `(( )) && cmd` used as a function's final statement. Pass 3's named appender functions will all end with conditional array appends — must use `if` there.

**`$USER` ordering bug fixed** in `_init_defaults`: `USER="${USER:-$(whoami)}"` now runs before any other phase, including `_check_image_user`. Regression test added to `unit.bats`: `env -u USER MOCK_IMAGE_USER="$(whoami)" "${FARADAI}"` must exit 0 (previously produced a false-positive mismatch error).

**Final suite count:** 99 tests, all passing.

**Pass 3 — `DOCKER_RUN_ARGS` builder extraction.** Replaced the inline mount-building block in `main()` with named appender functions that each own one policy area and write to a single `DOCKER_RUN_ARGS` accumulator:

`_append_runtime_flags`, `_append_resource_args`, `_append_security_args`, `_append_network_args`, `_append_credential_mount_args`, `_append_project_mount_args`, `_append_extra_docker_args`, `_build_docker_run_args` (orchestrator), `_exec_docker_run`.

Also extracted `_handle_ssh_agent_forwarding` (named to reflect it handles the decision either way, not just "confirms" the happy path), which sets `_SSH_AGENT_APPROVED` — read later by `_append_credential_mount_args`. `_SSH_AGENT_APPROVED=0` added to `_init_defaults`.

`_build_extra_docker_args` (old per-category array pattern) and the `NETWORK_ARGS` block in `_load_runtime_config` removed as dead code. `unit.bats` test names updated from `_build_extra_docker_args` to `_append_extra_docker_args`.

`set -e` + last-statement pitfall avoided throughout: all conditional appends in appender functions use `if [[ ]]; then; fi` rather than `[[ ]] && cmd` — the latter returns 1 as the function's exit code when the condition is false, which propagates as failure under `set -e` in the caller.

`test/sourced.bats` extended with 40 new tests covering all appenders (direct `DOCKER_RUN_ARGS` inspection), `_handle_ssh_agent_forwarding` (all branches including interactive y/n via process substitution), and `_build_docker_run_args` ordering guards (`--name` before image, image before CMD_ARGS, `-w` immediately before image).

**Final suite count:** 139 tests, all passing.

### Near-miss: BUILDLOG overwrite

When asked to update the BUILDLOG, Sonnet used `Write` instead of `Edit` — which would have replaced the entire file with only the content it had seen (sessions 1, 2, and 41; sessions 3–40 were never read). Josiah caught and rejected the tool call before it executed. The correct tool was `Edit`, appending only the new session entry. Lesson: `Write` is for new files or files read in full in the same conversation. Anything else that needs a partial update requires `Edit`.

### Opus code review and coupling fixes

After the refactoring passes were complete, Josiah had Opus review the script for tight coupling between functions. Opus identified 6 issues:

1. `_parse_cli_flags` Reads comment did not list `_MODE`, which the function reads to detect the `-a -c` mutex.
2. `_confirm_trust_workdir` used `_trust_answer` without `local`, leaking the variable into the global scope.
3. `_exec_docker_run` had been inlined into `main()` by the linter, leaving a test in `sourced.bats` that called it as a function — test and code were silently diverged.
4. `_append_credential_mount_args` contained a `mkdir -p "${HOME}/.config/gh"` side effect — a filesystem mutation embedded in a pure arg-builder function.
5. `_setup_cleanup_trap` performed two unrelated actions: removing a stale container (`docker rm -f`) and registering the `trap`. The name implied only the second.
6. No temporal-dependency notes on functions where ordering is load-bearing (e.g., `_append_credential_mount_args` must run after `_handle_ssh_agent_forwarding`).

All six were applied. The changes were TDD-ordered where new functions were involved: failing tests for `_ensure_host_dirs` and `_remove_stale_container` were written and confirmed to fail before the implementations were added.

Specific fixes:
- **Fix 1:** `_parse_cli_flags` Reads line updated to include `_MODE (initialised by _init_defaults)`.
- **Fix 2:** `local _trust_answer` added in `_confirm_trust_workdir`.
- **Fix 3:** `_exec_docker_run` restored as a named function; `main()` calls it instead of inlining `exec docker run`. Test passes again.
- **Fix 4:** `mkdir -p "${HOME}/.config/gh"` extracted to a new `_ensure_host_dirs` phase. `main()` calls `_ensure_host_dirs` immediately before `_build_docker_run_args`. `_append_credential_mount_args` is now a pure arg-builder with no side effects.
- **Fix 5:** `_setup_cleanup_trap` split into `_remove_stale_container` (the `docker rm -f` step) and `_setup_cleanup_trap` (the `trap` registration only). `main()` calls them in sequence.
- **Fix 6:** Temporal-dependency notes added to `_ensure_host_dirs` ("Must run before `_append_credential_mount_args`") and `_append_credential_mount_args` ("Must run after `_handle_ssh_agent_forwarding` and after `_ensure_host_dirs`").

**Final suite count:** 142 tests, all passing (79 sourced + 63 unit).

### OpenRouter Fusion review — issues #74–#84

Josiah ran an OpenRouter Fusion quorum review against three files: `faradai`, `Dockerfile`, and `README.md`. Quorum models: Ring-2.6-1T, Laguna M.1, CoBuddy. Judge model: auto. The raw fusion output was summarized by GPT, then the summary was refined in a second pass to recover findings the first pass had compressed out. The refined output was used to file issues and update the roadmap.

**New issues filed (#74–#84):**

- **#74** — Dockerfile ShellCheck download hardcoded to `linux.x86_64`; breaks ARM64 Linux builds. Fix: select architecture at build time via Docker `TARGETARCH`.
- **#75** — `${var,,}` (Bash 4+ syntax) used in `faradai` CLI; macOS ships Bash 3.2 by default. Fix: portable `tr '[:upper:]' '[:lower:]'` substitution, or explicit Bash 4+ version check at startup.
- **#76** — `~/.claude.json` and `~/.gitconfig` mounted unconditionally; Docker bind mount fails or creates spurious host directories if source files are absent on a clean machine. Fix: mount only if present; separate required paths (preflight with explicit error) from optional paths (skip if absent).
- **#77** — `install.sh` does not `cd` to its own repo root; breaks when invoked from a temp clone during `faradai update`, which calls `install.sh` with the caller's working directory. Fix: `SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"; cd "${SCRIPT_DIR}"` before any repo-relative operations.
- **#78** — `FARADAI_WORKDIR` accepts relative paths; Docker `-v` and `-w` require absolute paths. Relative values produce invalid or silently wrong bind mounts. Fix: normalize via `cd && pwd -P`, or reject non-absolute values with a clear error.
- **#79** — `read` used under `set -e` in prompt functions (`_confirm_trust_workdir`, `_handle_ssh_agent_forwarding`) without a TTY check; on EOF (piped input, CI) `read` returns non-zero and the script exits uncleanly. Fix: centralize prompting through a helper that checks `[[ -t 0 && -t 1 ]]` and directs non-interactive callers to the relevant `FARADAI_TRUST_*` variable.
- **#80** — `-c` conflict error hint emits `faradai -a -n faradai` when `_CONTAINER_NAME` is the default `"faradai"`; the correct command is `faradai -a`. Fix: special-case the default container name in the conflict path, matching the pattern used elsewhere.
- **#81** — `-n NAME` validates for blank and flag-like values but not Docker naming rules; names with invalid characters pass FaradAI's check and fail later with opaque Docker errors. Fix: validate the composed container name against `^[A-Za-z0-9][A-Za-z0-9_.-]*$`.
- **#82** — No managed container label; uninstall must identify FaradAI containers by name pattern, which fails for non-default names and risks over- or under-scoping. Fix: add `--label dev.faradai.managed=true` at `docker run`; scope uninstall via `--filter label=dev.faradai.managed=true`. Constraint: uninstall must never remove `~/.claude`, `~/.config/gh`, or source/project directories.
- **#83** — Exact apt package versions pinned without pinning the underlying repositories; upstream repos mutate and old versions disappear, causing future build failures. This carries maintenance cost without guaranteeing reproducibility. Fix: choose one strategy — either pin only major external tool versions and relax distro patch pins (pragmatic), or adopt snapshot repositories with checksums (strict).
- **#84** — README docs: (1) "hard OS-level boundary" overstates the isolation guarantee — more precise: "bind-mount / namespace / cgroup boundary, stronger than prompt-only, weaker than a VM"; (2) macOS Bash version requirement not stated; (3) Docker Desktop SSH-agent socket forwarding caveat missing (distinct from general macOS caveat); (4) `logs`/`status` usefulness with `--rm` not documented; (5) "npm not included" claim unverified given NodeSource install; (6) `./build.sh` reference in Troubleshooting unverified.

**Existing issues promoted:**

- **#50** (`_validate_cpus`/`_validate_memory` integer-truncating upper-bound allows `128.9` CPUs and `512.9g` RAM) — moved from Later to Now; priority upgraded from low to high.
- **#68** (no preflight check for `~/.claude` directory; missing credentials produce silent mount failure) — moved from Later to Now; `priority: high` label added.

**Items the review did not surface** (already filed): #61 (`-v` short flag falls through to Docker unhandled), #42 (combined short-flag forms rejected by `_build_extra_docker_args`), #60 (`trap _cleanup` dead code), #59 (runtime `$USER` must match baked-in USERNAME).

**Items the review noted as already addressed:** update flow tag-consistency check (resolves tag, clones exact ref, verifies HEAD matches — already in place); strategic future items (strict profile, per-project Claude state, credential broker) already tracked as #29–#31 in Planned.

**Two-step summarization:** The first GPT summary compressed `#77` (install.sh repo-root cd) and the `entrypoint.sh` dispatch-only design principle out of the output. Both were recovered in the refinement pass.

**Manual roadmap adjustments (Josiah):** After the automated issue triage, three items were moved from Later to Now: #56 (`entrypoint.sh` `_usage()` stale), #60 (`trap _cleanup` dead code), #62 (pin bats-core in CI). The Now refactoring section was renamed "Refactoring and De-linting" to better reflect its scope.

### Session continuation — Task 2: fix stopped-container dead-end (#67 + #80)

Resumed from a context-compacted session. Task 1 (#79: `_is_interactive` / `_prompt_yes_no` / `_prompt_choice` helpers) was already complete at the start of this session.

**Context management:** Josiah asked whether tasks could be moved to a new session to reduce context window usage; the `/compact` already run was sufficient and the session continued in place.

**ROADMAP.md cleanup:** The manual priority adjustments (`#56`, `#60`, `#62` → Now) had been noted in BUILDLOG but the actual ROADMAP.md edits were uncommitted. Applied as a separate docs commit.

**Task 2 changes — 9 new tests, 104 total, all passing:**

- `_prepare_container_name_for_create` (#80): special-cased `_CONTAINER_NAME == "faradai"` to emit `faradai -a` instead of the redundant `faradai -a -n faradai`. Added 3 tests covering attach mode (no-op), default name conflict, and named-container conflict.
- `_remove_stale_container` (#67): rewrote to branch on `_CONTAINER_RUNNING` rather than calling `docker rm -f` unconditionally:
  - `""` → return silently (no container found)
  - `"true"` → return silently (running container; `_prepare_container_name_for_create` handles the conflict)
  - `"false"` → prompt via `_prompt_yes_no` with explicit state-loss warning; die if declined; `docker rm -f` if confirmed
  Comment block updated to document the three-state invariant and the ephemeral-container rationale. Added 6 tests covering all three `_CONTAINER_RUNNING` branches plus non-interactive and decline paths.
- `main()`: swapped call order — `_remove_stale_container` now runs before `_prepare_container_name_for_create`, so a stopped container is cleaned up before the running-container conflict check. This breaks the dead-end where `-c` mode found a stopped container via `docker inspect` and printed an attach hint for an unattachable container.

### Remove `_cleanup` / `_setup_cleanup_trap` dead code (#60)

Josiah asked why `_cleanup` had been extracted from `_setup_cleanup_trap` given that no tests existed for either. The answer: the comment said "extracted to enhance testability" but the tests were never written. More fundamentally, the entire construct is dead code — `exec docker run` replaces the bash process before the trap can ever fire, and `--rm` already handles container removal on exit. Both functions and the `_setup_cleanup_trap` call in `main()` were deleted. 104 tests still pass. Issue #60 closed via `gh`.

### Task 3: `_preflight_credentials` with recovery flow (#68) — in progress

**Josiah caught:** during TDD test-writing, Josiah spotted that `_CMD_ARGS[0]` could be `"bash"` — the user explicitly booting a shell, not an AI tool. The original boot-target determination defaulted any unrecognised first arg to `"claude"`, so `faradai -c bash` would wrongly check Claude credentials and potentially trigger the recovery flow. Fixed by replacing the two-branch if/elif with a `case` that returns 0 immediately for any target that is neither `claude` nor `aider`. A 10th test was added to pin this: `_CMD_ARGS=("bash")` with Claude creds absent must return 0 silently.

**`_is_interactive` fix:** changed from `[[ -t 0 && -t 1 ]]` to `[[ -t 0 && -t 2 ]]` (stdin + stderr). `_prompt_choice` writes its result to stdout and must be called via `$()`; inside `$()` stdout is not a TTY, so the old check would have fired "interactive selection required" even in a real terminal. Checking stderr is semantically correct — it stays attached to the terminal even when stdout is captured.

### Task 4: fix decimal upper-bound in `_validate_cpus` / `_validate_memory` (#50)

Both validators used `(( int > limit ))` where `int` was the integer part of the value (`${val%%.*}` / `${BASH_REMATCH[1]%%.*}`). This let `128.5` CPUs and `512.5g` RAM pass — the decimal was stripped before the comparison. Fixed by replacing both integer comparisons with `awk`, which compares the full float. Upper-bound check is now an `if ! awk ...; then exit 1; fi` block in both functions — explicit control flow rather than a trailing `|| exit 1`.

**Josiah directed:** use `if !` blocks rather than trailing `|| exit 1` after awk invocations; keeps control flow explicit and avoids hiding logic after a long parameter list.

3 new tests (unit.bats): `512.5g` rejects, `524288.5m` rejects, `128.5` CPUs rejects. All pre-implementation failures confirmed.

### Task 5: make `~/.claude.json` and `~/.gitconfig` mounts conditional (#76)

Both files were mounted unconditionally in `_append_credential_mount_args`. Docker bind-mounts a missing source as a directory, which is silent and wrong; any user without Claude Desktop (no `~/.claude.json`) or without git configured (no `~/.gitconfig`) would hit this on first run.

Introduced `_maybe_mount_file <src> <dst> [<mode>]` — appends a `-v` mount only when the source file exists, silently returning 0 otherwise. Refactored `_append_credential_mount_args` to use it for all three optional file mounts: `.claude.json`, `.gitconfig`, and `.aider.conf.yml` (which was already conditional via an inline `if [[ -f ]]`).

5 new tests (sourced.bats): 3 for `_maybe_mount_file` (present, absent, mode suffix) and 2 for the absent-file branches of `.claude.json` and `.gitconfig`. Two existing "always mounts" test names updated to "present — mount included". 185 tests total, all passing.

### Snapshot repo bootstrap: `ca-certificates` from live mirror (#83)

The `base` stage installs `ca-certificates` from the default Ubuntu sources before switching apt to the snapshot URL. Standard ops/sec bootstrapping — the ubuntu:24.04 base image ships without `ca-certificates`, so HTTPS sources are unreachable until it is present. `ca-certificates` is intentionally not pulled from the snapshot: CA bundles need to be current (expired/revoked roots, newly added roots), so freezing them to a point-in-time snapshot would be actively wrong.

---

## Nix in the cage: a "Bad file descriptor" whodunit — 2026-06-16 (#99)

> The BUILDLOG stopped tracking every change after 0.3.0-alpha.1; entries since are selective. This one is here on purpose — the debugging arc is a good story and a candidate blog post, so it's written as a narrative rather than a terse changelog line.

### Setup

With `FARADAI_MOUNT_NIX_STORE=1`, `nix develop` against the PPN95 flake died inside the container with:

```
error: acquiring/releasing lock: Bad file descriptor
```

The same flake, the same shared `/nix`, worked fine on the host. So: what does running inside the cage change, and why does a *lock*, of all things, come back `EBADF`?

### Wrong theory #1 — "it's a Nix bug" (and the security tripwire)

The error reads like a classic POSIX gotcha: open a file `O_RDONLY`, then ask for a write lock, and the kernel hands you `EBADF`. Plausible story: Nix opens a `temproots` GC-root file read-only and write-locks it. The tidy fix seemed to be forwarding the host's `nix-daemon` socket into the container so container-`nix` could lock via the host.

**Josiah killed that immediately, and correctly:** the daemon can *write the real store*. Routing container operations through it would tunnel straight past the read-only `/nix/store` mount that the entire #99 design exists to enforce — it would have "worked" by quietly demolishing the security boundary. He also asked the question that should have slowed me down sooner: *"is this really a bug, or how Nix is supposed to behave?"*

### Wrong theory #2 — the `LD_PRELOAD` shim (and a glibc rabbit hole)

If the store mount must stay read-only, the workaround had to live in userspace. Plan: an `LD_PRELOAD` shim intercepting `open*` to flip `O_RDONLY → O_RDWR` for temproots lock files.

This spawned its own sub-saga. The first shim did nothing — libnixstore imports *versioned* glibc symbols (`open64@GLIBC_2.2.5`), and an unversioned `LD_PRELOAD` symbol doesn't satisfy a versioned import; the loader skips it. Making interception actually happen meant `.symver` assembler directives, a linker version script declaring the `GLIBC_*` version nodes, and `dlvsym(RTLD_NEXT, …)` to fetch the real versioned symbol. A lot of machinery — and it still didn't fix the lock.

### The disproof — `ctypes` says the premise is false

Before iterating the shim a fourth time, I stopped theorizing and tested the actual claim on the actual kernel with a few lines of Python `ctypes`: open a temproots-style file `O_RDONLY`, then try to write-lock it every way Nix might.

```
O_RDONLY + flock(LOCK_EX)      -> 0  (ok)
O_RDONLY + fcntl(F_SETLK)      -> 0  (ok)
O_RDONLY + fcntl(F_OFD_SETLK)  -> 0  (ok)
O_RDONLY + fcntl(F_OFD_SETLKW) -> 0  (ok)
```

All of them succeed. This kernel does **not** enforce the "fd must be writable for a write lock" rule. The whole `O_RDONLY` theory — and therefore the shim built on it — was dead. No `open()` flag change was ever going to matter.

### The red herring — `strace` makes the bug vanish

To see what Nix *actually* does, I reached for `strace` (added to the image as a temporary block; `--cap-drop ALL` was a worry, but a fork + `PTRACE_TRACEME` probe confirmed Docker's default seccomp permits `ptrace` for a child you spawned). Under strace:

```
openat(…/temproots/455320, O_RDWR|O_CREAT|O_CLOEXEC) = 10
flock(10</…/temproots/455320>, LOCK_EX)              = 0
exit=0
```

It *succeeded.* The temproots open was already `O_RDWR` (not `O_RDONLY` — second nail in the shim's coffin), the flock worked, and `nix develop` ran clean. A Heisenbug: the bug disappears under observation.

The cause wasn't ptrace timing — it was caching. When Nix doesn't need to re-copy the dirty flake tree into the store, it never calls `addTempRoot`, never touches the lock path, and trivially succeeds. The strace run happened to hit cache.

### The catch — the discarded shim becomes the right tool

Here's the turn. `strace` was the *wrong* instrument precisely because it changed the outcome. What I needed was a tracer that *doesn't* perturb the run — and the shim, built on a wrong theory and useless as a fix, was perfect for it: an in-process `open*` interceptor with negligible overhead. I gutted the flag-flipping and made it log every `open*` call's path, flags, return value, and errno behind `NIX_SHIM_DEBUG=1`. With it loaded the failure reproduced (unlike under strace), and the log was unambiguous:

```
open64 …/temproots/476       flags=O_RDWR|O_CREAT|O_CLOEXEC  ret=11   (ok)
open64 …/nix/var/nix/gc.lock  flags=O_RDWR|O_CREAT|O_CLOEXEC  ret=-1  errno=30 (Read-only file system)
```

### Root cause

`temproots` was never the problem — it opens fine (fd 11). The very next call, on **`/nix/var/nix/gc.lock`**, fails with `EROFS`. `gc.lock` sits *directly* under `/nix/var/nix`, and the original mount split only carved out `db`, `gcroots`, and `temproots` as writable — so `gc.lock` landed on the read-only `/nix` mount. Nix opens it `O_RDWR|O_CREAT` for any store-touching operation; the read-only filesystem returns `EROFS`; Nix is left holding fd `-1`; and the lock on `-1` is what finally surfaces as `acquiring/releasing lock: Bad file descriptor`.

Two layers of misleading signal had kept this hidden: the error *string* points at "lock," not "open" (the lock didn't fail — it inherited a `-1` fd), and Nix's own `-vvvv` log prints `acquiring write lock on "…/temproots/…"` immediately before dying — the last thing that *succeeded*, not the thing that failed.

### Fix

`_append_nix_mount_args` now mounts **all of `/nix/var/nix` read-write** (Nix's mutable bookkeeping is one unit; enumerating individual subdirs is exactly what dropped `gc.lock`), with **`/nix/var/nix/profiles` re-pinned read-only** via a nested bind-mount — **Josiah's refinement**: `nix develop` never writes `profiles`, and a writable `profiles` is the one part of the mutable state a compromised container could use to tamper with the *host's* profile generations. `/nix/store` stays read-only; store *contents* remain immutable, which is the guarantee that ever mattered. The shim, its build stage, the `LD_PRELOAD` env, and the temporary `strace` block are all removed. Security reasoning in DECISIONLOG (2026-06-16, #99).

### Lessons (blog material)

- **Read the error as a lead, not a verdict.** "acquiring/releasing lock: Bad file descriptor" is three steps downstream of the real event — a failed `open`. The lock didn't fail; it inherited a `-1` fd.
- **Test the premise before building on it.** A 20-line `ctypes` probe would have killed the `O_RDONLY` theory — and the entire shim — on day one.
- **The observer can erase the bug.** `strace` reshapes execution; here it dodged the failing code path entirely. Reach for the lowest-perturbation instrument that still *reproduces* the failure — which turned out to be the very shim I'd written for the wrong reason.
- **A "precise" security carve-out had a hole.** Enumerating writable subpaths (`db`/`gcroots`/`temproots`) felt exact but silently omitted `gc.lock`. Modeling the boundary as "the *store* is immutable; its *bookkeeping* is not" is both more correct and more robust.

### Verified (rebuilt image, fresh container)

Confirmed end-to-end with `FARADAI_MOUNT_NIX_STORE=1`:

- Mount layout in effect: `/nix` ro, `/nix/var/nix` rw, `/nix/var/nix/profiles` ro, config/state ro; `LD_PRELOAD` empty (shim gone); `gc.lock` now writable.
- `nix develop <PPN95> -c true` → `exit=0` (the `EBADF` is gone).
- The dev shell is genuinely usable, not just entered: `mmc` resolves to `/nix/store/8hnhk6d8w7gag0y7yc6mq5mlpvq6w3sp-mercury-22.01.8/bin/mmc` and `mmc --version` prints `Mercury Compiler, version 22.01.8`.
- The `profiles`-read-only bet held — no `EROFS` pointing at `…/profiles/…`.
- The read-only `/nix/store` boundary is confirmed intact and load-bearing: runs emit `error (ignored): creating directory "/nix/store/…": Read-only file system` — Nix trying to cache into the store, refused by the kernel, **degrading gracefully** rather than failing. Exactly the #99 guarantee: store contents immutable, workflow still works.

---

## The pattern leaves the cage: Nix mount strategy propagates to the Doom Emacs IDEs — 2026-06-16

> Also a blog-post candidate. The #99 narrative is about *finding* the right mount split; this one is about what happens when a hard-won pattern gets applied somewhere else and reveals a new design gap.

### The prior state

The docker-emacs IDE launchers — mercury-ide's `host/logic-languages-ide` and systems-ide's `run.sh` — had been mounting the host Nix store since the 2026-06-15 session that first wired them up. The mounts were simple and unconditional:

```bash
-v /nix:/nix
-v "${HOME}/.local/state/nix:..."
-v "${HOME}/.config/nix:..."
```

Unconditional. No `:ro`. Three paths, no split. This was the "it works, ship it" state — the focus at the time was getting the shared store *functional*, and it was: `nix develop` worked, smoketests passed 7/7. The security nuance of the faradai DECISIONLOG #99 mount split simply hadn't been applied yet.

### Bringing the pattern across

The fix is mechanical once you have the pattern. Replace the three unconditional mounts with:

```bash
nix_mounts=()
if [[ -d /nix ]] && [[ "${MOUNT_HOST_NIX:-1}" == "1" ]]; then
  nix_mounts+=(
    -v /nix:/nix:ro
    -v /nix/var/nix:/nix/var/nix
    -v /nix/var/nix/profiles:/nix/var/nix/profiles:ro
    -v "${HOME}/.config/nix:...:ro"
    -v "${HOME}/.local/state/nix:...:ro"
  )
fi
```

Five mounts instead of three. The `/nix/var/nix` rw override and the `profiles` re-pin are straight copies of `_append_nix_mount_args`. The Dockerfiles are untouched — the `nix-source` COPY stage keeps baking a full working `/nix` into the image regardless of what the launcher does.

### The new gap the copy-paste exposed

Applying the pattern mechanically raised a question that hadn't come up in faradai: **what if `/nix` exists on the host but is broken?**

In faradai, `FARADAI_MOUNT_NIX_STORE` defaults to `0`. The host Nix mount is opt-in. You only turn it on when you know the host store is healthy. The guard `[[ -d /nix ]]` is therefore rarely, if ever, tested against a bad store.

The IDE launchers are different. They auto-detect — the intent is that the IDEs *just work* with the host store when it's there. Auto-detection means the guard fires on anything that looks like a `/nix` directory, including a corrupt one, a half-upgraded one, a store that passed the SQLite schema version boundary mid-operation.

`[[ -d /nix ]]` cannot distinguish healthy from sick. The directory exists in all cases.

Josiah caught this gap directly: the baked-in store is exactly the fallback you want in that scenario, but you can't reach it if the sick host store always wins the auto-detection race. The fix is an escape hatch: `MOUNT_HOST_NIX=0` skips the host mounts entirely and falls back to the container's own store, without touching the host filesystem. A corrupted `/nix` doesn't need to be renamed, moved, or rebuilt before the IDE can be used.

### What the baked-in store actually is

This is worth naming explicitly, because the Dockerfile pattern makes it invisible at the launcher level.

Both IDE Dockerfiles pull from `josiah14/nix:2.34.7-ubuntu-24.04` via a `nix-source` build stage and `COPY --from=nix-source` the entire `/nix` tree, `~/.config/nix`, `~/.local/state/nix`, and `~/.config/direnv` into the final image. The result is a container that has a complete, working Nix installation at the image layer — `nix`, `nil`, `direnv`, `nix-direnv`, `bats`, the whole profile. The container *can* run `nix develop` purely from its own store, with no host involvement.

When the launcher mounts `/nix` from the host, Docker stacks the bind mount on top of the image layer. The image-layer `/nix` is still there; it's just shadowed. When no bind mount is active, the image layer wins, and the container runs on the version of Nix that was current when the image was built.

This is a useful property that the unconditional-mount design had accidentally hidden: **the fallback was always there.** The conditional detection plus `MOUNT_HOST_NIX=0` just makes it reachable.

### The mount progression, summarized

| Stage | What the IDE launchers did | Status |
|---|---|---|
| Before 2026-06-15 | No host Nix mount; container used baked-in store | Slow (rebuild on every `nix develop`) |
| 2026-06-15 | Unconditional `/nix`, state, config mounts (rw) | Fast; store write-unprotected |
| 2026-06-16 | Conditional detection; #99 RO/RW split; `MOUNT_HOST_NIX=0` | Fast; store immutable; fallback reachable |

The faradai `gc.lock` debugging arc provided both the correct mount topology and the understanding of *why* it's correct — the mutable bookkeeping must be writable, the store contents must not be. Neither the topology nor the reasoning had to be re-derived when porting the pattern to the IDEs. The hard work was done once, in the right place, and then carried across.
