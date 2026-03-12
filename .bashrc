#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091

# Source global definitions
if [ -f /etc/bashrc ]; then
  . /etc/bashrc
fi

# Source bash_profile for interactive shells
# shellcheck disable=SC2154
[ -n "$PS1" ] && source ~/.bash_profile

# Kubectl completion (conditional)
if command -v kubectl &>/dev/null; then
  source <(kubectl completion bash)
  complete -o default -F __start_kubectl k
fi

# Add ~/bin and ~/.local/bin to PATH (with dedup guard)
for p in "${HOME}/bin" "${HOME}/.local/bin"; do
  case ":${PATH}:" in
    *":${p}:"*) ;;
    *) export PATH="${p}:${PATH}" ;;
  esac
done
unset p

# Cargo environment (conditional)
[ -f "${HOME}/.cargo/env" ] && source "${HOME}/.cargo/env"
