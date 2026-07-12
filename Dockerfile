FROM ubuntu:24.04@sha256:c4a8d5503dfb2a3eb8ab5f807da5bc69a85730fb49b5cfca2330194ebcc41c7b AS base

ARG SNAPSHOT_DATE=20260522T000000Z

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# ca-certificates is intentionally unpinned: the CA bundle must track current
# trust anchors (expired/revoked/new roots), not a frozen snapshot point-in-time.
# FaradAI's pinned packages use main or universe; omit restricted because the
# Ubuntu Snapshot service can leave that metadata unavailable for hours.
# hadolint ignore=DL3008
RUN apt-get update -y \
 && apt-get install -y --no-install-recommends ca-certificates \
 && rm -rf /var/lib/apt/lists/* \
 && rm -f /etc/apt/sources.list.d/ubuntu.sources \
 && echo "deb https://snapshot.ubuntu.com/ubuntu/${SNAPSHOT_DATE} noble main universe multiverse" > /etc/apt/sources.list \
 && echo "deb https://snapshot.ubuntu.com/ubuntu/${SNAPSHOT_DATE} noble-updates main universe multiverse" >> /etc/apt/sources.list \
 && echo "deb https://snapshot.ubuntu.com/ubuntu/${SNAPSHOT_DATE} noble-security main universe multiverse" >> /etc/apt/sources.list \
 && echo 'Acquire::Check-Valid-Until "false";' > /etc/apt/apt.conf.d/99snapshot \
 && echo 'Acquire::Retries "5";' >> /etc/apt/apt.conf.d/99snapshot

FROM base AS builder

ARG USERNAME
ARG SHELLCHECK_VERSION=v0.11.0
ARG TARGETARCH
ARG AIDER_VERSION=0.86.2
ARG CLAUDE_CODE_VERSION=2.1.205
ARG CODEX_VERSION=0.141.0
ARG OPENCODE_VERSION=1.17.18
ARG HEADROOM_VERSION=0.31.0

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ENV DEBIAN_FRONTEND=noninteractive
ENV HOME=/home/${USERNAME}
ENV PIPX_HOME=/home/${USERNAME}/.local/pipx
ENV PIPX_BIN_DIR=/home/${USERNAME}/.local/bin

RUN apt-get update -y && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl=8.5.0-2ubuntu10.9 \
    gnupg=2.4.4-2ubuntu17.4 \
 && mkdir -p /etc/apt/keyrings \
 && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
    | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
 && echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main" \
    | tee /etc/apt/sources.list.d/nodesource.list > /dev/null \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
    nodejs=22.22.2-1nodesource1 \
    python3=3.12.3-0ubuntu2.1 \
    python3-pip=24.0+dfsg-1ubuntu1.3 \
    python3-venv=3.12.3-0ubuntu2.1 \
    pipx=1.4.3-1 \
 && rm -rf /var/lib/apt/lists/* \
 && mkdir -p /home/${USERNAME}

RUN npm config set prefix "/home/${USERNAME}/.local" \
 && pipx install aider-chat==${AIDER_VERSION} \
 && pipx runpip aider-chat cache purge \
 && find /home/${USERNAME}/.local -name "__pycache__" -type d -exec rm -rf {} +

# Deliberately narrower than [all]: [all] pulls in torch via [ml]/[memory]/[evals]
# (multi-GB with default CUDA wheels, hundreds of MB even pinned CPU-only) plus
# [voice]/[image] extras unrelated to a text-based coding-agent sandbox. proxy is
# what `headroom wrap` needs to run at all (includes onnxruntime-based Kompress
# compression and mcp — no torch); code adds AST-aware compression for coding
# tasks; html/reports/spreadsheet/otel are lightweight, no-torch extras kept for
# their own merits (web content extraction, dashboard output, spreadsheet
# ingestion, metrics export). All of it (proxy/code/html/reports/spreadsheet/otel)
# ships prebuilt wheels for linux x86_64/aarch64 — no Rust toolchain needed at
# build time on either TARGETARCH this image supports.
RUN pipx install "headroom-ai[proxy,code,html,reports,spreadsheet,otel]"==${HEADROOM_VERSION} \
 && pipx runpip headroom-ai cache purge \
 && find /home/${USERNAME}/.local -name "__pycache__" -type d -exec rm -rf {} +

RUN npm install -g @openai/codex@${CODEX_VERSION} \
 && npm cache clean --force \
 && rm -rf /home/${USERNAME}/.cache

RUN npm install -g @anthropic-ai/claude-code@${CLAUDE_CODE_VERSION} \
 && npm cache clean --force \
 && rm -rf /home/${USERNAME}/.cache

RUN npm install -g opencode-ai@${OPENCODE_VERSION} \
 && npm cache clean --force \
 && rm -rf /home/${USERNAME}/.cache

RUN case "${TARGETARCH:-amd64}" in \
      amd64) _SC_ARCH="x86_64" ;; \
      arm64) _SC_ARCH="aarch64" ;; \
      *) echo "unsupported TARGETARCH=${TARGETARCH}" >&2; exit 1 ;; \
    esac \
 && curl -fsSL "https://github.com/koalaman/shellcheck/releases/download/${SHELLCHECK_VERSION}/shellcheck-${SHELLCHECK_VERSION}.linux.${_SC_ARCH}.tar.gz" \
    | tar -xz --strip-components=1 -C /tmp "shellcheck-${SHELLCHECK_VERSION}/shellcheck"

FROM base AS final

ARG USERNAME
ARG USER_UID
ARG USER_GID
ARG TARGETARCH
ARG GH_VERSION=2.96.0

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

LABEL org.opencontainers.image.title="FaradAI" \
      org.opencontainers.image.source="https://github.com/josiah14-automation-engineering/faradai" \
      org.opencontainers.image.faradai.username="${USERNAME}"

ENV DEBIAN_FRONTEND=noninteractive

# Ubuntu 24.04 ships with a default 'ubuntu' user at UID/GID 1000 which clashes
# with the host user if they share that UID/GID
#
# gh is installed differently from the packages below: unlike the Ubuntu
# snapshot repo (pinned to SNAPSHOT_DATE) and NodeSource (which keeps every
# past version), the cli.github.com apt repo's index only ever serves the
# single latest release. A version-pinned `apt-get install gh=X` there breaks
# the moment upstream cuts a new release out from under the pin (this is what
# broke this build). GitHub Releases keeps every past version's per-arch .deb
# indefinitely, so downloading the pinned .deb directly is the only way to
# keep gh reproducible — see DECISIONLOG.
RUN apt-get update -y && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl=8.5.0-2ubuntu10.9 \
    gnupg=2.4.4-2ubuntu17.4 \
 && mkdir -p /etc/apt/keyrings \
 && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
    | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
 && echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main" \
    | tee /etc/apt/sources.list.d/nodesource.list > /dev/null \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
    bind9-dnsutils=1:9.18.39-0ubuntu0.24.04.5 \
    git=1:2.43.0-1ubuntu7.3 \
    iproute2=6.1.0-1ubuntu6.3 \
    iputils-ping=3:20240117-1ubuntu0.1 \
    jq=1.7.1-3ubuntu0.24.04.2 \
    net-tools=2.10-0.1ubuntu4.4 \
    netcat-openbsd=1.226-1ubuntu2 \
    nodejs=22.22.2-1nodesource1 \
    openssh-client=1:9.6p1-3ubuntu13.16 \
    python3=3.12.3-0ubuntu2.1 \
    python3-pip=24.0+dfsg-1ubuntu1.3 \
    python3-venv=3.12.3-0ubuntu2.1 \
    tmux=3.4-1ubuntu0.1 \
    vim=2:9.1.0016-1ubuntu7.13 \
 && case "${TARGETARCH:-amd64}" in \
      amd64|arm64) : ;; \
      *) echo "unsupported TARGETARCH=${TARGETARCH}" >&2; exit 1 ;; \
    esac \
 && curl -fsSL -o /tmp/gh.deb \
    "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_${TARGETARCH:-amd64}.deb" \
 && apt-get install -y /tmp/gh.deb \
 && rm -f /tmp/gh.deb \
 && apt-get purge -y gnupg \
 && apt-get autoremove -y \
 && rm -rf /var/lib/apt/lists/* \
 && { userdel -r ubuntu 2>/dev/null || true; } \
 && { groupdel ubuntu 2>/dev/null || true; } \
 && groupadd --gid ${USER_GID} ${USERNAME} \
 && useradd --uid ${USER_UID} --gid ${USER_GID} --create-home --shell /bin/bash ${USERNAME}

# ~/.config is never itself a bind mount (only ~/.config/gh and ~/.config/opencode
# are), so if it doesn't already exist when those nested mounts are attached at
# `docker run` time, Docker auto-creates it as root:root to hold the mount
# points — silently blocking the container user from writing any *other*
# subdirectory directly under ~/.config (e.g. tools like headroom's rtk that
# create their own ~/.config/<tool> dir on first run). Creating it here, owned
# by the container user, before any mount is ever attached, avoids that.
RUN mkdir -p "/home/${USERNAME}/.config" \
 && chown ${USER_UID}:${USER_GID} "/home/${USERNAME}/.config"

ENV PATH="/home/${USERNAME}/.local/bin:${PATH}"

COPY --chmod=755 --from=builder /tmp/shellcheck /usr/local/bin/shellcheck

COPY --from=builder --chown=${USER_UID}:${USER_GID} \
    /home/${USERNAME}/.local \
    /home/${USERNAME}/.local

RUN ln -sf "/home/${USERNAME}/.local/state/nix/profiles/profile" "/home/${USERNAME}/.nix-profile"

ENV PATH="/home/${USERNAME}/.nix-profile/bin:${PATH}"

COPY --chmod=755 entrypoint.sh /usr/local/bin/entrypoint.sh

USER ${USERNAME}

# Pre-register common Git hosts so SSH agent forwarding works without ~/.ssh mounted.
# ssh-keyscan exits 0 even if a host is unreachable, so this won't fail the build.
RUN mkdir -p "/home/${USERNAME}/.ssh" \
 && chmod 700 "/home/${USERNAME}/.ssh" \
 && ssh-keyscan github.com gitlab.com bitbucket.org >> "/home/${USERNAME}/.ssh/known_hosts" 2>/dev/null \
 && chmod 600 "/home/${USERNAME}/.ssh/known_hosts"

HEALTHCHECK --interval=30s --timeout=10s --start-period=15s --retries=3 \
    CMD claude --version > /dev/null 2>&1 && codex --version > /dev/null 2>&1 && aider --version > /dev/null 2>&1 && opencode --version > /dev/null 2>&1

WORKDIR /home/${USERNAME}

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
