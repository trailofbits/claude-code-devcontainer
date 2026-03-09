#!/usr/bin/env bash
set -euo pipefail

# Block direct push to main/master — use feature branches.
# Usage: echo '{"tool_input":{"command":"git push origin main"}}' | ./check-git-push.sh

CMD=$(jq -r '.tool_input.command' | head -1)

if echo "$CMD" | grep -qE 'git[[:space:]]+push.*(main|master)'; then
	echo 'BLOCKED: Use feature branches, not direct push to main' >&2
	exit 2
fi
