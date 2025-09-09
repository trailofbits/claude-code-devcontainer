# Security Audit Development Container

A pre-configured slightly-sandboxed development environment using Claude Code for auditing. Claude Code and common tools pre-installed.
You will have to re-authorize claude code with a plan or API key

for security auditing and analysis work, built on Ubuntu 24.04 with essential tools and Claude Code integration.

## Features

- **Claude Code** pre-installed and configured

## Quick Start

1. Clone this devcontainer configuration to your audits directory:

   ```bash
   git clone git@github.com/trailofbits/claude-code-devcontainer ~/audits/.devcontainer/
   ```

2. Open the audits folder in VS Code and select "Reopen in Container" when prompted, or use:

   ```bash
   cd ~/audits
   code .
   ```

3. VS Code will automatically build and start the development container

## Usage

The container runs as the `ubuntu` user with passwordless sudo access. Node.js and npm are available through nvm, and Claude Code is installed globally.

To verify the setup:

```bash
claude --version  # should show 1.0.x
claude doctor # shows config information
```

## Container Details

- **Base Image**: Ubuntu 24.04
- **Default User**: ubuntu
- **Working Directory**: /workspace
- **Shell**: zsh with Oh My Zsh
- **Editor**: vim
