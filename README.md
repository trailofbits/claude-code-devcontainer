# Claude Code in a devcontainer

A sandboxed development environment for running Claude Code with `bypassPermissions` safely enabled. Built at [Trail of Bits](https://www.trailofbits.com/) for security audit workflows.

## Why Use This?

Running Claude with `bypassPermissions` on your host machine is risky—it can execute any command without confirmation. This devcontainer provides **filesystem isolation** so you get the productivity benefits of unrestricted Claude without risking your host system.

**Designed for:**

- **Security audits**: Review client code without risking your host
- **Untrusted repositories**: Explore unknown codebases safely
- **Experimental work**: Let Claude modify code freely in isolation
- **Multi-repo engagements**: Work on multiple related repositories

## Prerequisites

- **Docker runtime** (one of):
  - [Docker Desktop](https://docker.com/products/docker-desktop) - ensure it's running
  - [OrbStack](https://orbstack.dev/)
  - [Colima](https://github.com/abiosoft/colima): `brew install colima docker && colima start`

<details>
<summary><strong>Optimizing Colima for Apple Silicon</strong></summary>

Colima's defaults (QEMU + sshfs) are conservative. For better performance:

```bash
# Stop and delete current VM (removes containers/images)
colima stop && colima delete

# Start with optimized settings
colima start \
  --cpu 4 \
  --memory 8 \
  --disk 100 \
  --vm-type vz \
  --vz-rosetta \
  --mount-type virtiofs
```

Adjust `--cpu` and `--memory` based on your Mac (e.g., 6/16 for Pro, 8/32 for Max).

| Option | Benefit |
|--------|---------|
| `--vm-type vz` | Apple Virtualization.framework (faster than QEMU) |
| `--mount-type virtiofs` | 5-10x faster file I/O than sshfs |
| `--vz-rosetta` | Run x86 containers via Rosetta |

Verify with `colima status` - should show "macOS Virtualization.Framework" and "virtiofs".

</details>

## Quick Start

Choose the pattern that fits your workflow:

### Pattern A: Per-Project Container (Isolated)

Each project gets its own container with independent volumes. Best for one-off reviews, untrusted repos, or when you need isolation between projects.

**VS Code / Cursor:**

1. Install the Dev Containers extension:
   - VS Code: `ms-vscode-remote.remote-containers`
   - Cursor: `anysphere.remote-containers`

2. Clone this repo into your project's `.devcontainer/` folder:

   ```bash
   git clone <untrusted-repo>
   cd untrusted-repo
   git clone https://github.com/trailofbits/claude-code-devcontainer .devcontainer/
   ```

3. Open **your project folder** in VS Code, then:
   - Press `Cmd+Shift+P` (Mac) or `Ctrl+Shift+P` (Windows/Linux)
   - Type "Reopen in Container" and select **Dev Containers: Reopen in Container**

**Terminal (without VS Code):**

```bash
# Install devcontainer CLI if needed
npm install -g @devcontainers/cli

# Install the devc helper (one-time)
git clone https://github.com/trailofbits/claude-code-devcontainer ~/.claude-devcontainer
~/.claude-devcontainer/install.sh self-install

# Clone untrusted repo and start container
git clone <untrusted-repo>
cd untrusted-repo
devc .          # Installs template + starts container
devc shell      # Opens shell in container
```

### Pattern B: Shared Workspace Container (Grouped)

A parent directory contains the devcontainer config, and you clone multiple repos inside. Shared volumes across all repos. Best for client engagements, related repositories, or ongoing work.

```bash
# Create workspace for a client engagement
mkdir -p ~/sandbox/client-name
cd ~/sandbox/client-name
devc .                        # Install template + start

devc shell
# Inside container:
git clone <client-repo-1>
git clone <client-repo-2>
cd client-repo-1
claude                        # Ready to work
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

## Network Isolation

By default, containers have full outbound network access. For stricter security, use iptables to restrict network access.

### When to Enable Network Isolation

- Reviewing code that may contain malicious dependencies
- Auditing software with telemetry or phone-home behavior
- Maximum isolation for highly sensitive reviews

### Example: Claude + GitHub + Package Registries

```bash
sudo iptables -A OUTPUT -d api.anthropic.com -j ACCEPT
sudo iptables -A OUTPUT -d github.com -j ACCEPT
sudo iptables -A OUTPUT -d raw.githubusercontent.com -j ACCEPT
sudo iptables -A OUTPUT -d registry.npmjs.org -j ACCEPT
sudo iptables -A OUTPUT -d pypi.org -j ACCEPT
sudo iptables -A OUTPUT -d files.pythonhosted.org -j ACCEPT
sudo iptables -A OUTPUT -o lo -j ACCEPT
sudo iptables -A OUTPUT -j DROP
```

### Trade-offs

- Blocks package managers unless you allowlist registries
- May break tools that require network access
- DNS resolution still works (consider blocking if paranoid)

## Security Model

This devcontainer provides **filesystem isolation** but not complete sandboxing.

**Sandboxed:** Filesystem (host files inaccessible), processes (isolated from host), package installations (stay in container)

**Not sandboxed:** Network (full outbound by default—see [Network Isolation](#network-isolation)), git identity (`~/.gitconfig` mounted read-only), Docker socket (not mounted by default)

### The `bypassPermissions` Setting

This container auto-configures Claude Code with `bypassPermissions` mode, which:

- Allows Claude to run commands without confirmation prompts
- Is appropriate here because the container itself is the sandbox
- Would be risky on a host machine but is safe in this isolated environment

<details>
<summary><strong>Reference</strong></summary>

### Container Details

| Feature | Value |
|---------|-------|
| Base Image | Ubuntu 24.04 |
| Node.js | 22 (via devcontainer feature) |
| Python | 3.13 + uv |
| Shell | zsh with Oh My Zsh |
| User | vscode (passwordless sudo) |
| Working Directory | /workspace |

### Included Tools

**Modern CLI:** `rg` (ripgrep), `fd` (fdfind), `tmux` (200k history), `fzf`, `delta`

**Network/Security:** `iptables`, `ipset`, `iproute2`, `dnsutils`

### Persistent Volumes

| Volume | Path | Purpose |
|--------|------|---------|
| Command history | /commandhistory | zsh/bash history |
| Claude config | ~/.claude | Settings, API keys |
| GitHub CLI | ~/.config/gh | gh auth tokens |

Your host `~/.gitconfig` is mounted read-only for git identity.

### Auto-Configuration

On container creation, `post_install.py` automatically sets `bypassPermissions` mode, creates tmux config with 200k scrollback, sets up git-delta as default pager, fixes volume ownership, and creates global gitignore.

### Verification

```bash
claude --version          # Check Claude CLI version
cat ~/.claude/settings.json  # Verify bypassPermissions
python3 --version         # Python 3.13
rg --version              # ripgrep
```

</details>

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
