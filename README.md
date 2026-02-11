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

- **For terminal workflows** (one-time install):

  ```bash
  npm install -g @devcontainers/cli
  git clone https://github.com/trailofbits/claude-code-devcontainer ~/.claude-devcontainer
  ~/.claude-devcontainer/install.sh self-install
  ```

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

**Terminal:**

```bash
git clone <untrusted-repo>
cd untrusted-repo
devc .          # Installs template + starts container
devc shell      # Opens shell in container
```

**VS Code / Cursor:**

1. Install the Dev Containers extension:
   - VS Code: `ms-vscode-remote.remote-containers`
   - Cursor: `anysphere.remote-containers`

2. Set up the devcontainer (choose one):

   ```bash
   # Option A: Use devc (recommended)
   devc .

   # Option B: Clone manually
   git clone https://github.com/trailofbits/claude-code-devcontainer .devcontainer/
   ```

3. Open **your project folder** in VS Code, then:
   - Press `Cmd+Shift+P` (Mac) or `Ctrl+Shift+P` (Windows/Linux)
   - Type "Reopen in Container" and select **Dev Containers: Reopen in Container**

### Pattern B: Shared Workspace Container (Grouped)

A parent directory contains the devcontainer config, and you clone multiple repos inside. Shared volumes across all repos. Best for client engagements, related repositories, or ongoing work.

```bash
# Create workspace for a client engagement
mkdir -p ~/sandbox/client-name
cd ~/sandbox/client-name
devc .          # Install template + start container
devc shell      # Opens shell in container

# Inside container:
git clone <client-repo-1>
git clone <client-repo-2>
cd client-repo-1
claude          # Ready to work
```

## CLI Helper Commands

```
devc .              Install template + start container in current directory
devc up             Start the devcontainer
devc rebuild        Rebuild container (preserves persistent volumes)
devc down           Stop the container
devc shell          Open zsh shell in container
devc exec CMD       Execute command inside the container
devc upgrade        Upgrade Claude Code in the container
devc mount SRC DST  Add a bind mount (host → container)
devc template DIR   Copy devcontainer files to directory
devc self-install   Install devc to ~/.local/bin
```

## File Sharing

### VS Code / Cursor

Drag files from your host into the VS Code Explorer panel — they are copied into `/workspace/` automatically. No configuration needed.

### Terminal: `devc mount`

To make a host directory available inside the container:

```bash
devc mount ~/drop /drop           # Read-write
devc mount ~/secrets /secrets --readonly
```

This adds a bind mount to `devcontainer.json` and recreates the container. Existing mounts are preserved across `devc template` updates.

**Tip:** A shared "drop folder" is useful for passing files in without mounting your entire home directory.

> **Security note:** Avoid mounting large host directories (e.g., `$HOME`). Every mounted path is writable from inside the container unless `--readonly` is specified, which undermines the filesystem isolation this project provides.

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

The container auto-configures `bypassPermissions` mode—Claude runs commands without confirmation. This would be risky on a host machine, but the container itself is the sandbox.

## Container Details

| Component | Details |
|-----------|---------|
| Base | Ubuntu 24.04, Node.js 22, Python 3.13 + uv, zsh |
| User | `vscode` (passwordless sudo), working dir `/workspace` |
| Tools | `rg`, `fd`, `tmux`, `fzf`, `delta`, `iptables`, `ipset` |
| Volumes (survive rebuilds) | Command history (`/commandhistory`), Claude config (`~/.claude`), GitHub CLI auth (`~/.config/gh`) |
| Host mounts | `~/.gitconfig` (read-only), `.devcontainer/` (read-only) |
| Auto-configured | [anthropics](https://github.com/anthropics/claude-code-plugins) + [trailofbits](https://github.com/trailofbits/claude-code-plugins) skills, git-delta |

Volumes are stored outside the container, so your shell history, Claude settings, and `gh` login persist even after `devc rebuild`. Host `~/.gitconfig` is mounted read-only for git identity.

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

Python is managed via uv:

```bash
uv run script.py              # Run a script
uv add package                # Add project dependency
uv run --with requests py.py  # Ad-hoc dependency
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
