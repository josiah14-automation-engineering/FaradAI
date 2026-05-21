FROM ubuntu:24.04@sha256:c4a8d5503dfb2a3eb8ab5f807da5bc69a85730fb49b5cfca2330194ebcc41c7b AS builder

ARG USERNAME

ENV DEBIAN_FRONTEND=noninteractive
ENV HOME=/home/${USERNAME}
ENV PIPX_HOME=/home/${USERNAME}/.local/pipx
ENV PIPX_BIN_DIR=/home/${USERNAME}/.local/bin

RUN apt-get update -y && apt-get install -y \
    nodejs \
    npm \
    python3 \
    python3-pip \
    python3-venv \
    pipx \
 && rm -rf /var/lib/apt/lists/* \
 && mkdir -p /home/${USERNAME}

RUN npm config set prefix "/home/${USERNAME}/.local" \
 && npm install -g @anthropic-ai/claude-code@2.1.143 \
 && pipx install aider-chat==0.86.2 \
 && pipx runpip aider-chat cache purge \
 && npm cache clean --force \
 && find /home/${USERNAME}/.local -name "__pycache__" -type d -exec rm -rf {} + \
 && rm -rf /home/${USERNAME}/.cache


FROM ubuntu:24.04@sha256:c4a8d5503dfb2a3eb8ab5f807da5bc69a85730fb49b5cfca2330194ebcc41c7b AS final

ARG USERNAME
ARG USER_UID
ARG USER_GID
ARG WORKDIR_PATH=/home/${USERNAME}/Development/personal

ENV DEBIAN_FRONTEND=noninteractive

# Ubuntu 24.04 ships with a default 'ubuntu' user at UID/GID 1000 which clashes
# with the host user if they share that UID/GID
RUN apt-get update -y && apt-get install -y --no-install-recommends \
    curl \
    dnsutils \
    git \
    iproute2 \
    iputils-ping \
    net-tools \
    netcat-openbsd \
    nodejs \
    openssh-client \
    python3 \
    python3-pip \
    python3-venv \
    tmux \
    vim \
 && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
 && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
 && apt-get update \
 && apt-get install -y --no-install-recommends gh \
 && rm -f /usr/share/keyrings/githubcli-archive-keyring.gpg \
 && rm -f /etc/apt/sources.list.d/github-cli.list \
 && rm -rf /var/lib/apt/lists/* \
 && userdel -r ubuntu 2>/dev/null || true \
 && groupdel ubuntu 2>/dev/null || true \
 && groupadd --gid ${USER_GID} ${USERNAME} \
 && useradd --uid ${USER_UID} --gid ${USER_GID} --create-home --shell /bin/bash ${USERNAME} \
 && mkdir -p ${WORKDIR_PATH} \
 && chown ${USER_UID}:${USER_GID} ${WORKDIR_PATH}

ENV PATH="/home/${USERNAME}/.local/bin:${PATH}"

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

WORKDIR ${WORKDIR_PATH}

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
