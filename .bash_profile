#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091

# Load shell dotfiles:
# ~/.path can extend $PATH, ~/.extra for settings you don't want to commit
for file in ~/.{path,exports,aliases,functions,extra}; do
  [ -r "$file" ] && [ -f "$file" ] && source "$file"
done
unset file

# Homebrew (conditional)
if [ -f /opt/homebrew/bin/brew ]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif [ -f /usr/local/bin/brew ]; then
  eval "$(/usr/local/bin/brew shellenv)"
fi

# Shell options
shopt -s nocaseglob   # Case-insensitive globbing
shopt -s histappend   # Append to history, don't overwrite
shopt -s cdspell      # Autocorrect typos in cd paths

for option in autocd globstar; do
  shopt -s "$option" 2>/dev/null
done

# Bash completion
if command -v brew &>/dev/null; then
  brew_prefix="$(brew --prefix)"
  [ -r "${brew_prefix}/etc/profile.d/bash_completion.sh" ] && source "${brew_prefix}/etc/profile.d/bash_completion.sh"
  [ -f "${brew_prefix}/etc/bash_completion" ] && source "${brew_prefix}/etc/bash_completion"
  unset brew_prefix
elif [ -f /etc/bash_completion ]; then
  source /etc/bash_completion
fi

# SSH hostname tab completion
[ -e "${HOME}/.ssh/config" ] && complete -o "default" -o "nospace" -W "$(grep "^Host" ~/.ssh/config | grep -v "[?*]" | cut -d " " -f2 | tr ' ' '\n')" scp sftp ssh

# Terraform completion (conditional)
command -v terraform &>/dev/null && complete -C "$(command -v terraform)" terraform

# History: flush to file after every command
PROMPT_COMMAND="${PROMPT_COMMAND:+${PROMPT_COMMAND};}history -a"

# Silence macOS bash deprecation warning
export BASH_SILENCE_DEPRECATION_WARNING=1

# pyenv (conditional)
if command -v pyenv &>/dev/null; then
  export PYENV_ROOT="${HOME}/.pyenv"
  case ":${PATH}:" in
    *":${PYENV_ROOT}/bin:"*) ;;
    *) export PATH="${PYENV_ROOT}/bin:${PATH}" ;;
  esac
  eval "$(pyenv init -)"
  command -v pyenv-virtualenv-init &>/dev/null && eval "$(pyenv virtualenv-init -)"
fi

# Go paths (conditional)
if command -v go &>/dev/null; then
  [ -n "$GOROOT" ] && export PATH="${GOROOT}/bin:${PATH}"
  [ -n "$GOPATH" ] && export PATH="${PATH}:${GOPATH}/bin"
fi

# Cargo env (conditional)
[ -f "${HOME}/.cargo/env" ] && source "${HOME}/.cargo/env"

# --- Modern shell tools ---

# Starship prompt
command -v starship &>/dev/null && eval "$(starship init bash)"

# Zoxide (smart cd)
command -v zoxide &>/dev/null && eval "$(zoxide init bash --cmd j)"

# Skim keybindings
if command -v sk &>/dev/null; then
  # Try brew-installed skim keybindings, then common paths
  for sk_bindings in \
    "$(brew --prefix 2>/dev/null)/opt/sk/share/skim/completion.bash" \
    "$(brew --prefix 2>/dev/null)/opt/sk/share/skim/key-bindings.bash" \
    "${HOME}/.skim/shell/completion.bash" \
    "${HOME}/.skim/shell/key-bindings.bash" \
    "/usr/share/skim/completion.bash" \
    "/usr/share/skim/key-bindings.bash"; do
    [ -f "$sk_bindings" ] && source "$sk_bindings"
  done
  unset sk_bindings
fi

# fzf fuzzy search
command -v fzf &>/dev/null && eval "$(fzf --bash)"

