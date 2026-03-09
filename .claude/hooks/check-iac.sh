#!/usr/bin/env bash
set -euo pipefail

# Block destructive infrastructure-as-code operations.
# Allows: terraform plan, terraform apply (interactive), pulumi up.
# Usage: echo '{"tool_input":{"command":"terraform destroy"}}' | ./check-iac.sh

CMD=$(jq -r '.tool_input.command' | head -1)

# Terraform destroy — block
if echo "$CMD" | grep -qE 'terraform[[:space:]]+destroy'; then
	echo 'BLOCKED: terraform destroy tears down all infrastructure' >&2
	exit 2
fi

# Terraform apply -auto-approve — block (no interactive confirmation)
if echo "$CMD" | grep -qE 'terraform[[:space:]]+apply.*-auto-approve'; then
	echo 'BLOCKED: terraform apply -auto-approve skips confirmation' >&2
	exit 2
fi

# Terraform state rm — block
if echo "$CMD" | grep -qE 'terraform[[:space:]]+state[[:space:]]+rm'; then
	echo 'BLOCKED: terraform state rm removes resources from state' >&2
	exit 2
fi

# Pulumi destroy — block
if echo "$CMD" | grep -qE 'pulumi[[:space:]]+destroy'; then
	echo 'BLOCKED: pulumi destroy tears down all infrastructure' >&2
	exit 2
fi

# CDK destroy — block
if echo "$CMD" | grep -qE 'cdk[[:space:]]+destroy'; then
	echo 'BLOCKED: cdk destroy tears down CloudFormation stacks' >&2
	exit 2
fi