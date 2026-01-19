# Claude Code in a devcontainer

A pre-configured sandboxed development environment for Claude Code with `--dangerously-skip-permissions` mode automatically enabled.

## Features

- **Claude Code** pre-installed with `bypassPermissions` auto-configured
- **Multi-stage Docker build** for smaller images
- **Node.js 23** and **Python 3.13** with **uv** package manager
- **Modern CLI tools**: ripgrep, fd, tmux, fzf
- **Session persistence**: command history, GitHub CLI auth, Claude config survive rebuilds
- **Network tools**: iptables, ipset for security testing

## Quick Start

### Option 1: VS Code / Cursor

1. Install the Dev Containers extension:
   - VS Code: `ms-vscode-remote.remote-containers`
   - Cursor: `anysphere.remote-containers`

2. Clone this repo to your project directory:

   ```bash
   git clone git@github.com:trailofbits/claude-code-devcontainer ~/audits/.devcontainer/
   ```

3. Open the folder in VS Code and select "Reopen in Container" when prompted.

### Option 2: Terminal (without VS Code)

1. Install the devcontainer CLI:

   ```bash
   npm install -g @devcontainers/cli
   ```

2. Install the `devc` helper:

   ```bash
   ./install.sh self-install
   ```

3. Use `devc` to manage containers:

   ```bash
   devc template ~/my-project  # Copy template to project
   cd ~/my-project
   devc up                     # Start container
   devc shell                  # Open shell
   devc rebuild                # Rebuild (preserves auth)
   ```

## CLI Helper Commands

```
devc .              Install template + start container in current directory
devc up             Start the devcontainer
devc rebuild        Rebuild container (preserves persistent volumes)
devc down           Stop the container
devc shell          Open zsh shell in container
devc template DIR   Copy devcontainer files to directory
devc self-install   Install devc to ~/.local/bin
```

## Container Details

| Feature | Value |
|---------|-------|
| Base Image | Ubuntu 25.04 |
| Node.js | 23 (via multi-stage build) |
| Python | 3.13 + uv |
| Shell | zsh with Oh My Zsh |
| User | ubuntu (passwordless sudo) |
| Working Directory | /workspace |

### Included Tools

**Modern CLI:**
- `rg` (ripgrep) - Fast grep replacement
- `fd` (fdfind) - Fast find replacement
- `tmux` - Terminal multiplexer (200k history)
- `fzf` - Fuzzy finder
- `delta` - Better git diffs

**Network/Security:**
- `iptables`, `ipset` - Firewall tools
- `iproute2`, `dnsutils` - Network diagnostics

## Persistent Volumes

The following data persists across container rebuilds:

| Volume | Path | Purpose |
|--------|------|---------|
| Command history | /commandhistory | zsh/bash history |
| Claude config | ~/.claude | Settings, API keys |
| GitHub CLI | ~/.config/gh | gh auth tokens |

Your host `~/.gitconfig` is mounted read-only for git identity.

## Auto-Configuration

On container creation, `post_install.py` automatically:

1. Sets Claude to `bypassPermissions` mode
2. Creates tmux config with 200k scrollback
3. Sets up git-delta as default pager
4. Fixes volume ownership

## Verification

```bash
claude --version          # Check Claude CLI version
cat ~/.claude/settings.json  # Verify bypassPermissions
python3 --version         # Python 3.13
rg --version              # ripgrep
fd --version              # fd-find
tmux -V                   # tmux
```

## Troubleshooting

### "devcontainer CLI not found"

```bash
npm install -g @devcontainers/cli
```

### Container won't start

1. Check Docker is running
2. Try rebuilding: `devc rebuild`
3. Check logs: `docker logs $(docker ps -lq)`

### GitHub CLI auth not persisting

The gh volume may need ownership fix:

```bash
sudo chown -R $(id -u):$(id -g) ~/.config/gh
```

### Python/uv not working

Python is installed via uv. Use:

```bash
uv run python script.py  # Run with uv
uv pip install package   # Install packages
```

## Development

Build the image manually:

```bash
devcontainer build --workspace-folder .
```

Test the container:

```bash
devcontainer up --workspace-folder .
devcontainer exec --workspace-folder . zsh
```
