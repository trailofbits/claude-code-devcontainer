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

# Google Cloud SDK (conditional)
for gcloud_inc in \
  "/opt/homebrew/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/path.bash.inc" \
  "/opt/homebrew/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/completion.bash.inc" \
  "/usr/share/google-cloud-sdk/path.bash.inc" \
  "/usr/share/google-cloud-sdk/completion.bash.inc"; do
  [ -f "$gcloud_inc" ] && source "$gcloud_inc"
done
unset gcloud_inc

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

# --- Unset empty credential vars (localEnv sets "" when unset on host) ---
if [[ -d /workspace ]]; then
  for _var in ANTHROPIC_API_KEY OPENAI_API_KEY EXA_API_KEY GH_TOKEN; do
    [[ -z "${!_var}" ]] && unset "$_var"
  done
  unset _var
fi
