FROM ubuntu:24.04 AS builder

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
 && pipx install aider-chat==0.86.2


FROM ubuntu:24.04 AS final

ARG USERNAME
ARG USER_UID
ARG USER_GID
ARG WORKDIR_PATH=/home/${USERNAME}/Development/personal

ENV DEBIAN_FRONTEND=noninteractive

# Ubuntu 24.04 ships with a default 'ubuntu' user at UID/GID 1000 which clashes
# with the host user if they share that UID/GID
RUN apt-get purge -y --auto-remove sudo 2>/dev/null || true \
 && apt-get update -y && apt-get install -y --no-install-recommends \
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

WORKDIR ${WORKDIR_PATH}

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
