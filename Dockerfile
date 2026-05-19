FROM ubuntu:24.04

ARG USERNAME
ARG USER_UID
ARG USER_GID

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get purge -y --auto-remove sudo 2>/dev/null || true \
 && apt-get update -y && apt-get install -y \
    curl \
    git \
    nodejs \
    npm \
    openssh-client \
    python3 \
    python3-pip \
    python3-venv \
    pipx \
    tmux \
    && rm -rf /var/lib/apt/lists/*

# Ubuntu 24.04 ships with a default 'ubuntu' user at UID/GID 1000 which clashes
# with the host user if they share that UID/GID
RUN userdel -r ubuntu 2>/dev/null || true \
 && groupdel ubuntu 2>/dev/null || true \
 && groupadd --gid ${USER_GID} ${USERNAME} \
 && useradd --uid ${USER_UID} --gid ${USER_GID} --create-home ${USERNAME} \
 && mkdir -p /home/${USERNAME}/Development/personal \
 && chown ${USER_UID}:${USER_GID} /home/${USERNAME}/Development/personal


ENV PATH="/home/${USERNAME}/.local/bin:${PATH}"

COPY entrypoint.sh "/usr/local/bin/entrypoint.sh"
RUN chown ${USER_UID}:${USER_GID} "/usr/local/bin/entrypoint.sh" \
 && chmod +x "/usr/local/bin/entrypoint.sh"

USER ${USERNAME}

# Keep the below as separate RUN commands to make updating versions quick and easy
RUN npm config set prefix "/home/${USERNAME}/.local"
RUN npm install -g @anthropic-ai/claude-code@2.1.143
RUN pipx install aider-chat==0.86.2

WORKDIR /home/${USERNAME}/Development/personal

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
