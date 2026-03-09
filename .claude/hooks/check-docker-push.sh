#!/usr/bin/env bash
set -euo pipefail

# Block docker push — must be done manually.
# Usage: echo '{"tool_input":{"command":"docker push myimage"}}' | ./check-docker-push.sh

CMD=$(jq -r '.tool_input.command' | head -1)

if echo "$CMD" | grep -qE 'docker[[:space:]]+push'; then
	echo 'BLOCKED: Docker image pushing must be done manually' >&2
	exit 2
fi
