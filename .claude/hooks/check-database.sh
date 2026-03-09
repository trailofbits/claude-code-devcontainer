#!/usr/bin/env bash
set -euo pipefail

# Block destructive database operations — DROP, TRUNCATE, FLUSHALL, ORM resets.
# Allows: prisma db push (without --accept-data-loss), normal queries.
# Usage: echo '{"tool_input":{"command":"psql -c \"DROP TABLE users\""}}' | ./check-database.sh

CMD=$(jq -r '.tool_input.command' | head -1)

# SQL destructive statements (case-insensitive)
if echo "$CMD" | grep -qiE 'DROP[[:space:]]+(TABLE|DATABASE|SCHEMA)'; then
	echo 'BLOCKED: DROP TABLE/DATABASE/SCHEMA is irreversible' >&2
	exit 2
fi

if echo "$CMD" | grep -qiE 'TRUNCATE[[:space:]]'; then
	echo 'BLOCKED: TRUNCATE deletes all rows irreversibly' >&2
	exit 2
fi

# PostgreSQL CLI destructive commands
if echo "$CMD" | grep -qE '(dropdb|dropuser)[[:space:]]'; then
	echo 'BLOCKED: dropdb/dropuser must be done manually' >&2
	exit 2
fi

# Redis destructive commands (case-insensitive)
if echo "$CMD" | grep -qiE 'FLUSHALL|FLUSHDB'; then
	echo 'BLOCKED: FLUSHALL/FLUSHDB wipes all Redis data' >&2
	exit 2
fi

# ORM destructive flags
if echo "$CMD" | grep -qE 'prisma[[:space:]]+migrate[[:space:]]+reset'; then
	echo 'BLOCKED: prisma migrate reset drops and recreates the database' >&2
	exit 2
fi

if echo "$CMD" | grep -qE 'prisma[[:space:]]+db[[:space:]]+push.*--accept-data-loss'; then
	echo 'BLOCKED: --accept-data-loss can destroy data' >&2
	exit 2
fi

if echo "$CMD" | grep -qE 'drizzle-kit[[:space:]]+push.*--force'; then
	echo 'BLOCKED: drizzle-kit push --force skips safety checks' >&2
	exit 2
fi

if echo "$CMD" | grep -qE 'typeorm[[:space:]]+.*synchronize.*--force|typeorm[[:space:]]+schema:drop'; then
	echo 'BLOCKED: TypeORM schema:drop/force-sync destroys data' >&2
	exit 2
fi