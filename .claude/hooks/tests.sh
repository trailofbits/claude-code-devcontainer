#!/usr/bin/env bash
set -euo pipefail

# Test suite for PreToolUse hook scripts.
# Usage: .claude/hooks/tests.sh

HOOKS_DIR="$(cd "$(dirname "$0")" && pwd)"
PASS=0
FAIL=0

assert_allowed() {
	local hook="$1" cmd="$2" label="$3"
	if echo "{\"tool_input\":{\"command\":\"$cmd\"}}" | "$HOOKS_DIR/$hook" >/dev/null 2>&1; then
		((++PASS))
	else
		echo "FAIL (expected ALLOW): [$hook] $label" >&2
		((++FAIL))
	fi
}

assert_blocked() {
	local hook="$1" cmd="$2" label="$3"
	if echo "{\"tool_input\":{\"command\":\"$cmd\"}}" | "$HOOKS_DIR/$hook" >/dev/null 2>&1; then
		echo "FAIL (expected BLOCK): [$hook] $label" >&2
		((++FAIL))
	else
		((++PASS))
	fi
}

# --- check-rm.sh ---

assert_blocked check-rm.sh "rm -rf /tmp/test" "rm -rf"
assert_blocked check-rm.sh "rm -fr /tmp/test" "rm -fr"
assert_blocked check-rm.sh "rm -rfi /tmp/test" "rm -rfi"
assert_allowed check-rm.sh "rm file.txt" "rm without -rf"
assert_allowed check-rm.sh "rm -f file.txt" "rm -f only"
assert_allowed check-rm.sh "trash /tmp/test" "trash command"

# --- check-git-push.sh ---

assert_blocked check-git-push.sh "git push origin main" "push to main"
assert_blocked check-git-push.sh "git push origin master" "push to master"
assert_blocked check-git-push.sh "git push -u origin main" "push -u to main"
assert_allowed check-git-push.sh "git push origin feature/foo" "push to feature branch"
assert_allowed check-git-push.sh "git push -u origin feature/bar" "push -u to feature branch"
assert_allowed check-git-push.sh "git status" "git status"

# --- check-gh.sh (allowed commands) ---

assert_allowed check-gh.sh "gh pr create --title test" "pr create"
assert_allowed check-gh.sh "gh pr edit 123 --title new" "pr edit"
assert_allowed check-gh.sh "gh pr view 123" "pr view"
assert_allowed check-gh.sh "gh pr list" "pr list"
assert_allowed check-gh.sh "gh pr diff 123" "pr diff"
assert_allowed check-gh.sh "gh pr checks 123" "pr checks"
assert_allowed check-gh.sh "gh pr comment 123 --body note" "pr comment"
assert_allowed check-gh.sh "gh pr ready 123" "pr ready"
assert_allowed check-gh.sh "gh pr status" "pr status"
assert_allowed check-gh.sh "gh issue view 42" "issue view"
assert_allowed check-gh.sh "gh issue list" "issue list"
assert_allowed check-gh.sh "gh issue create --title bug" "issue create"
assert_allowed check-gh.sh "gh issue comment 42 --body note" "issue comment"
assert_allowed check-gh.sh "gh repo view" "repo view"
assert_allowed check-gh.sh "gh api repos/foo/bar/pulls/1/comments" "api GET (default)"
assert_allowed check-gh.sh "git log --oneline" "non-gh command"
assert_allowed check-gh.sh "ls -la" "unrelated command"

# --- check-gh.sh (blocked commands) ---

assert_blocked check-gh.sh "gh pr merge 123" "pr merge"
assert_blocked check-gh.sh "gh pr close 42" "pr close"
assert_blocked check-gh.sh "gh pr review --approve 123" "pr review approve"
assert_blocked check-gh.sh "gh repo delete foo/bar" "repo delete"
assert_blocked check-gh.sh "gh repo create foo" "repo create"
assert_blocked check-gh.sh "gh release create v1.0" "release create"
assert_blocked check-gh.sh "gh auth login" "auth login"
assert_blocked check-gh.sh "gh issue close 42" "issue close"
assert_blocked check-gh.sh "gh issue delete 42" "issue delete"
assert_blocked check-gh.sh "gh api -X DELETE repos/foo/bar/issues/1" "api DELETE"
assert_blocked check-gh.sh "gh api -X POST repos/foo/bar/merges" "api POST"
assert_blocked check-gh.sh "gh api --method PUT repos/foo/bar" "api PUT"
assert_blocked check-gh.sh "gh api --method PATCH repos/foo/bar" "api PATCH"

# --- check-publish.sh ---

assert_blocked check-publish.sh "npm publish" "npm publish"
assert_blocked check-publish.sh "pnpm publish" "pnpm publish"
assert_blocked check-publish.sh "yarn publish" "yarn publish"
assert_allowed check-publish.sh "npm install" "npm install"
assert_allowed check-publish.sh "pnpm add lodash" "pnpm add"

# --- check-docker-push.sh ---

assert_blocked check-docker-push.sh "docker push myimage:latest" "docker push"
assert_blocked check-docker-push.sh "docker push registry.io/app:v1" "docker push to registry"
assert_allowed check-docker-push.sh "docker build -t app ." "docker build"
assert_allowed check-docker-push.sh "docker pull nginx" "docker pull"
assert_allowed check-docker-push.sh "docker run -d nginx" "docker run"

echo ""
echo "Results: $PASS passed, $FAIL failed ($((PASS + FAIL)) total)"
if ((FAIL > 0)); then
	exit 1
fi
