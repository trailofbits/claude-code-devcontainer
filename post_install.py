#!/usr/bin/env python3
"""Post-install configuration for Claude Code and Codex devcontainer.

Runs on container creation to set up:
- Onboarding bypass (when CLAUDE_CODE_OAUTH_TOKEN is set)
- Claude settings (bypassPermissions mode)
- Codex managed config
- Auditron from the mounted dotfiles flake
- Tmux configuration (200k history, mouse support)
- Directory ownership fixes for mounted volumes
"""

import contextlib
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path


def setup_onboarding_bypass():
    """Bypass the interactive onboarding wizard when CLAUDE_CODE_OAUTH_TOKEN is set.

    Runs `claude -p` to seed ~/.claude.json with auth state. The subprocess
    writes the config file during startup before the API call completes, so
    a timeout is expected and acceptable. After the subprocess finishes (or
    times out), we check whether ~/.claude.json was populated and only then
    set hasCompletedOnboarding.

    Workaround for https://github.com/anthropics/claude-code/issues/8938.
    """
    token = os.environ.get("CLAUDE_CODE_OAUTH_TOKEN", "").strip()
    if not token:
        print(
            "[post_install] No CLAUDE_CODE_OAUTH_TOKEN set, skipping onboarding bypass",
            file=sys.stderr,
        )
        return

    # When `CLAUDE_CONFIG_DIR` is set, as is done in `devcontainer.json`, `claude` unexpectedly
    # looks for `.claude.json` in *that* folder, instead of in `~`, contradicting the documentation.
    #  See https://github.com/anthropics/claude-code/issues/3833#issuecomment-3694918874
    claude_json_dir = Path(os.environ.get("CLAUDE_CONFIG_DIR", Path.home()))
    claude_json = claude_json_dir / ".claude.json"

    print("[post_install] Running claude -p to populate auth state...", file=sys.stderr)
    try:
        result = subprocess.run(
            ["claude", "-p", "ok"],
            capture_output=True,
            text=True,
            timeout=30,
        )
        if result.returncode != 0:
            print(
                f"[post_install] claude -p exited {result.returncode}: "
                f"{result.stderr.strip()}",
                file=sys.stderr,
            )
    except subprocess.TimeoutExpired:
        print(
            "[post_install] claude -p timed out (expected on cold start)",
            file=sys.stderr,
        )
    except (FileNotFoundError, OSError) as e:
        print(
            f"[post_install] Warning: could not run claude ({e}) — "
            "onboarding bypass skipped",
            file=sys.stderr,
        )
        return

    if not claude_json.exists():
        print(
            f"[post_install] Warning: {claude_json} not created by claude -p — "
            "onboarding bypass skipped",
            file=sys.stderr,
        )
        return

    config: dict = {}
    try:
        config = json.loads(claude_json.read_text())
    except json.JSONDecodeError as e:
        print(
            f"[post_install] Warning: {claude_json} has invalid JSON ({e}), "
            "starting fresh",
            file=sys.stderr,
        )

    config["hasCompletedOnboarding"] = True

    claude_json.write_text(json.dumps(config, indent=2) + "\n", encoding="utf-8")
    print(
        f"[post_install] Onboarding bypass configured: {claude_json}", file=sys.stderr
    )


def _link_managed_config(claude_dir, config_src):
    """Symlink the read-only managed config files into ~/.claude.

    Files (CLAUDE.md, statusline.sh) and dirs (commands, hooks, skills) are
    linked straight at the bind-mounted source (/opt/claude-config) so edits
    to the host dotfiles show up on the next container start. settings.json
    is handled separately — it's merged with bypassPermissions and written as
    a real file.
    """
    for name in ("CLAUDE.md", "statusline.sh", "commands", "hooks", "skills"):
        source = config_src / name
        if not source.exists():
            continue
        target = claude_dir / name
        if target.is_symlink() or target.is_file():
            target.unlink()
        elif target.is_dir():
            shutil.rmtree(target)
        target.symlink_to(source)
        print(f"[post_install] Linked {target} -> {source}", file=sys.stderr)


def setup_claude_settings():
    """Link managed dotfiles config into ~/.claude and write settings.json.

    The dotfiles Claude config is bind-mounted read-only at /opt/claude-config
    (see devcontainer.json). When present, its files are symlinked in and its
    settings.json is used as the base. bypassPermissions is always forced — the
    container is the isolation boundary, so the agent runs unattended inside it.
    """
    claude_dir = Path(os.environ.get("CLAUDE_CONFIG_DIR", Path.home() / ".claude"))
    claude_dir.mkdir(parents=True, exist_ok=True)

    config_src = Path("/opt/claude-config")
    settings = {}
    if config_src.is_dir() and any(config_src.iterdir()):
        _link_managed_config(claude_dir, config_src)
        base = config_src / "settings.json"
        if base.is_file():
            with contextlib.suppress(json.JSONDecodeError):
                settings = json.loads(base.read_text())
    else:
        print(
            "[post_install] /opt/claude-config not mounted — minimal settings only",
            file=sys.stderr,
        )

    # The container is the sandbox: run without permission prompts inside it.
    settings.setdefault("permissions", {})["defaultMode"] = "bypassPermissions"

    settings_file = claude_dir / "settings.json"
    if settings_file.is_symlink():
        settings_file.unlink()
    settings_file.write_text(json.dumps(settings, indent=2) + "\n", encoding="utf-8")
    print(
        f"[post_install] Claude settings configured: {settings_file}", file=sys.stderr
    )


def _link_managed_path(source, target):
    if not source.exists():
        return
    if target.is_symlink() or target.is_file():
        target.unlink()
    elif target.is_dir():
        shutil.rmtree(target)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.symlink_to(source)
    print(f"[post_install] Linked {target} -> {source}", file=sys.stderr)


def _copy_managed_config(source, target):
    """Install a writable config file once, preserving container-local edits."""
    if not source.is_file():
        return
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.is_symlink():
        target.unlink()
    elif target.exists():
        print(
            f"[post_install] Codex config exists, preserving {target}", file=sys.stderr
        )
        return
    shutil.copy2(source, target)
    print(f"[post_install] Installed writable {target} from {source}", file=sys.stderr)


def setup_codex_settings():
    """Link managed dotfiles config into ~/.codex and ~/.agents."""
    config_src = Path("/opt/codex-config")
    if not config_src.is_dir() or not any(config_src.iterdir()):
        print(
            "[post_install] /opt/codex-config not mounted — skipping Codex config",
            file=sys.stderr,
        )
        return

    codex_dir = Path.home() / ".codex"
    agents_dir = Path.home() / ".agents"
    codex_dir.mkdir(parents=True, exist_ok=True)
    agents_dir.mkdir(parents=True, exist_ok=True)

    _link_managed_path(config_src / "global-agents.md", codex_dir / "AGENTS.md")
    _copy_managed_config(
        config_src / "devcontainer-config.toml", codex_dir / "config.toml"
    )
    for name in ("profile-template.toml", "hooks", "rules"):
        _link_managed_path(config_src / name, codex_dir / name)
    _link_managed_path(config_src / ".agents" / "skills", agents_dir / "skills")

    print(f"[post_install] Codex settings configured: {codex_dir}", file=sys.stderr)


def _write_auditron_upgrade_helper():
    """Install a small helper for refreshing the Nix profile package."""
    helper = Path.home() / ".local" / "bin" / "auditron-upgrade"
    helper.parent.mkdir(parents=True, exist_ok=True)
    helper.write_text(
        """#!/bin/sh
set -eu

if [ ! -f /opt/dotfiles/flake.nix ]; then
  echo "[auditron-upgrade] /opt/dotfiles is not mounted" >&2
  exit 1
fi

sudo /opt/start-nix-daemon.sh >/dev/null 2>&1 || true

if command -v gh >/dev/null 2>&1; then
  gh auth setup-git --hostname github.com >/dev/null 2>&1 || true
fi

nix profile remove --regex '^auditron($|-).*' >/dev/null 2>&1 || true
exec nix profile add /opt/dotfiles#auditron
""",
        encoding="utf-8",
    )
    helper.chmod(0o755)
    print(
        f"[post_install] Auditron upgrade helper installed: {helper}", file=sys.stderr
    )


def _run_auditron_install_command(args, timeout):
    return subprocess.run(
        args,
        capture_output=True,
        text=True,
        timeout=timeout,
    )


def setup_auditron():
    """Install Auditron from the pinned dotfiles flake when credentials allow it."""
    _write_auditron_upgrade_helper()

    if shutil.which("auditron"):
        print("[post_install] Auditron already available on PATH", file=sys.stderr)
        return

    if not (Path("/opt/dotfiles") / "flake.nix").is_file():
        print(
            "[post_install] /opt/dotfiles not mounted — skipping Auditron install",
            file=sys.stderr,
        )
        return

    if not shutil.which("nix"):
        print(
            "[post_install] nix not found — skipping Auditron install", file=sys.stderr
        )
        return

    subprocess.run(
        ["sudo", "/opt/start-nix-daemon.sh"],
        capture_output=True,
        check=False,
        text=True,
    )

    if shutil.which("gh"):
        gh_result = _run_auditron_install_command(
            ["gh", "auth", "setup-git", "--hostname", "github.com"],
            timeout=30,
        )
        if gh_result.returncode != 0:
            print(
                "[post_install] gh auth setup-git failed; Auditron fetch may fail",
                file=sys.stderr,
            )

    result = _run_auditron_install_command(
        ["nix", "profile", "add", "/opt/dotfiles#auditron"],
        timeout=900,
    )
    if result.returncode == 0:
        print(
            "[post_install] Auditron installed from /opt/dotfiles#auditron",
            file=sys.stderr,
        )
        return

    detail = result.stderr.strip() or result.stdout.strip()
    print(f"[post_install] Auditron install skipped: {detail}", file=sys.stderr)


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
        Path.home() / ".codex",
        Path.home() / ".agents",
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
                    print(
                        f"[post_install] Fixed ownership: {dir_path}", file=sys.stderr
                    )
            except (PermissionError, subprocess.CalledProcessError) as e:
                print(
                    f"[post_install] Warning: Could not fix ownership of {dir_path}: {e}",
                    file=sys.stderr,
                )


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

# Codex
.codex/
.agents/

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
    print(
        f"[post_install] Local git config created: {local_gitconfig}", file=sys.stderr
    )


def main():
    """Run all post-install configuration."""
    print("[post_install] Starting post-install configuration...", file=sys.stderr)

    setup_onboarding_bypass()
    setup_claude_settings()
    setup_codex_settings()
    setup_tmux_config()
    fix_directory_ownership()
    setup_global_gitignore()
    setup_auditron()

    print("[post_install] Configuration complete!", file=sys.stderr)


if __name__ == "__main__":
    main()
