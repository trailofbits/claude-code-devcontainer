# Claude Code in a devcontainer

A pre-configured slightly-sandboxed development environment using Claude Code with the `--dangerously-skip-permissions` yolo mode.
Claude Code and common tools pre-installed.

You will have to re-authorize claude code with a plan or API key.

Originally based on the official Claude Code devcontainer at https://github.com/anthropics/claude-code/tree/main/.devcontainer 

## Features

- **Claude Code** pre-installed and configured

## Quick Start

1. Install the Dev Containers package in vscode. The package name is `ms-vscode-remote.remote-containers` in Microsoft's vscode and `anysphere.remote-containers` in Cursor.

2. Clone this devcontainer configuration to your audits directory:

   ```
   git clone git@github.com:trailofbits/claude-code-devcontainer ~/audits/.devcontainer/
   ```

3. Open the audits folder in VS Code and select "Reopen in Container" when prompted, or use:

   ```
   cd ~/audits
   code .
   ```

4. VS Code will automatically build and start the development container. You may see this popup in the lower right.

<img width="461" height="101" alt="Screenshot 2025-09-08 at 11 46 34 PM" src="https://github.com/user-attachments/assets/9c00280b-b2ee-4909-ac2f-c46cfcf6f52c" />


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

## Development

In vscode action bar, choose "Install devcontainer CLI", then in a new terminal, you can run `devcontainer up` to build the docker image.

`devcontainer exec bash` or `devcontainer exec zsh` can be used to run a shell within the container if you'd like to use it outside of vscode
