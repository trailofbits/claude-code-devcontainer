#!/usr/bin/env bash
set -euo pipefail

# Block destructive cloud CLI operations — AWS delete/terminate, GCP delete, Azure delete.
# Allows: aws s3 ls, gcloud list, az list, etc.
# Usage: echo '{"tool_input":{"command":"aws s3 rm --recursive s3://bucket"}}' | ./check-cloud-cli.sh

CMD=$(jq -r '.tool_input.command' | head -1)

# AWS destructive commands — block
if echo "$CMD" | grep -qE 'aws[[:space:]]+.*[[:space:]](delete-|terminate-)'; then
	echo 'BLOCKED: AWS delete/terminate operations must be done manually' >&2
	exit 2
fi

if echo "$CMD" | grep -qE 'aws[[:space:]]+s3[[:space:]]+rm[[:space:]]+.*--recursive'; then
	echo 'BLOCKED: aws s3 rm --recursive deletes entire buckets' >&2
	exit 2
fi

# GCP destructive commands — block
if echo "$CMD" | grep -qE 'gcloud[[:space:]]+.*[[:space:]](delete|destroy)'; then
	echo 'BLOCKED: gcloud delete/destroy operations must be done manually' >&2
	exit 2
fi

# Azure destructive commands — block
if echo "$CMD" | grep -qE 'az[[:space:]]+.*[[:space:]]delete'; then
	echo 'BLOCKED: az delete operations must be done manually' >&2
	exit 2
fi

# gsutil rm -r — block
if echo "$CMD" | grep -qE 'gsutil[[:space:]]+rm[[:space:]]+.*-r'; then
	echo 'BLOCKED: gsutil rm -r recursively deletes cloud storage' >&2
	exit 2
fi