#!/usr/bin/env bash
set -euo pipefail

# Block production deployment commands — must be done via CI/CD.
# Allows: netlify deploy (preview, no --prod), vercel (preview, no --prod).
# Usage: echo '{"tool_input":{"command":"vercel --prod"}}' | ./check-deploy.sh

CMD=$(jq -r '.tool_input.command' | head -1)

# Firebase deploy — block
if echo "$CMD" | grep -qE 'firebase[[:space:]]+deploy'; then
	echo 'BLOCKED: firebase deploy must be done via CI/CD' >&2
	exit 2
fi

# Vercel --prod — block
if echo "$CMD" | grep -qE 'vercel[[:space:]]+.*--prod'; then
	echo 'BLOCKED: vercel --prod must be done via CI/CD' >&2
	exit 2
fi

# Fly deploy — block
if echo "$CMD" | grep -qE 'fly[[:space:]]+deploy'; then
	echo 'BLOCKED: fly deploy must be done via CI/CD' >&2
	exit 2
fi

# Heroku container:release — block
if echo "$CMD" | grep -qE 'heroku[[:space:]]+container:release'; then
	echo 'BLOCKED: heroku container:release must be done via CI/CD' >&2
	exit 2
fi

# Netlify deploy --prod — block (preview deploys are fine)
if echo "$CMD" | grep -qE 'netlify[[:space:]]+deploy[[:space:]]+.*--prod'; then
	echo 'BLOCKED: netlify deploy --prod must be done via CI/CD' >&2
	exit 2
fi

# Wrangler deploy/publish — block
if echo "$CMD" | grep -qE 'wrangler[[:space:]]+(deploy|publish)'; then
	echo 'BLOCKED: wrangler deploy/publish must be done via CI/CD' >&2
	exit 2
fi