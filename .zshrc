# shellcheck shell=bash
# Zsh configuration for Claude Code devcontainer

# --- PATH & fnm ---
export PATH="$HOME/.deno/bin:$HOME/.local/bin:$PATH"
export FNM_DIR="$HOME/.fnm"
export PATH="$FNM_DIR:$PATH"
eval "$(fnm env --use-on-cd)"

# --- Zsh options ---
setopt SHARE_HISTORY
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_REDUCE_BLANKS
setopt HIST_VERIFY
setopt AUTO_CD
setopt AUTO_PUSHD
setopt PUSHD_IGNORE_DUPS
setopt PUSHD_SILENT
setopt COMPLETE_IN_WORD
setopt ALWAYS_TO_END

# --- Source dotfiles ---
# shellcheck disable=SC1091
[[ -f "$HOME/.exports" ]] && source "$HOME/.exports"
# shellcheck disable=SC1091
[[ -f "$HOME/.aliases" ]] && source "$HOME/.aliases"
# Remove Oh My Zsh git plugin alias that conflicts with gwt() function
unalias gwt 2>/dev/null
# shellcheck disable=SC1091
[[ -f "$HOME/.functions" ]] && source "$HOME/.functions"

# --- Override history (after dotfiles, so container's 200k wins over dotfiles' 32k) ---
export HISTFILE=/commandhistory/.zsh_history
export HISTSIZE=200000
export SAVEHIST=200000

# --- Unset empty credential vars (localEnv sets "" when unset on host) ---
for _var in ANTHROPIC_API_KEY OPENAI_API_KEY EXA_API_KEY GH_TOKEN; do
  [[ -z "${(P)_var}" ]] && unset "$_var"
done
unset _var

# --- Container-only aliases ---
alias sg=ast-grep
alias claude-yolo='claude --dangerously-skip-permissions'

# --- fzf configuration ---
export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
export FZF_ALT_C_COMMAND='fd --type d --hidden --follow --exclude .git'
export FZF_DEFAULT_OPTS='--height 40% --layout=reverse --border --info=inline'

_fzf_compgen_path() {
  fd --hidden --follow --exclude .git . "$1"
}
_fzf_compgen_dir() {
  fd --type d --hidden --follow --exclude .git . "$1"
}

eval "$(fzf --zsh)"

# --- Starship prompt ---
eval "$(starship init zsh)"

# --- Zoxide (j instead of cd) ---
eval "$(zoxide init zsh --cmd j)"
