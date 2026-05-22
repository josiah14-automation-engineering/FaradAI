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

## Session 34 — 2026-05-22

### Known issues and limitations section in README

Added a "Known issues and limitations" section to README covering: Docker filesystem I/O overhead, no GPU passthrough, local LSP limitations, and multi-user `docker rm` name collision. Also updated the stale `gh` auth troubleshooting entry — it previously said credentials weren't persisted, which was true before #33 was fixed.

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

**Resolution:** BUILDLOG.md is frozen as a historical record after `v0.1.0-alpha.1`. Significant architectural and security decisions made post-release are captured in `DECISIONLOG.md` — a terse, indexed log with one entry per decision. Task-level work continues to live in GitHub issues and commit messages. CHANGELOG and DECISIONLOG cross-reference each other.

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
