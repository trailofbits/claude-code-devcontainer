#!/usr/bin/env bash
set -euo pipefail

# Block npm/pnpm/yarn publish — must be done manually.
# Usage: echo '{"tool_input":{"command":"pnpm publish"}}' | ./check-publish.sh

CMD=$(jq -r '.tool_input.command' | head -1)

if echo "$CMD" | grep -qE '(npm|pnpm|yarn)[[:space:]]+publish'; then
	echo 'BLOCKED: Package publishing must be done manually' >&2
	exit 2
fi
