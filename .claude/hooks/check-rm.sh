#!/usr/bin/env bash
set -euo pipefail

# Block rm -rf / rm -fr — use trash instead.
# Usage: echo '{"tool_input":{"command":"rm -rf /"}}' | ./check-rm.sh

CMD=$(jq -r '.tool_input.command' | head -1)

if echo "$CMD" | grep -qE 'rm[[:space:]]+-[^[:space:]]*r[^[:space:]]*f'; then
	echo 'BLOCKED: Use trash instead of rm -rf' >&2
	exit 2
fi
