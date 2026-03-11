#!/usr/bin/env bash
set -euo pipefail

# Allowlist for gh CLI — only PR and issue workflows allowed.
# Merging, closing, and other destructive operations must be done
# manually on GitHub.
#
# Allowed:
#   gh pr  create|edit|view|list|diff|checks|comment|ready|status
#   gh issue  view|list|create|comment
#   gh repo view
#   gh api  (GET only, no -X DELETE/PUT/PATCH/POST)
#
# Usage: echo '{"tool_input":{"command":"gh pr merge 1"}}' | ./check-gh.sh

CMD=$(jq -r '.tool_input.command' | head -1)

# Not a gh command — allow
echo "$CMD" | grep -qE 'gh[[:space:]]' || exit 0

# Label operations
echo "$CMD" | grep -qE 'gh[[:space:]]+(label[[:space:]]+(create|edit|view|list))' && exit 0

# PR operations
echo "$CMD" | grep -qE 'gh[[:space:]]+(pr[[:space:]]+(create|edit|view|list|diff|checks|comment|ready|status))' && exit 0

# Issue operations
echo "$CMD" | grep -qE 'gh[[:space:]]+(issue[[:space:]]+(view|list|create|comment))' && exit 0

# Repo view (read-only)
echo "$CMD" | grep -qE 'gh[[:space:]]+repo[[:space:]]+view' && exit 0

# gh api — allow GET (default), block write methods
if echo "$CMD" | grep -qE 'gh[[:space:]]+api'; then
	if echo "$CMD" | grep -qE '(-X|--method)[[:space:]]*(DELETE|PUT|PATCH|POST)'; then
		echo 'BLOCKED: Destructive gh api methods not allowed' >&2
		exit 2
	fi
	exit 0
fi

echo 'BLOCKED: Only gh pr (create|edit|view|list|diff|checks|comment|ready|status) and gh issue (view|list|create|comment) allowed. Other operations must be done manually on GitHub.' >&2
exit 2
