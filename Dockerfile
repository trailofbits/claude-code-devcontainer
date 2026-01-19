# Stage 1: Install Node packages
FROM node:23-bookworm-slim AS node

ARG CLAUDE_CODE_VERSION=latest

RUN npm install -g @anthropic-ai/claude-code@${CLAUDE_CODE_VERSION} pnpm

# Stage 2: Final image
FROM ubuntu:25.04

ARG TZ
ENV TZ="$TZ"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Install system packages
RUN apt-get update && apt-get install -y --no-install-recommends \
  # Core tools
  less \
  git \
  procps \
  sudo \
  unzip \
  gnupg2 \
  gh \
  jq \
  nano \
  vim \
  curl \
  ca-certificates \
  locales \
  build-essential \
  openssh-client \
  # Modern CLI tools
  fzf \
  ripgrep \
  fd-find \
  tmux \
  zsh \
  # Python
  python3 \
  # Network tools (for security testing)
  iptables \
  ipset \
  iproute2 \
  dnsutils \
  && apt-get clean && rm -rf /var/lib/apt/lists/* \
  && localedef -i en_US -c -f UTF-8 -A /usr/share/locale/locale.alias en_US.UTF-8

ENV LANG=en_US.utf8

# Copy Node.js and npm packages from stage 1
COPY --from=node /usr/local /usr/local

# Install git-delta
ARG GIT_DELTA_VERSION=0.18.2
RUN ARCH=$(dpkg --print-architecture) && \
  curl -fsSL "https://github.com/dandavison/delta/releases/download/${GIT_DELTA_VERSION}/git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb" -o /tmp/git-delta.deb && \
  dpkg -i /tmp/git-delta.deb && \
  rm /tmp/git-delta.deb

# Install uv (Python package manager)
ENV UV_INSTALL_DIR="/usr/local/bin"
RUN curl -LsSf https://astral.sh/uv/install.sh | sh

ARG USERNAME=ubuntu

# Setup directories and permissions
RUN mkdir -p /usr/local/share/npm-global && \
  chown -R ubuntu:ubuntu /usr/local/share

# Allow fully password-less sudo
RUN echo "ALL            ALL = (ALL) NOPASSWD: ALL" > /etc/sudoers.d/no-passwd && chmod 0440 /etc/sudoers.d/no-passwd

# Persist command history
RUN mkdir /commandhistory && \
  touch /commandhistory/.bash_history && \
  touch /commandhistory/.zsh_history && \
  chown -R $USERNAME /commandhistory

# Set environment variables
ENV DEVCONTAINER=true
ENV SHELL=/bin/zsh
ENV EDITOR=nano
ENV VISUAL=nano

# Create workspace and config directories
RUN mkdir -p /workspace /home/ubuntu/.claude /opt && \
  chown -R ubuntu:ubuntu /workspace /home/ubuntu/.claude /opt

WORKDIR /workspace

# Switch to non-root user for zsh setup
USER ubuntu

# Install Oh My Zsh and configure shell
ARG ZSH_IN_DOCKER_VERSION=1.2.1
RUN sh -c "$(curl -fsSL https://github.com/deluan/zsh-in-docker/releases/download/v${ZSH_IN_DOCKER_VERSION}/zsh-in-docker.sh)" -- \
  -p git \
  -p fzf \
  -a "export HISTFILE=/commandhistory/.zsh_history" \
  -a "export HISTSIZE=200000" \
  -a "export SAVEHIST=200000" \
  -a "setopt SHARE_HISTORY" \
  -a "setopt HIST_IGNORE_DUPS" \
  -a "# Aliases" \
  -a "alias fd=fdfind" \
  -a "alias claude-yolo='claude --dangerously-skip-permissions'" \
  -x

# Copy post_install script
COPY --chown=ubuntu:ubuntu post_install.py /opt/post_install.py
