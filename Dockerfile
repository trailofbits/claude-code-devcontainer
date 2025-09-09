FROM ubuntu:24.04

ARG TZ
ENV TZ="$TZ"

ARG CLAUDE_CODE_VERSION=latest

# Install basic development tools and iptables/ipset
RUN apt-get update && apt-get install -y --no-install-recommends \
  less \
  git \
  procps \
  sudo \
  fzf \
  zsh \
  man-db \
  unzip \
  gnupg2 \
  gh \
  iptables \
  ipset \
  iproute2 \
  dnsutils \
  aggregate \
  jq \
  nano \
  vim \
  curl \
  ca-certificates \
  locales \
  build-essential \
  wget \
  && apt-get clean && rm -rf /var/lib/apt/lists/* \
  && localedef -i en_US -c -f UTF-8 -A /usr/share/locale/locale.alias en_US.UTF-8

ENV LANG=en_US.utf8

# Ensure ubuntu user has access to /usr/local/share
RUN mkdir -p /usr/local/share/npm-global && \
  chown -R ubuntu:ubuntu /usr/local/share

ARG USERNAME=ubuntu

# setup node as the ubuntu user
USER ubuntu
RUN bash -c "curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash"
ENV NVM_DIR="/home/ubuntu/.nvm"
# install node 20
RUN bash -c "source ${NVM_DIR}/nvm.sh && nvm install 20 && nvm use 20 && nvm alias default 20"

USER root

# Persist bash history.
RUN SNIPPET="export PROMPT_COMMAND='history -a' && export HISTFILE=/commandhistory/.bash_history" \
  && mkdir /commandhistory \
  && touch /commandhistory/.bash_history \
  && chown -R $USERNAME /commandhistory

# Set `DEVCONTAINER` environment variable to help with orientation
ENV DEVCONTAINER=true

# Create workspace and config directories and set permissions
RUN mkdir -p /workspace /home/ubuntu/.claude && \
  chown -R ubuntu:ubuntu /workspace /home/ubuntu/.claude

WORKDIR /workspace

ARG GIT_DELTA_VERSION=0.18.2
RUN ARCH=$(dpkg --print-architecture) && \
  wget "https://github.com/dandavison/delta/releases/download/${GIT_DELTA_VERSION}/git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb" && \
  sudo dpkg -i "git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb" && \
  rm "git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb"

# Set up non-root user
USER ubuntu

# Set the default shell to zsh rather than sh
ENV SHELL=/bin/zsh

# Set the default editor and visual
ENV EDITOR=nano
ENV VISUAL=nano

# Default powerline10k theme
ARG ZSH_IN_DOCKER_VERSION=1.2.0
RUN sh -c "$(wget -O- https://github.com/deluan/zsh-in-docker/releases/download/v${ZSH_IN_DOCKER_VERSION}/zsh-in-docker.sh)" -- \
  -p git \
  -p fzf \
  -a "source /usr/share/doc/fzf/examples/key-bindings.zsh" \
  -a "source /usr/share/doc/fzf/examples/completion.zsh" \
  -a "export PROMPT_COMMAND='history -a' && export HISTFILE=/commandhistory/.bash_history" \
  -a "export NVM_DIR=\"/home/ubuntu/.nvm\" && [ -s \"\$NVM_DIR/nvm.sh\" ] && source \"\$NVM_DIR/nvm.sh\" && [ -s \"\$NVM_DIR/bash_completion\" ] && source \"\$NVM_DIR/bash_completion\"" \
  -x

# Install Claude as ubuntu user
USER ubuntu
RUN bash -c "unset NPM_CONFIG_PREFIX && source /home/ubuntu/.nvm/nvm.sh && npm install -g @anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}"

