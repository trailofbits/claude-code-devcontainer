#!/usr/bin/env bash
set -euo pipefail

# Block destructive docker operations — push, system/volume prune, compose down -v.
# Allows: build, run, pull, compose up, compose down (without -v).
# Usage: echo '{"tool_input":{"command":"docker push myimage"}}' | ./check-docker.sh

CMD=$(jq -r '.tool_input.command' | head -1)

# Not a docker command — allow
echo "$CMD" | grep -qE 'docker' || exit 0

# Docker push — block
if echo "$CMD" | grep -qE 'docker[[:space:]]+push'; then
	echo 'BLOCKED: Docker image pushing must be done manually' >&2
	exit 2
fi

# System prune — block
if echo "$CMD" | grep -qE 'docker[[:space:]]+system[[:space:]]+prune'; then
	echo 'BLOCKED: docker system prune removes all unused data' >&2
	exit 2
fi

# Volume prune — block
if echo "$CMD" | grep -qE 'docker[[:space:]]+volume[[:space:]]+prune'; then
	echo 'BLOCKED: docker volume prune deletes all unused volumes' >&2
	exit 2
fi

# Compose down -v — block (removes volumes)
if echo "$CMD" | grep -qE 'docker[- ]compose[[:space:]]+down.*-v|docker[- ]compose[[:space:]]+down.*--volumes'; then
	echo 'BLOCKED: compose down -v destroys volumes with data' >&2
	exit 2
fi