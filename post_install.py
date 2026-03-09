#!/usr/bin/env python3
"""Post-install configuration for Claude Code devcontainer.

Runs on container creation to set up:
- Claude settings (bypassPermissions mode)
- Tmux configuration (200k history, mouse support)
- Directory ownership fixes for mounted volumes
"""

import contextlib
import json
import os
import subprocess
import sys
from pathlib import Path


def setup_claude_settings():
    """Configure Claude Code with bypassPermissions enabled."""
    claude_dir = Path.home() / ".claude"
    claude_dir.mkdir(parents=True, exist_ok=True)

    settings_file = claude_dir / "settings.json"

    # Load existing settings or start fresh
    settings = {}
    if settings_file.exists():
        with contextlib.suppress(json.JSONDecodeError):
            settings = json.loads(settings_file.read_text())

    # Set bypassPermissions mode
    if "permissions" not in settings:
        settings["permissions"] = {}
    settings["permissions"]["defaultMode"] = "bypassPermissions"

    settings_file.write_text(json.dumps(settings, indent=2) + "\n", encoding="utf-8")
    print(f"[post_install] Claude settings configured: {settings_file}", file=sys.stderr)


def setup_tmux_config():
    """Configure tmux with 200k history, mouse support, and vi keys."""
    tmux_conf = Path.home() / ".tmux.conf"

    if tmux_conf.exists():
        print("[post_install] Tmux config exists, skipping", file=sys.stderr)
        return

    config = """\
# 200k line scrollback history
set-option -g history-limit 200000

# Enable mouse support
set -g mouse on

# Use vi keys in copy mode
setw -g mode-keys vi

# Start windows and panes at 1, not 0
set -g base-index 1
setw -g pane-base-index 1

# Renumber windows when one is closed
set -g renumber-windows on

# Faster escape time for vim
set -sg escape-time 10

# True color support
set -g default-terminal "tmux-256color"
set -ag terminal-overrides ",xterm-256color:RGB"

# Terminal features (ghostty, cursor shape in vim)
set -as terminal-features ",xterm-ghostty:RGB"
set -as terminal-features ",xterm*:RGB"
set -ga terminal-overrides ",xterm*:colors=256"
set -ga terminal-overrides '*:Ss=\\E[%p1%d q:Se=\\E[ q'

# Status bar
set -g status-style 'bg=#333333 fg=#ffffff'
set -g status-left '[#S] '
set -g status-right '%Y-%m-%d %H:%M'
"""
    tmux_conf.write_text(config, encoding="utf-8")
    print(f"[post_install] Tmux configured: {tmux_conf}", file=sys.stderr)


def fix_directory_ownership():
    """Fix ownership of mounted volumes that may have root ownership."""
    uid = os.getuid()
    gid = os.getgid()

    dirs_to_fix = [
        Path.home() / ".claude",
        Path("/commandhistory"),
        Path.home() / ".config" / "gh",
    ]

    for dir_path in dirs_to_fix:
        if dir_path.exists():
            try:
                # Use sudo to fix ownership if needed
                stat_info = dir_path.stat()
                if stat_info.st_uid != uid:
                    subprocess.run(
                        ["sudo", "chown", "-R", f"{uid}:{gid}", str(dir_path)],
                        check=True,
                        capture_output=True,
                    )
                    print(f"[post_install] Fixed ownership: {dir_path}", file=sys.stderr)
            except (PermissionError, subprocess.CalledProcessError) as e:
                print(
                    f"[post_install] Warning: Could not fix ownership of {dir_path}: {e}",
                    file=sys.stderr,
                )


def deep_merge(base: dict, override: dict) -> dict:
    """Deep merge two dicts: dicts recurse, lists deduplicate-concatenate, scalars overwrite."""
    result = dict(base)
    for key, val in override.items():
        if key in result and isinstance(result[key], dict) and isinstance(val, dict):
            result[key] = deep_merge(result[key], val)
        elif key in result and isinstance(result[key], list) and isinstance(val, list):
            merged = list(result[key])
            for item in val:
                if item not in merged:
                    merged.append(item)
            result[key] = merged
        else:
            result[key] = val
    return result


def setup_claude_settings_from_dotfiles():
    """Merge dotfiles settings.json into container Claude settings.

    The dotfiles settings are staged at /opt during build because ~/.claude/ is a
    Docker volume — files baked into the image layer are hidden by the volume mount.
    This function reads the staged copy and deep-merges it at runtime.
    """
    staged = Path("/opt/dotfiles-claude-settings.json")
    if not staged.exists():
        return

    override = {}
    with contextlib.suppress(json.JSONDecodeError):
        override = json.loads(staged.read_text())

    if not override:
        return

    settings_file = Path.home() / ".claude" / "settings.json"
    existing = {}
    if settings_file.exists():
        with contextlib.suppress(json.JSONDecodeError):
            existing = json.loads(settings_file.read_text())

    merged = deep_merge(existing, override)
    settings_file.write_text(json.dumps(merged, indent=2) + "\n", encoding="utf-8")
    print("[post_install] Claude settings merged from dotfiles", file=sys.stderr)


def setup_claude_statusline():
    """Deploy statusline script from dotfiles into the volume-mounted Claude config."""
    staged = Path("/opt/dotfiles-claude-statusline.sh")
    if not staged.exists():
        return

    target = Path.home() / ".claude" / "statusline.sh"
    target.write_bytes(staged.read_bytes())
    target.chmod(0o755)
    print(f"[post_install] Claude statusline deployed: {target}", file=sys.stderr)


def setup_claude_local_settings():
    """Merge dotfiles' settings.local.json into the volume-mounted Claude config.

    The dotfiles settings are staged at /opt during build because ~/.claude/ is a
    Docker volume — files baked into the image layer are hidden by the volume mount.
    This function reads the staged copy and deep-merges it at runtime.
    """
    staged = Path("/opt/dotfiles-claude-settings.local.json")
    if not staged.exists():
        return

    target = Path.home() / ".claude" / "settings.local.json"

    override = {}
    with contextlib.suppress(json.JSONDecodeError):
        override = json.loads(staged.read_text())

    if not override:
        return

    existing = {}
    if target.exists():
        with contextlib.suppress(json.JSONDecodeError):
            existing = json.loads(target.read_text())

    merged = deep_merge(existing, override)
    target.write_text(json.dumps(merged, indent=2) + "\n", encoding="utf-8")
    print(f"[post_install] Claude local settings merged: {target}", file=sys.stderr)


def setup_global_gitignore():
    """Set up global gitignore and local git config.

    Since ~/.gitconfig is mounted read-only from host, we create a local
    config file that includes the host config and adds container-specific
    settings like core.excludesfile and delta configuration.

    GIT_CONFIG_GLOBAL env var (set in devcontainer.json) points git to this
    local config as the "global" config.
    """
    home = Path.home()
    gitignore = home / ".gitignore_global"
    local_gitconfig = home / ".gitconfig.local"
    host_gitconfig = home / ".gitconfig"

    # Create global gitignore with common patterns
    patterns = """\
# Claude Code
.claude/

# macOS
.DS_Store
.AppleDouble
.LSOverride
._*

# Python
*.pyc
*.pyo
__pycache__/
*.egg-info/
.eggs/
*.egg
.venv/
venv/
.mypy_cache/
.ruff_cache/

# Node
node_modules/
.npm/

# Editors
*.swp
*.swo
*~
.idea/
.vscode/
*.sublime-*

# Misc
*.log
.env.local
.env.*.local
"""
    gitignore.write_text(patterns, encoding="utf-8")
    print(f"[post_install] Global gitignore created: {gitignore}", file=sys.stderr)

    # Create local git config that includes host config and sets excludesfile + delta
    # Delta config is included here so it works even if host doesn't have it configured
    local_config = f"""\
# Container-local git config
# Includes host config (mounted read-only) and adds container settings

[include]
    path = {host_gitconfig}

[core]
    excludesfile = {gitignore}
    pager = delta

[interactive]
    diffFilter = delta --color-only

[delta]
    navigate = true
    light = false
    line-numbers = true
    side-by-side = false

[merge]
    conflictstyle = diff3

[diff]
    colorMoved = default

[gpg "ssh"]
    program = /usr/bin/ssh-keygen
"""
    local_gitconfig.write_text(local_config, encoding="utf-8")
    print(f"[post_install] Local git config created: {local_gitconfig}", file=sys.stderr)


def setup_gh_credential_helper():
    """Configure git to use gh as credential helper for GitHub HTTPS operations.

    Appends a credential helper block to ~/.gitconfig.local that delegates
    to `gh auth git-credential`. Works whether GH_TOKEN is set (uses the
    token) or not (falls back to ~/.config/gh/ volume auth).
    """
    local_gitconfig = Path.home() / ".gitconfig.local"
    if not local_gitconfig.exists():
        print("[post_install] No .gitconfig.local found, skipping gh credential helper", file=sys.stderr)
        return

    content = local_gitconfig.read_text(encoding="utf-8")
    marker = '[credential "https://github.com"]'
    if marker in content:
        print("[post_install] gh credential helper already configured, skipping", file=sys.stderr)
        return

    block = f"""
{marker}
    helper =
    helper = !/usr/bin/gh auth git-credential
"""
    local_gitconfig.write_text(content + block, encoding="utf-8")
    print(f"[post_install] gh credential helper configured: {local_gitconfig}", file=sys.stderr)


def validate_git_worktree():
    """Check if workspace is a git worktree and verify the git dir is accessible."""
    git_file = Path("/workspace/.git")
    if not git_file.exists() or git_file.is_dir():
        return

    content = git_file.read_text().strip()
    if not content.startswith("gitdir:"):
        return

    gitdir_path = Path(content.split(":", 1)[1].strip())
    if gitdir_path.exists():
        print(f"[post_install] Git worktree OK: {gitdir_path}", file=sys.stderr)
    else:
        print(
            f"[post_install] WARNING: Git worktree target not found: {gitdir_path}\n"
            f"[post_install] Git operations will fail. Run 'devc rebuild' to fix.",
            file=sys.stderr,
        )


def main():
    """Run all post-install configuration."""
    print("[post_install] Starting post-install configuration...", file=sys.stderr)

    setup_claude_settings()
    setup_claude_settings_from_dotfiles()
    setup_claude_statusline()
    setup_claude_local_settings()
    setup_tmux_config()
    fix_directory_ownership()
    setup_global_gitignore()
    setup_gh_credential_helper()
    validate_git_worktree()

    print("[post_install] Configuration complete!", file=sys.stderr)


if __name__ == "__main__":
    main()
