#!/bin/bash
set -euo pipefail

# Claude Code Devcontainer CLI Helper
# Provides the `devc` command for managing devcontainers

# Resolve symlinks to get actual script location
SOURCE="${BASH_SOURCE[0]}"
while [[ -L "$SOURCE" ]]; do
  DIR="$(cd "$(dirname "$SOURCE")" && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$(cd "$(dirname "$SOURCE")" && pwd)"
SCRIPT_NAME="$(basename "$0")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_usage() {
  cat <<EOF
Usage: devc <command> [options]

Commands:
    .                   Install devcontainer template to current directory and start
    up                  Start the devcontainer in current directory
    rebuild             Rebuild the devcontainer (preserves auth volumes)
    down                Stop the devcontainer
    shell               Open a shell in the running container
    self-install        Install 'devc' command to ~/.local/bin
    update              Update devc to the latest version
    template [dir]      Copy devcontainer template to directory (default: current)
    exec <cmd>          Execute a command in the running container
    upgrade             Upgrade Claude Code to latest version
    mount <host> <cont> Add a mount to the devcontainer (recreates container)
    env                 Print .devc.env from running container's env vars
    sync [project] [--trusted]  Sync sessions from devcontainers to host
    cp <cont> <host>    Copy files/directories from container to host
    destroy [-f]        Remove container, volumes, and image for current project
    help                Show this help message

Examples:
    devc .                      # Install template and start container
    devc up                     # Start container in current directory
    devc rebuild                # Clean rebuild
    devc shell                  # Open interactive shell
    devc self-install           # Install devc to PATH
    devc update                 # Update to latest version
    devc exec ls -la            # Run command in container
    devc upgrade                # Upgrade Claude Code to latest
    devc mount ~/data /data     # Add mount to container
    devc env > .devc.env        # Capture env vars from running container
    devc sync                   # Sync sessions from all devcontainers
    devc sync crypto            # Sync only matching devcontainer
    devc cp /some/file ./out    # Copy a path from container to host
    devc destroy                # Remove all project Docker resources
    devc destroy -f             # Skip confirmation prompt
EOF
}

log_info() {
  echo -e "${BLUE}[devc]${NC} $1"
}

log_success() {
  echo -e "${GREEN}[devc]${NC} $1"
}

log_warn() {
  echo -e "${YELLOW}[devc]${NC} $1"
}

log_error() {
  echo -e "${RED}[devc]${NC} $1" >&2
}

check_devcontainer_cli() {
  if ! command -v devcontainer &>/dev/null; then
    log_error "devcontainer CLI not found."
    log_info "Install it with: npm install -g @devcontainers/cli"
    exit 1
  fi
}

load_env_file() {
  local workspace="${1:-.}"
  local env_file="$workspace/.devc.env"
  if [[ ! -f "$env_file" ]]; then
    return 0
  fi
  log_info "Loading environment from $env_file"
  # Export non-empty, non-comment lines. Don't override vars already set in the shell.
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    key="${line%%=*}"
    value="${line#*=}"
    # Validate key is a POSIX identifier
    [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
    # Strip matching surrounding quotes from value
    if [[ "$value" == \"*\" ]]; then value="${value#\"}"; value="${value%\"}"; fi
    if [[ "$value" == \'*\' ]]; then value="${value#\'}"; value="${value%\'}"; fi
    if [[ -z "${!key:-}" && -n "$value" ]]; then
      export "$key=$value"
    fi
  done <"$env_file"
}

check_no_sys_admin() {
  local workspace="${1:-.}"
  local dc_json="$workspace/.devcontainer/devcontainer.json"
  [[ -f "$dc_json" ]] || return 0
  if jq -e \
    '.runArgs[]? | select(test("SYS_ADMIN"))' \
    "$dc_json" >/dev/null 2>&1; then
    log_error "SYS_ADMIN capability detected in runArgs."
    log_error "This defeats the read-only .devcontainer mount."
    exit 1
  fi
}

get_workspace_folder() {
  echo "${1:-$(pwd)}"
}

# Inject or remove --gpus from runArgs based on DEVC_GPU env var.
# Accepts: "all" or a positive integer (number of GPUs to expose).
# When unset, removes any --gpus entries from runArgs.
setup_gpu_passthrough() {
  local devcontainer_json="$1"

  [[ -f "$devcontainer_json" ]] || return 0

  local updated
  if [[ -n "${DEVC_GPU:-}" ]]; then
    DEVC_GPU="${DEVC_GPU,,}"
    if [[ "$DEVC_GPU" != "all" ]]; then
      if ! [[ "$DEVC_GPU" =~ ^[1-9][0-9]*$ ]] || (( DEVC_GPU > 128 )); then
        log_error "DEVC_GPU must be 'all' or a positive integer (1-128), got: $DEVC_GPU"
        exit 1
      fi
    fi
    local gpus_arg="--gpus=${DEVC_GPU}"
    log_info "GPU passthrough: ${DEVC_GPU}"
    updated=$(jq --arg gpu "$gpus_arg" '
      .runArgs = ((.runArgs // []) | map(select(startswith("--gpus") | not))) + [$gpu]
    ' "$devcontainer_json") || { log_error "jq failed updating $devcontainer_json"; return 1; }
  else
    updated=$(jq '
      .runArgs = ((.runArgs // []) | map(select(startswith("--gpus") | not)))
    ' "$devcontainer_json") || { log_error "jq failed updating $devcontainer_json"; return 1; }
  fi

  [[ -n "$updated" ]] || { log_error "jq produced empty output for $devcontainer_json"; return 1; }
  local tmp
  tmp=$(mktemp "${devcontainer_json}.tmp.XXXXXX")
  echo "$updated" >"$tmp" && mv "$tmp" "$devcontainer_json"
}

# Inject or remove --publish from runArgs based on DEVC_API_PORT env var.
# When set, publishes the port on localhost. When unset, removes any --publish
# entries so containers don't clash (especially across worktrees).
setup_port_publishing() {
  local devcontainer_json="$1"

  [[ -f "$devcontainer_json" ]] || return 0

  local updated
  if [[ -n "${DEVC_API_PORT:-}" ]]; then
    if ! [[ "$DEVC_API_PORT" =~ ^[0-9]+$ ]] || (( DEVC_API_PORT < 1 || DEVC_API_PORT > 65535 )); then
      log_error "DEVC_API_PORT must be a port number (1-65535), got: $DEVC_API_PORT"
      exit 1
    fi
    local publish_arg="--publish=127.0.0.1:${DEVC_API_PORT}:8000"
    log_info "Publishing port ${DEVC_API_PORT} → container 8000"
    updated=$(jq --arg pub "$publish_arg" '
      .runArgs = ((.runArgs // []) | map(select(startswith("--publish") | not))) + [$pub]
    ' "$devcontainer_json") || { log_error "jq failed updating $devcontainer_json"; return 1; }
  else
    updated=$(jq '
      .runArgs = ((.runArgs // []) | map(select(startswith("--publish") | not)))
    ' "$devcontainer_json") || { log_error "jq failed updating $devcontainer_json"; return 1; }
  fi

  [[ -n "$updated" ]] || { log_error "jq produced empty output for $devcontainer_json"; return 1; }
  echo "$updated" >"$devcontainer_json"
}

# Read .devc.packages from workspace and inject as EXTRA_PACKAGES build arg.
# Packages are installed in a separate cached Dockerfile layer.
setup_extra_packages() {
  local workspace="$1"
  local devcontainer_json="$workspace/.devcontainer/devcontainer.json"
  local packages_file="$workspace/.devc.packages"

  [[ -f "$devcontainer_json" ]] || return 0

  local packages=""
  if [[ -f "$packages_file" ]]; then
    # Read non-empty, non-comment lines into a space-separated string
    while IFS= read -r line || [[ -n "$line" ]]; do
      [[ -z "$line" || "$line" == \#* ]] && continue
      # Validate package name (alphanumeric, hyphens, dots, colons, plus signs)
      if [[ "$line" =~ ^[a-zA-Z0-9][a-zA-Z0-9.+:_-]*$ ]]; then
        packages="${packages:+$packages }$line"
      else
        log_warn "Skipping invalid package name: $line"
      fi
    done <"$packages_file"
  fi

  if [[ -z "$packages" ]]; then
    return 0
  fi

  log_info "Extra packages: $packages"

  local updated
  updated=$(jq --arg pkgs "$packages" '
    .build.args.EXTRA_PACKAGES = $pkgs
  ' "$devcontainer_json") || { log_error "jq failed updating $devcontainer_json"; return 1; }
  [[ -n "$updated" ]] || { log_error "jq produced empty output for $devcontainer_json"; return 1; }
  echo "$updated" >"$devcontainer_json"
}

# Detect if a workspace is a git worktree and resolve the main .git directory.
# Outputs the absolute path to the main .git/ directory on stdout.
# Returns empty (no output) if the workspace is a normal repo or not a git repo.
resolve_git_worktree() {
  local workspace="$1"

  # Not a git worktree if .git is a directory (normal repo) or missing
  [[ -f "$workspace/.git" ]] || return 0

  # git must be available on the host
  command -v git &>/dev/null || return 0

  # Resolve the shared .git directory (the "common dir")
  local common_dir
  common_dir=$(git -C "$workspace" rev-parse --git-common-dir 2>/dev/null) || return 0

  # Canonicalize to absolute path
  (cd "$common_dir" 2>/dev/null && pwd) || return 0
}

# If the workspace is a git worktree, inject a bind mount for the main .git
# directory so that git operations work inside the container. The mount uses
# the same absolute path on both host and container so the .git file's
# gitdir: pointer resolves without modification.
setup_worktree_mount() {
  local workspace="$1"
  local devcontainer_json="$workspace/.devcontainer/devcontainer.json"

  [[ -f "$devcontainer_json" ]] || return 0

  local git_dir
  git_dir=$(resolve_git_worktree "$workspace")

  if [[ -n "$git_dir" ]]; then
    log_info "Git worktree detected. Mounting $git_dir for git access."
    update_devcontainer_mounts "$devcontainer_json" "$git_dir" "$git_dir" "false"
  else
    # Clean up stale worktree mounts: remove any mount whose target ends
    # with /.git (the pattern used by injected worktree mounts)
    local updated
    updated=$(jq '
      .mounts = ((.mounts // []) | map(select(test("target=.*/\\.git,") | not)))
    ' "$devcontainer_json" 2>/dev/null) || return 0
    echo "$updated" >"$devcontainer_json"
  fi
}

# Extract custom mounts from devcontainer.json to a temp file
# Returns the temp file path, or empty string if no custom mounts
#
# Security: .devcontainer/ is mounted read-only inside the container to prevent
# a compromised process from injecting malicious mounts or commands into
# devcontainer.json that execute on the host during rebuild. This protection
# requires that SYS_ADMIN is never added to runArgs (it would allow remounting
# read-write).
extract_mounts_to_file() {
  local devcontainer_json="$1"
  local temp_file

  [[ -f "$devcontainer_json" ]] || return 0

  temp_file=$(mktemp)

  # Filter out default mounts by target path (immune to project name changes)
  local custom_mounts
  custom_mounts=$(jq -c '
    .mounts // [] | map(
      select(
        (contains("target=/commandhistory,") | not) and
        (contains("target=/home/vscode/.claude,") | not) and
        (contains("target=/home/vscode/.config/gh,") | not) and
        (contains("target=/home/vscode/.gitconfig,") | not) and
        (contains("target=/workspace/.devcontainer,") | not) and
        (contains("target=/home/vscode/.claude/CLAUDE.md,") | not) and
        (contains("target=/home/vscode/.claude/commands,") | not) and
        (contains("target=/home/vscode/.claude/skills,") | not) and
        (contains("target=/home/vscode/.claude/rules,") | not) and
        (contains("target=/home/vscode/.claude/docs,") | not)
      )
    ) | if length > 0 then . else empty end
  ' "$devcontainer_json" 2>/dev/null) || true

  if [[ -n "$custom_mounts" ]]; then
    echo "$custom_mounts" >"$temp_file"
    echo "$temp_file"
  else
    rm -f "$temp_file"
  fi
}

# Merge preserved mounts back into devcontainer.json
merge_mounts_from_file() {
  local devcontainer_json="$1"
  local mounts_file="$2"

  [[ -f "$mounts_file" ]] || return 0
  [[ -s "$mounts_file" ]] || return 0

  local custom_mounts
  custom_mounts=$(cat "$mounts_file")

  local updated
  updated=$(jq --argjson custom "$custom_mounts" '
    .mounts = ((.mounts // []) + $custom | unique)
  ' "$devcontainer_json")

  echo "$updated" >"$devcontainer_json"
}

# Add or update a mount in devcontainer.json
update_devcontainer_mounts() {
  local devcontainer_json="$1"
  local host_path="$2"
  local container_path="$3"
  local readonly="${4:-false}"

  local mount_str="source=${host_path},target=${container_path},type=bind"
  [[ "$readonly" == "true" ]] && mount_str="${mount_str},readonly"

  local updated
  updated=$(jq --arg target "$container_path" --arg mount "$mount_str" '
    .mounts = (
      ((.mounts // []) | map(select(contains("target=" + $target + ",") or endswith("target=" + $target) | not)))
      + [$mount]
    )
  ' "$devcontainer_json")

  echo "$updated" >"$devcontainer_json"
}

cmd_template() {
  local target_dir="${1:-.}"
  target_dir="$(cd "$target_dir" 2>/dev/null && pwd)" || {
    log_error "Directory does not exist: $1"
    exit 1
  }

  local devcontainer_dir="$target_dir/.devcontainer"
  local devcontainer_json="$devcontainer_dir/devcontainer.json"
  local preserved_mounts=""

  if [[ -d "$devcontainer_dir" ]]; then
    log_warn "Devcontainer already exists at $devcontainer_dir"
    read -p "Overwrite? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      log_info "Aborted."
      exit 0
    fi

    # Preserve custom mounts before overwriting
    preserved_mounts=$(extract_mounts_to_file "$devcontainer_json")
    if [[ -n "$preserved_mounts" ]]; then
      log_info "Preserving custom mounts..."
    fi
  fi

  mkdir -p "$devcontainer_dir"

  # Copy template files
  cp "$SCRIPT_DIR/Dockerfile" "$devcontainer_dir/"
  cp "$SCRIPT_DIR/devcontainer.json" "$devcontainer_dir/"
  cp "$SCRIPT_DIR/post_install.py" "$devcontainer_dir/"
  cp "$SCRIPT_DIR/.zshrc" "$devcontainer_dir/"
  cp "$SCRIPT_DIR/.bashrc" "$devcontainer_dir/"
  cp "$SCRIPT_DIR/.bash_profile" "$devcontainer_dir/"

  # Copy .devc.env.example so users know which env vars to set
  if [[ -f "$SCRIPT_DIR/.devc.env.example" ]]; then
    cp "$SCRIPT_DIR/.devc.env.example" "$target_dir/.devc.env.example"
  fi

  # Always create .dotfiles/ (Dockerfile COPY requires it to exist)
  mkdir -p "$devcontainer_dir/.dotfiles/.claude"

  # Copy dotfiles if present (optional — only in forks with .dotfiles/)
  if [[ -d "$SCRIPT_DIR/.dotfiles" ]]; then
    for f in .aliases .exports .functions .vimrc starship.toml; do
      [[ -f "$SCRIPT_DIR/.dotfiles/$f" ]] && cp "$SCRIPT_DIR/.dotfiles/$f" "$devcontainer_dir/.dotfiles/"
    done
    [[ -f "$SCRIPT_DIR/.dotfiles/.claude/settings.json" ]] &&
      cp "$SCRIPT_DIR/.dotfiles/.claude/settings.json" "$devcontainer_dir/.dotfiles/.claude/"
    [[ -f "$SCRIPT_DIR/.dotfiles/.claude/statusline.sh" ]] &&
      cp "$SCRIPT_DIR/.dotfiles/.claude/statusline.sh" "$devcontainer_dir/.dotfiles/.claude/"
    [[ -d "$SCRIPT_DIR/.dotfiles/nvim" ]] &&
      cp -r "$SCRIPT_DIR/.dotfiles/nvim" "$devcontainer_dir/.dotfiles/"
    log_info "Dotfiles copied"
  fi

  # Restore preserved mounts
  if [[ -n "$preserved_mounts" ]]; then
    merge_mounts_from_file "$devcontainer_json" "$preserved_mounts"
    rm -f "$preserved_mounts"
    log_info "Custom mounts restored"
  fi

  log_success "Template installed to $devcontainer_dir"
}

cmd_up() {
  local workspace_folder
  workspace_folder="$(get_workspace_folder "${1:-}")"

  check_devcontainer_cli
  load_env_file "$workspace_folder"
  check_no_sys_admin "$workspace_folder"
  setup_worktree_mount "$workspace_folder"
  setup_port_publishing "$workspace_folder/.devcontainer/devcontainer.json"
  setup_gpu_passthrough "$workspace_folder/.devcontainer/devcontainer.json"
  setup_extra_packages "$workspace_folder"
  log_info "Starting devcontainer in $workspace_folder..."

  devcontainer up --workspace-folder "$workspace_folder"
  log_success "Devcontainer started"
}

cmd_rebuild() {
  local workspace_folder
  workspace_folder="$(get_workspace_folder "${1:-}")"

  check_devcontainer_cli
  load_env_file "$workspace_folder"
  check_no_sys_admin "$workspace_folder"
  setup_worktree_mount "$workspace_folder"
  setup_port_publishing "$workspace_folder/.devcontainer/devcontainer.json"
  setup_gpu_passthrough "$workspace_folder/.devcontainer/devcontainer.json"
  setup_extra_packages "$workspace_folder"
  log_info "Rebuilding devcontainer in $workspace_folder..."

  devcontainer up --workspace-folder "$workspace_folder" --remove-existing-container
  log_success "Devcontainer rebuilt"
}

cmd_down() {
  local workspace_folder
  workspace_folder="$(get_workspace_folder "${1:-}")"

  check_devcontainer_cli
  log_info "Stopping devcontainer..."

  # Get container ID and stop it
  local label="devcontainer.local_folder=$workspace_folder"
  local container_id
  container_id=$(docker ps -q --filter "label=$label" 2>/dev/null || true)

  if [[ -n "$container_id" ]]; then
    docker stop "$container_id"
    log_success "Devcontainer stopped"
  else
    log_warn "No running devcontainer found for $workspace_folder"
  fi
}

cmd_shell() {
  local workspace_folder
  workspace_folder="$(get_workspace_folder)"

  check_devcontainer_cli
  log_info "Opening shell in devcontainer..."

  devcontainer exec --workspace-folder "$workspace_folder" bash
}

cmd_exec() {
  local workspace_folder
  workspace_folder="$(get_workspace_folder)"

  check_devcontainer_cli
  devcontainer exec --workspace-folder "$workspace_folder" "$@"
}

cmd_upgrade() {
  local workspace_folder
  workspace_folder="$(get_workspace_folder)"

  check_devcontainer_cli
  log_info "Upgrading Claude Code..."

  devcontainer exec --workspace-folder "$workspace_folder" claude update

  log_success "Claude Code upgraded"
}

cmd_env() {
  local workspace_folder
  workspace_folder="$(get_workspace_folder "${1:-}")"

  check_devcontainer_cli

  # Env vars to export — must match .devc.env.example
  local vars=(
    GH_TOKEN
    OPENAI_API_KEY
    CODEX_AZURE_BASE_URL
    ANTHROPIC_API_KEY
    EXA_API_KEY
    GEMINI_API_KEY
  )

  # Shell snippet receives var names as positional args, prints KEY=VALUE for each non-empty var
  # shellcheck disable=SC2016  # single quotes intentional; script runs inside the container
  local script='for v in "$@"; do val="${!v}"; [ -n "$val" ] && printf "%s=%s\n" "$v" "$val"; done; true'

  local output
  local exec_stderr
  exec_stderr=$(mktemp)
  if ! output=$(devcontainer exec --workspace-folder "$workspace_folder" bash -c "$script" -- "${vars[@]}" 2>"$exec_stderr"); then
    log_error "Failed to exec into container. Is it running? (devc up)"
    log_error "$(cat "$exec_stderr")"
    rm -f "$exec_stderr"
    exit 1
  fi
  rm -f "$exec_stderr"

  # Print header
  cat <<'HEADER'
# Devcontainer environment variables
# Generated by: devc env
# NEVER commit this file — it is gitignored.
HEADER

  # Print captured vars
  if [[ -n "$output" ]]; then
    echo "$output"
    echo ""
  fi

  # Host-side only vars — consumed by devc before container start
  echo "# Optional — expose container port 8000 on this host port (omit to skip)"
  echo "# DEVC_API_PORT=8000"
  echo ""
  echo "# Optional — GPU passthrough: \"all\" or number of GPUs (requires NVIDIA Container Toolkit)"
  echo "# DEVC_GPU=all"
  echo ""
}

cmd_mount() {
  local host_path="${1:-}"
  local container_path="${2:-}"
  local readonly="false"

  if [[ -z "$host_path" ]] || [[ -z "$container_path" ]]; then
    log_error "Usage: devc mount <host_path> <container_path> [--readonly]"
    exit 1
  fi

  [[ "${3:-}" == "--readonly" ]] && readonly="true"

  # Expand and validate host path
  host_path="$(cd "$host_path" 2>/dev/null && pwd)" || {
    log_error "Host path does not exist: $1"
    exit 1
  }

  local workspace_folder
  workspace_folder="$(get_workspace_folder)"
  local devcontainer_json="$workspace_folder/.devcontainer/devcontainer.json"

  if [[ ! -f "$devcontainer_json" ]]; then
    log_error "No devcontainer.json found. Run 'devc template' first."
    exit 1
  fi

  check_devcontainer_cli

  load_env_file "$workspace_folder"
  setup_port_publishing "$devcontainer_json"
  setup_gpu_passthrough "$devcontainer_json"

  log_info "Adding mount: $host_path → $container_path"
  update_devcontainer_mounts "$devcontainer_json" "$host_path" "$container_path" "$readonly"

  log_info "Recreating container with new mount..."
  devcontainer up --workspace-folder "$workspace_folder" --remove-existing-container

  log_success "Mount added: $host_path → $container_path"
}

cmd_sync() {
  local filter=""
  local trusted=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
    --trusted)
      trusted=true
      shift
      ;;
    *)
      filter="$1"
      shift
      ;;
    esac
  done

  local host_projects="${HOME}/.claude/projects"

  if [[ "$trusted" == false ]]; then
    log_warn "This copies files from devcontainers to your host filesystem."
    log_warn "Only proceed if you trust the container contents."
    log_info "Use --trusted to skip this prompt."
    read -p "Continue? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      log_info "Aborted."
      exit 0
    fi
  fi

  # Discover all devcontainers (running + stopped) by label.
  local container_ids
  container_ids=$(docker ps -a -q \
    --filter "label=devcontainer.local_folder" 2>/dev/null || true)

  if [[ -z "$container_ids" ]]; then
    log_error "No devcontainers found (running or stopped)."
    exit 1
  fi

  # List discovered devcontainers.
  log_info "Discovered devcontainers:"
  local matched_any=false
  while IFS= read -r cid; do
    local name folder status
    name=$(sync_get_project_name "$cid")
    folder=$(docker inspect --format \
      '{{index .Config.Labels "devcontainer.local_folder"}}' "$cid")
    status=$(docker inspect --format '{{.State.Status}}' "$cid")

    if [[ -n "$filter" ]]; then
      if ! echo "$name" | grep -qi "$filter"; then
        continue
      fi
    fi

    matched_any=true
    echo "  - ${name} (${status}) ${folder}"
  done <<< "$container_ids"

  if [[ "$matched_any" == false ]]; then
    log_error "No devcontainers matching '${filter}'."
    echo ""
    echo "Available:"
    while IFS= read -r cid; do
      local name status
      name=$(sync_get_project_name "$cid")
      status=$(docker inspect --format '{{.State.Status}}' "$cid")
      echo "  - ${name} (${status})"
    done <<< "$container_ids"
    exit 1
  fi

  echo ""

  # Sync matching containers.
  while IFS= read -r cid; do
    local name
    name=$(sync_get_project_name "$cid")

    if [[ -n "$filter" ]]; then
      if ! echo "$name" | grep -qi "$filter"; then
        continue
      fi
    fi

    sync_one_container "$cid" "$host_projects"
    echo ""
  done <<< "$container_ids"

  log_success "Run '/insights' in Claude Code to include these sessions."
}

# Extract project name from devcontainer.local_folder label.
sync_get_project_name() {
  local folder
  folder=$(docker inspect --format \
    '{{index .Config.Labels "devcontainer.local_folder"}}' "$1")
  basename "$folder"
}

# Resolve the Claude projects dir inside a container without
# docker exec (works on stopped containers too).
# Reads CLAUDE_CONFIG_DIR from container env, falls back to
# /home/<user>/.claude.
sync_get_claude_projects_dir() {
  local cid="$1"
  local claude_dir

  claude_dir=$(docker inspect --format '{{json .Config.Env}}' "$cid" \
    | tr ',' '\n' | tr -d '[]"' \
    | grep '^CLAUDE_CONFIG_DIR=' \
    | cut -d= -f2- || true)

  if [[ -n "$claude_dir" ]]; then
    echo "${claude_dir}/projects"
    return
  fi

  local user
  user=$(docker inspect --format '{{.Config.User}}' "$cid")
  if [[ -z "$user" || "$user" == "root" ]]; then
    echo "/root/.claude/projects"
  else
    echo "/home/${user}/.claude/projects"
  fi
}

sync_one_container() {
  local cid="$1"
  local host_projects="$2"
  local project_name status claude_dir folder

  project_name=$(sync_get_project_name "$cid")
  folder=$(docker inspect --format \
    '{{index .Config.Labels "devcontainer.local_folder"}}' "$cid")
  status=$(docker inspect --format '{{.State.Status}}' "$cid")
  claude_dir=$(sync_get_claude_projects_dir "$cid")

  log_info "=== ${project_name} (${status}) ==="
  echo "  Host path:  ${folder}"
  echo "  Container:  ${cid:0:12}"

  # docker cp works on both running and stopped containers.
  local tmpdir
  tmpdir=$(mktemp -d)

  if ! docker cp "${cid}:${claude_dir}/." "$tmpdir/" 2>/dev/null; then
    echo "  No sessions found, skipping."
    rm -rf "$tmpdir"
    return 0
  fi

  local session_count
  session_count=$(find "$tmpdir" -name '*.jsonl' | wc -l | tr -d ' ')

  if [[ "$session_count" -eq 0 ]]; then
    echo "  No sessions found, skipping."
    rm -rf "$tmpdir"
    return 0
  fi

  echo "  Sessions:   ${session_count}"

  local total_copied=0

  # Sync each project key subdirectory.
  for key_path in "$tmpdir"/*/; do
    [[ ! -d "$key_path" ]] && continue
    local key dest_key
    key=$(basename "$key_path")

    if [[ "$key" == "-workspace" ]]; then
      dest_key="-devcontainer-${project_name}"
    else
      dest_key="${key}"
    fi

    local dest_dir="${host_projects}/${dest_key}"
    mkdir -p "$dest_dir"

    local copied=0
    while IFS= read -r -d '' file; do
      local rel="${file#"$key_path"}"
      local dest_file="${dest_dir}/${rel}"
      mkdir -p "$(dirname "$dest_file")"

      if [[ ! -e "$dest_file" ]] \
          || [[ "$file" -nt "$dest_file" ]]; then
        cp -p "$file" "$dest_file"
        copied=$((copied + 1))
      fi
    done < <(find "$key_path" -type f -print0)

    if [[ "$copied" -gt 0 ]]; then
      echo "  Synced ${copied} file(s) -> ${dest_key}"
    fi
    total_copied=$((total_copied + copied))
  done

  # Handle .jsonl files directly in projects/ (no subdirectory).
  local orphan_copied=0
  local dest_dir="${host_projects}/-devcontainer-${project_name}"
  mkdir -p "$dest_dir"

  while IFS= read -r -d '' file; do
    local name
    name=$(basename "$file")
    local dest_file="${dest_dir}/${name}"

    if [[ ! -e "$dest_file" ]] \
        || [[ "$file" -nt "$dest_file" ]]; then
      cp -p "$file" "$dest_file"
      orphan_copied=$((orphan_copied + 1))
    fi
  done < <(find "$tmpdir" -maxdepth 1 -name '*.jsonl' -print0)

  if [[ "$orphan_copied" -gt 0 ]]; then
    echo "  Synced ${orphan_copied} file(s) -> -devcontainer-${project_name}"
    total_copied=$((total_copied + orphan_copied))
  fi

  rm -rf "$tmpdir"

  echo "  Total: ${total_copied} file(s) synced."
}

cmd_cp() {
  local container_path="${1:-}"
  local host_path="${2:-}"

  if [[ -z "$container_path" ]] || [[ -z "$host_path" ]]; then
    log_error "Usage: devc cp <container_path> <host_path>"
    exit 1
  fi

  local workspace_folder
  workspace_folder="$(get_workspace_folder)"

  # Find the running container
  local label="devcontainer.local_folder=$workspace_folder"
  local container_id
  container_id=$(docker ps -q --filter "label=$label" 2>/dev/null || true)

  if [[ -z "$container_id" ]]; then
    log_error "No running devcontainer found for $workspace_folder"
    exit 1
  fi

  log_info "Copying $container_path → $host_path"
  docker cp "$container_id:$container_path" "$host_path"
  log_success "Copied $container_path → $host_path"
}

cmd_self_install() {
  local install_dir="$HOME/.local/bin"
  local install_path="$install_dir/devc"

  mkdir -p "$install_dir"

  # Create a symlink to the original script
  ln -sf "$SCRIPT_DIR/$SCRIPT_NAME" "$install_path"

  log_success "Installed 'devc' to $install_path"

  # Check if in PATH
  if [[ ":$PATH:" != *":$install_dir:"* ]]; then
    log_warn "$install_dir is not in your PATH"
    log_info "Add this to your shell profile:"
    echo "    export PATH=\"\$HOME/.local/bin:\$PATH\""
  fi
}

cmd_update() {
  log_info "Updating devc..."

  if ! git -C "$SCRIPT_DIR" rev-parse --is-inside-work-tree &>/dev/null; then
    log_error "Not a git repository: $SCRIPT_DIR"
    log_info "Re-clone with: rm -rf ~/.claude-devcontainer && git clone https://github.com/trailofbits/claude-code-devcontainer ~/.claude-devcontainer"
    exit 1
  fi

  local before_sha after_sha
  before_sha=$(git -C "$SCRIPT_DIR" rev-parse HEAD)

  if ! git -C "$SCRIPT_DIR" pull --ff-only; then
    log_error "Update failed. Try: cd $SCRIPT_DIR && git pull"
    exit 1
  fi

  after_sha=$(git -C "$SCRIPT_DIR" rev-parse HEAD)

  if [[ "$before_sha" == "$after_sha" ]]; then
    log_success "Already up to date"
  else
    log_success "Updated from ${before_sha:0:7} to ${after_sha:0:7}"
  fi
}

cmd_dot() {
  # Install template and start container in one command
  cmd_template "."
  cmd_up "."
}

# Discovers all Docker resources associated with the current workspace.
# Sets global variables: CONTAINER_ID, CONTAINER_STATUS, VOLUMES (array), IMAGE, IMAGE_UID
discover_resources() {
  local workspace_folder="$1"
  local label="devcontainer.local_folder=$workspace_folder"

  CONTAINER_ID=""
  CONTAINER_STATUS=""
  VOLUMES=()
  IMAGE=""
  IMAGE_UID=""

  # Find container (any state: running, stopped, created, etc.)
  CONTAINER_ID=$(docker ps -aq --filter "label=$label" 2>/dev/null | head -1)

  if [[ -z "$CONTAINER_ID" ]]; then
    return 0
  fi

  # Get container status
  CONTAINER_STATUS=$(docker inspect "$CONTAINER_ID" --format '{{.State.Status}}' 2>/dev/null || true)

  # Get volumes (docker volumes only, not bind mounts)
  while IFS= read -r vol; do
    [[ -n "$vol" ]] && VOLUMES+=("$vol")
  done < <(docker inspect "$CONTAINER_ID" --format '{{json .Mounts}}' 2>/dev/null \
    | jq -r '.[] | select(.Type == "volume") | .Name' 2>/dev/null)

  # Get image and its -uid variant
  IMAGE=$(docker inspect "$CONTAINER_ID" --format '{{.Config.Image}}' 2>/dev/null || true)
  if [[ -n "$IMAGE" ]]; then
    if [[ "$IMAGE" == *-uid ]]; then
      IMAGE_UID="$IMAGE"
      IMAGE="${IMAGE%-uid}"
    else
      IMAGE_UID="${IMAGE}-uid"
    fi
  fi
}

print_destroy_summary() {
  echo ""
  log_warn "The following resources will be permanently removed:"
  echo ""

  if [[ -n "$CONTAINER_ID" ]]; then
    local container_name
    container_name=$(docker inspect "$CONTAINER_ID" --format '{{.Name}}' 2>/dev/null | sed 's|^/||')
    echo "  Container:  ${container_name:-$CONTAINER_ID}"
    if [[ "$CONTAINER_STATUS" == "running" ]]; then
      echo "              (currently running -- will be force-stopped)"
    fi
  fi

  if [[ ${#VOLUMES[@]} -gt 0 ]]; then
    echo "  Volumes:"
    for vol in "${VOLUMES[@]}"; do
      echo "              $vol"
    done
  fi

  if [[ -n "$IMAGE" ]]; then
    echo "  Image:      $IMAGE"
    if docker image inspect "$IMAGE_UID" &>/dev/null; then
      echo "              $IMAGE_UID"
    fi
  fi

  echo ""
}

cmd_destroy() {
  local force=false

  # Parse flags
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -f|--force)
        force=true
        shift
        ;;
      *)
        break
        ;;
    esac
  done

  local workspace_folder
  workspace_folder="$(get_workspace_folder "${1:-}")"

  discover_resources "$workspace_folder"

  # No resources found (idempotent behavior)
  if [[ -z "$CONTAINER_ID" ]]; then
    log_info "No devcontainer found for $workspace_folder"
    return 0
  fi

  print_destroy_summary

  # Running container warning
  if [[ "$CONTAINER_STATUS" == "running" && "$force" != true ]]; then
    log_warn "Container is currently running!"
    read -p "Force-stop the running container? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      log_info "Aborted."
      return 0
    fi
  fi

  # Main confirmation prompt
  if [[ "$force" != true ]]; then
    read -p "Destroy these resources? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      log_info "Aborted."
      return 0
    fi
  fi

  # Deletion, in order: stop, remove container, volumes, images
  if [[ -n "$CONTAINER_ID" && "$CONTAINER_STATUS" == "running" ]]; then
    log_info "Stopping container..."
    docker stop "$CONTAINER_ID" >/dev/null 2>&1 || true
  fi

  if [[ -n "$CONTAINER_ID" ]]; then
    log_info "Removing container..."
    docker rm -f "$CONTAINER_ID" >/dev/null 2>&1 || true
  fi

  for vol in "${VOLUMES[@]}"; do
    log_info "Removing volume: $vol"
    docker volume rm -f "$vol" >/dev/null 2>&1 || true
  done

  if [[ -n "$IMAGE" ]]; then
    log_info "Removing image: $IMAGE"
    docker rmi -f "$IMAGE" >/dev/null 2>&1 || true
    if docker image inspect "$IMAGE_UID" &>/dev/null 2>&1; then
      log_info "Removing image: $IMAGE_UID"
      docker rmi -f "$IMAGE_UID" >/dev/null 2>&1 || true
    fi
  fi

  log_success "All resources destroyed for $workspace_folder"
}

# Main command dispatcher
main() {
  if [[ $# -eq 0 ]]; then
    print_usage
    exit 1
  fi

  local command="$1"
  shift

  case "$command" in
  .)
    cmd_dot
    ;;
  up)
    cmd_up "$@"
    ;;
  rebuild)
    cmd_rebuild "$@"
    ;;
  down)
    cmd_down "$@"
    ;;
  destroy)
    cmd_destroy "$@"
    ;;
  shell)
    cmd_shell
    ;;
  exec)
    [[ "${1:-}" == "--" ]] && shift
    cmd_exec "$@"
    ;;
  upgrade)
    cmd_upgrade
    ;;
  env)
    cmd_env "$@"
    ;;
  mount)
    cmd_mount "$@"
    ;;
  sync)
    cmd_sync "$@"
    ;;
  cp)
    cmd_cp "$@"
    ;;
  self-install)
    cmd_self_install
    ;;
  update)
    cmd_update
    ;;
  template)
    cmd_template "$@"
    ;;
  help | --help | -h)
    print_usage
    ;;
  *)
    log_error "Unknown command: $command"
    print_usage
    exit 1
    ;;
  esac
}

main "$@"
