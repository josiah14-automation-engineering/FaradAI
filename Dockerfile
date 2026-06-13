FROM ubuntu:24.04@sha256:c4a8d5503dfb2a3eb8ab5f807da5bc69a85730fb49b5cfca2330194ebcc41c7b AS base

ARG SNAPSHOT_DATE=20260522T000000Z

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# ca-certificates is intentionally unpinned: the CA bundle must track current
# trust anchors (expired/revoked/new roots), not a frozen snapshot point-in-time.
# hadolint ignore=DL3008
RUN apt-get update -y \
 && apt-get install -y --no-install-recommends ca-certificates \
 && rm -rf /var/lib/apt/lists/* \
 && rm -f /etc/apt/sources.list.d/ubuntu.sources \
 && echo "deb https://snapshot.ubuntu.com/ubuntu/${SNAPSHOT_DATE} noble main restricted universe multiverse" > /etc/apt/sources.list \
 && echo "deb https://snapshot.ubuntu.com/ubuntu/${SNAPSHOT_DATE} noble-updates main restricted universe multiverse" >> /etc/apt/sources.list \
 && echo "deb https://snapshot.ubuntu.com/ubuntu/${SNAPSHOT_DATE} noble-security main restricted universe multiverse" >> /etc/apt/sources.list \
 && echo 'Acquire::Check-Valid-Until "false";' > /etc/apt/apt.conf.d/99snapshot

FROM base AS builder

ARG USERNAME
ARG SHELLCHECK_VERSION=v0.11.0
ARG TARGETARCH

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ENV DEBIAN_FRONTEND=noninteractive
ENV HOME=/home/${USERNAME}
ENV PIPX_HOME=/home/${USERNAME}/.local/pipx
ENV PIPX_BIN_DIR=/home/${USERNAME}/.local/bin

RUN apt-get update -y && apt-get install -y --no-install-recommends \
    ca-certificates=20240203 \
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
 && npm install -g @anthropic-ai/claude-code@2.1.177 \
 && pipx install aider-chat==0.86.2 \
 && pipx runpip aider-chat cache purge \
 && npm cache clean --force \
 && find /home/${USERNAME}/.local -name "__pycache__" -type d -exec rm -rf {} + \
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

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

LABEL org.opencontainers.image.title="FaradAI" \
      org.opencontainers.image.source="https://github.com/josiah14-automation-engineering/faradai" \
      org.opencontainers.image.faradai.username="${USERNAME}"

ENV DEBIAN_FRONTEND=noninteractive

# Ubuntu 24.04 ships with a default 'ubuntu' user at UID/GID 1000 which clashes
# with the host user if they share that UID/GID
RUN apt-get update -y && apt-get install -y --no-install-recommends \
    ca-certificates=20240203 \
    curl=8.5.0-2ubuntu10.9 \
    gnupg=2.4.4-2ubuntu17.4 \
 && mkdir -p /etc/apt/keyrings \
 && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
    | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
 && echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main" \
    | tee /etc/apt/sources.list.d/nodesource.list > /dev/null \
 && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
 && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
    bind9-dnsutils=1:9.18.39-0ubuntu0.24.04.5 \
    gh=2.92.0 \
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
 && apt-get purge -y gnupg \
 && apt-get autoremove -y \
 && rm -f /usr/share/keyrings/githubcli-archive-keyring.gpg \
 && rm -f /etc/apt/sources.list.d/github-cli.list \
 && rm -rf /var/lib/apt/lists/* \
 && userdel -r ubuntu 2>/dev/null || true \
 && groupdel ubuntu 2>/dev/null || true \
 && groupadd --gid ${USER_GID} ${USERNAME} \
 && useradd --uid ${USER_UID} --gid ${USER_GID} --create-home --shell /bin/bash ${USERNAME}

ENV PATH="/home/${USERNAME}/.local/bin:${PATH}"

COPY --chmod=755 --from=builder /tmp/shellcheck /usr/local/bin/shellcheck

COPY --from=builder --chown=${USER_UID}:${USER_GID} \
    /home/${USERNAME}/.local \
    /home/${USERNAME}/.local

COPY --chmod=755 entrypoint.sh /usr/local/bin/entrypoint.sh

USER ${USERNAME}

# Pre-register common Git hosts so SSH agent forwarding works without ~/.ssh mounted.
# ssh-keyscan exits 0 even if a host is unreachable, so this won't fail the build.
RUN mkdir -p "/home/${USERNAME}/.ssh" \
 && chmod 700 "/home/${USERNAME}/.ssh" \
 && ssh-keyscan github.com gitlab.com bitbucket.org >> "/home/${USERNAME}/.ssh/known_hosts" 2>/dev/null \
 && chmod 600 "/home/${USERNAME}/.ssh/known_hosts"

HEALTHCHECK --interval=30s --timeout=10s --start-period=15s --retries=3 \
    CMD claude --version > /dev/null 2>&1 && aider --version > /dev/null 2>&1

WORKDIR /home/${USERNAME}

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
