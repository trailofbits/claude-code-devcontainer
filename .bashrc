#!/usr/bin/env bash
# Bash configuration for Claude Code devcontainer

# --- PATH & fnm ---
export PATH="$HOME/.deno/bin:$HOME/.local/bin:$PATH"
export FNM_DIR="$HOME/.fnm"
export PATH="$FNM_DIR:$PATH"
eval "$(fnm env --use-on-cd)"

# --- Bash options ---
shopt -s nocaseglob # Case-insensitive globbing
shopt -s cdspell    # Autocorrect typos in cd
shopt -s autocd     # cd by typing directory name
shopt -s globstar   # Recursive globbing with **
shopt -s histappend # Append to history, don't overwrite

# --- Source dotfiles ---
# shellcheck disable=SC1091
[[ -f "$HOME/.exports" ]] && source "$HOME/.exports"
# shellcheck disable=SC1091
[[ -f "$HOME/.aliases" ]] && source "$HOME/.aliases"
# shellcheck disable=SC1091
[[ -f "$HOME/.functions" ]] && source "$HOME/.functions"

# --- Override history (after dotfiles, so container's 200k wins over dotfiles' 32k) ---
export HISTFILE=/commandhistory/.bash_history
export HISTSIZE=200000
export HISTFILESIZE=200000

# --- Bash completion ---
if [[ -f /usr/share/bash-completion/bash_completion ]]; then
  # shellcheck disable=SC1091
  source /usr/share/bash-completion/bash_completion
elif [[ -f /etc/bash_completion ]]; then
  # shellcheck disable=SC1091
  source /etc/bash_completion
fi

# --- Container-only aliases ---
alias sg=ast-grep
alias claude-yolo='claude --dangerously-skip-permissions'

# --- fzf configuration ---
export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
export FZF_ALT_C_COMMAND='fd --type d --hidden --follow --exclude .git'
export FZF_DEFAULT_OPTS='--height 40% --layout=reverse --border --info=inline'

eval "$(fzf --bash)"

# --- Starship prompt ---
eval "$(starship init bash)"

# --- Zoxide (j instead of cd) ---
eval "$(zoxide init bash --cmd j)"
