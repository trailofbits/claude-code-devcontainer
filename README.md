# Claude Code in a devcontainer

A sandboxed development environment for running Claude Code with `bypassPermissions` safely enabled. Built at [Trail of Bits](https://www.trailofbits.com/) for security audit workflows.

## Why Use This?

Running Claude with `bypassPermissions` on your host machine is risky—it can execute any command without confirmation. This devcontainer provides **filesystem isolation** so you get the productivity benefits of unrestricted Claude without risking your host system.

**Designed for:**

- **Security audits**: Review client code without risking your host
- **Untrusted repositories**: Explore unknown codebases safely
- **Experimental work**: Let Claude modify code freely in isolation
- **Multi-repo engagements**: Work on multiple related repositories

**Works with:** VS Code, Cursor, and JetBrains IDEs (IntelliJ, GoLand, PyCharm, etc.)

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

**JetBrains IDEs (IntelliJ, GoLand, PyCharm, etc.):**

1. Install the [Dev Containers plugin](https://plugins.jetbrains.com/plugin/21962-dev-containers) from the JetBrains Marketplace
2. Set up the devcontainer:

   ```bash
   devc .
   ```

3. Open the project in your JetBrains IDE — it will detect `.devcontainer/devcontainer.json` and offer to reopen in the container

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
devc destroy [-f]   Remove container, volumes, and image for current project
devc down           Stop the container
devc shell          Open zsh shell in container
devc exec CMD       Execute command inside the container
devc upgrade        Upgrade Claude Code in the container
devc mount SRC DST  Add a bind mount (host → container)
devc sync [NAME]    Sync Claude Code sessions from devcontainers to host
devc template DIR   Copy devcontainer files to directory
devc self-install   Install devc to ~/.local/bin
```

> **Note:** Use `devc destroy` to clean up a project's Docker resources. Removing containers manually (e.g., `docker rm`) will leave orphaned volumes and images behind that `devc destroy` won't be able to find.

## Session Sync for `/insights`

Claude Code's `/insights` command analyzes your session history, but it only reads from `~/.claude/projects/` on the host. Sessions inside devcontainer volumes are invisible to it.

`devc sync` copies session logs from all devcontainers (running and stopped) to the host so `/insights` can include them:

```bash
devc sync              # Sync all devcontainers
devc sync crypto       # Filter by project name (substring match)
```

Devcontainers are auto-discovered via Docker labels — no need to know container names or IDs. The sync is incremental, so it's safe to run repeatedly.

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

## Plugin Configuration

Marketplace plugin sources are installed at build time, but plugins must be individually enabled. To avoid manual enabling after each rebuild, configure auto-enabled plugins in `.dotfiles/.claude/settings.json`:

```json
{
  "enabledPlugins": {
    "context7@claude-plugins-official": true,
    "everything-claude-code@everything-claude-code": true,
    "code-simplifier@claude-plugins-official": true
  }
}
```

This file is deep-merged into `~/.claude/settings.json` at container creation, so your plugin selections persist across rebuilds. To disable a plugin, remove its entry or set it to `false`.

The format is `"plugin-name@marketplace-name": true`. To find available plugin names, run `claude plugin list` inside the container.

## API Key Passthrough

API keys set on the host are automatically forwarded into the container:

| Variable | Service |
|----------|---------|
| `ANTHROPIC_API_KEY` | Claude Code (bypasses interactive `claude login`) |
| `OPENAI_API_KEY` | OpenAI-based plugins and tools, Codex CLI |
| `EXA_API_KEY` | Exa AI search |
| `GH_TOKEN` | GitHub CLI and git HTTPS (see [GitHub Authentication](#github-authentication)) |
| `GEMINI_API_KEY` | Gemini CLI for PR reviews |

Add them to your host shell profile (e.g., `~/.bashrc`, `~/.zshrc`) so they persist across sessions. Environment variables are read from the host at **container creation time** — if you add or change a key, rebuild the container to pick it up:

```bash
# First time or after changing a key
export ANTHROPIC_API_KEY=sk-ant-...
devc rebuild                        # re-creates container with new env
devc shell
```

If a key is not set on the host, the variable is left unset inside the container so tools fall back to their default auth flow (e.g., `claude login`).

## AI Review CLIs

The container includes [Codex](https://github.com/openai/codex) and [Gemini CLI](https://github.com/google/gemini-cli), used by the `/review-pr` skill to provide independent review perspectives alongside Claude.

**Codex** uses `OPENAI_API_KEY` (already documented above). Get a key from [OpenAI Platform](https://platform.openai.com/api-keys). Verify with:

```bash
which codex
```

**Gemini CLI** uses `GEMINI_API_KEY`. Get a key from [Google AI Studio](https://aistudio.google.com/apikey) (free tier: 60 req/min, 1000 req/day). Add it to your host shell profile:

```bash
export GEMINI_API_KEY=AI...
```

Rebuild the container to pick it up, then verify:

```bash
devc rebuild
devc shell
gemini --version
```

## GitHub Authentication

Git and `gh` inside the container authenticate via one of two methods. The recommended approach uses a fine-grained PAT for minimal blast radius; the fallback uses interactive OAuth.

### Option A: Fine-Grained PAT (Recommended)

1. Create a [fine-grained personal access token](https://github.com/settings/tokens?type=beta) scoped to the repository you're working on. Grant only the permissions you need (typically **Contents: Read & write** and **Pull requests: Read & write**).

2. Add it to your host shell profile (`~/.bashrc` or `~/.zshrc`):

   ```bash
   export GH_TOKEN=github_pat_...
   ```

3. Rebuild the container to pick up the new variable, then verify:

   ```bash
   source ~/.zshrc       # or restart your terminal
   devc rebuild
   devc shell
   gh auth status        # should show "Logged in" via GH_TOKEN
   gh pr list            # uses GH_TOKEN automatically
   git push origin feat  # credential helper delegates to gh
   ```

The token flows through `containerEnv` in `devcontainer.json`. Inside the container, git's credential helper is configured to delegate to `gh auth git-credential`, which reads `GH_TOKEN` from the environment.

**Why this is safer:** A fine-grained PAT scoped to a single repo limits the damage if a prompt injection bypasses the safety hooks. Broad OAuth tokens grant access to every repo you can reach.

### Option B: Interactive OAuth (Fallback)

If `GH_TOKEN` is not set, fall back to `gh auth login`:

```bash
devc shell
gh auth login          # Follow the interactive browser flow
```

The OAuth credentials are stored in `~/.config/gh/`, which is a persistent Docker volume — they survive container rebuilds. However, this grants access to all repositories your GitHub account can reach.

### How It Works

| Layer | What it does |
|-------|-------------|
| `devcontainer.json` | Passes `GH_TOKEN` from host via `containerEnv` |
| `post_install.py` | Configures `[credential "https://github.com"]` in `~/.gitconfig.local` to delegate to `gh auth git-credential` |
| `.zshrc` / `.bashrc` | Unsets `GH_TOKEN` if the host didn't have it set (prevents empty string from overriding volume auth) |
| `check-shell-bypass.sh` | Blocks `GH_TOKEN=` and `GITHUB_TOKEN=` overrides to prevent prompt injection from hijacking auth |
| `~/.config/gh/` volume | Persists OAuth credentials for Option B across rebuilds |

## Host Directory Mounts

The following `~/.claude/` subdirectories are bind-mounted read-only into the container:

| Host path | Container path | Content |
|-----------|---------------|---------|
| `~/.claude/CLAUDE.md` | `~/.claude/CLAUDE.md` | Global instructions |
| `~/.claude/commands/` | `~/.claude/commands/` | Custom slash commands |
| `~/.claude/skills/` | `~/.claude/skills/` | Learned skills |
| `~/.claude/rules/` | `~/.claude/rules/` | Project rules |
| `~/.claude/docs/` | `~/.claude/docs/` | Documentation (e.g., `CI.md` referenced in CLAUDE.md) |

Directories are created on the host automatically if they don't exist. All mounts are **read-only** — skills and commands created inside the container won't persist to the host.

## Git Worktrees

Running `devc` from inside a git worktree works automatically. The CLI detects worktrees (where `.git` is a file, not a directory), resolves the main repository's `.git/` directory, and mounts it into the container at the same absolute path so git's `gitdir:` pointer resolves without modification.

```bash
git worktree add ../feature-branch feature-branch
cd ../feature-branch
devc .          # Worktree detected, main .git/ mounted automatically
devc shell
git status      # Works — full git history, commits, rebases all functional
```

**How it works:** `devc up` and `devc rebuild` call `git rev-parse --git-common-dir` to find the shared `.git/` directory, then inject a bind mount into `devcontainer.json`. The mount is read-write so commits, rebases, and merges work from inside the container.

**Limitations:**
- The main repository's `.git/` directory must be accessible to Docker (on macOS, paths under `/Users/` are shared by default)
- The worktree mount persists in `devcontainer.json` as a custom mount and survives `devc template` updates

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
| Base | Ubuntu 24.04, Node.js 22, Python 3.13 + uv, Deno |
| Shells | bash (default) and zsh (Oh My Zsh), both with starship prompt |
| User | `vscode` (passwordless sudo), working dir `/workspace` |
| Search & nav | `rg`, `fd`, `fzf`, `zoxide` (`j` to jump) |
| Dev tools | `tmux`, `delta`, `bat`, `eza`, `lazygit`, `ast-grep`, `codex`, `gemini` |
| Network | `iptables`, `ipset`, `dnsutils` |
| Volumes (survive rebuilds) | Command history (`/commandhistory`), Claude config (`~/.claude`), GitHub CLI auth (`~/.config/gh`) |
| Host mounts | `~/.gitconfig`, `.devcontainer/`, `~/.claude/{CLAUDE.md,commands,skills,rules,docs}` (all read-only) |
| API keys | `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `EXA_API_KEY`, `GH_TOKEN`, `GEMINI_API_KEY` (from host env) |
| Claude plugins | [anthropics](https://github.com/anthropics/claude-code-plugins) + [trailofbits](https://github.com/trailofbits/claude-code-plugins) skills, [everything-claude-code](https://github.com/nicobailon/everything-claude-code) |
| Dotfiles | Personal aliases, functions, exports, vim config, starship theme |

Volumes are stored outside the container, so your shell history, Claude settings, and `gh` login persist even after `devc rebuild`. Host `~/.gitconfig` is mounted read-only for git identity.

> **Nerd Font required:** The starship prompt uses Nerd Font glyphs. Install a [Nerd Font](https://www.nerdfonts.com/) (e.g., JetBrains Mono Nerd, FiraCode Nerd) in your host terminal, or prompt symbols will render as boxes.

## Troubleshooting

### "devcontainer CLI not found"

```bash
npm install -g @devcontainers/cli
```

### Container won't start

1. Check Docker is running
2. Try rebuilding: `devc rebuild`
3. Check logs: `docker logs $(docker ps -lq)`

### GitHub CLI / git push not working

If using a fine-grained PAT, verify it's reaching the container:

```bash
gh auth status          # Should show "Logged in" via GH_TOKEN
```

If using OAuth, the `~/.config/gh/` volume may need an ownership fix:

```bash
sudo chown -R $(id -u):$(id -g) ~/.config/gh
```

See [GitHub Authentication](#github-authentication) for full setup instructions.

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

# Verify tools
devcontainer exec --workspace-folder . bash -c \
  "starship --version && zoxide --version && bat --version && eza --version && lazygit --version && fd --version && deno --version && claude --version"

# Verify both shells
devcontainer exec --workspace-folder . zsh -ic "type j && type ll && type sg"
devcontainer exec --workspace-folder . bash -ic "type j && type ll && type sg"
```

Lint shell scripts:

```bash
shellcheck install.sh .bashrc .zshrc
shfmt -i 2 -d install.sh .bashrc
```
