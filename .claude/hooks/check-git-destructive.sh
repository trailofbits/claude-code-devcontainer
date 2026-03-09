#!/usr/bin/env bash
set -euo pipefail

# Block destructive git operations — force push, hard reset, clean, etc.
# Allows: push --force-with-lease (safe alternative), normal push to feature branches.
# Usage: echo '{"tool_input":{"command":"git push --force origin feat"}}' | ./check-git-destructive.sh

CMD=$(jq -r '.tool_input.command' | head -1)

# Not a git command — allow
echo "$CMD" | grep -qE 'git[[:space:]]' || exit 0

# Push to main/master — block
if echo "$CMD" | grep -qE 'git[[:space:]]+push.*(main|master)'; then
	echo 'BLOCKED: Use feature branches, not direct push to main/master' >&2
	exit 2
fi

# Force push — block (but allow --force-with-lease)
if echo "$CMD" | grep -qE 'git[[:space:]]+push.*--force'; then
	if echo "$CMD" | grep -qE '\-\-force-with-lease'; then
		exit 0
	fi
	echo 'BLOCKED: Use --force-with-lease instead of --force' >&2
	exit 2
fi
if echo "$CMD" | grep -qE 'git[[:space:]]+push[[:space:]]+-[a-zA-Z]*f([[:space:]]|$)'; then
	echo 'BLOCKED: Use --force-with-lease instead of -f push' >&2
	exit 2
fi

# Hard reset — block
if echo "$CMD" | grep -qE 'git[[:space:]]+reset[[:space:]]+--hard'; then
	echo 'BLOCKED: git reset --hard discards changes irreversibly' >&2
	exit 2
fi

# Clean -f — block
if echo "$CMD" | grep -qE 'git[[:space:]]+clean[[:space:]]+-[^[:space:]]*f'; then
	echo 'BLOCKED: git clean -f deletes untracked files irreversibly' >&2
	exit 2
fi

# Checkout discard all — block
if echo "$CMD" | grep -qE 'git[[:space:]]+checkout[[:space:]]+--[[:space:]]+\.'; then
	echo 'BLOCKED: git checkout -- . discards all uncommitted changes' >&2
	exit 2
fi

# Branch force delete — block
if echo "$CMD" | grep -qE 'git[[:space:]]+branch[[:space:]]+-D'; then
	echo 'BLOCKED: git branch -D force-deletes without merge check' >&2
	exit 2
fi

# Stash drop/clear — block
if echo "$CMD" | grep -qE 'git[[:space:]]+stash[[:space:]]+(drop|clear)'; then
	echo 'BLOCKED: git stash drop/clear destroys stashed changes' >&2
	exit 2
fi

# Skip hooks — block
if echo "$CMD" | grep -qE 'git[[:space:]]+.*--no-verify'; then
	echo 'BLOCKED: --no-verify bypasses safety hooks' >&2
	exit 2
fi

# Remote manipulation — block
if echo "$CMD" | grep -qE 'git[[:space:]]+remote[[:space:]]+(add|set-url)'; then
	echo 'BLOCKED: Changing git remotes must be done manually' >&2
	exit 2
fi
