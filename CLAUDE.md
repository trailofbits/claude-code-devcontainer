# Development Standards

These instructions apply to all projects worked on inside this devcontainer.

## Philosophy

- **No speculative features** - Don't add "might be useful" functionality
- **No premature abstraction** - Don't create utilities until you've written the same code three times
- **Clarity over cleverness** - Prefer explicit, readable code over dense one-liners; reduce nesting with early returns
- **Justify new dependencies** - Each dependency is attack surface and maintenance burden
- **No unnecessary configuration** - Don't add flags unless users actively need them
- **No phantom features** - Don't document or validate features that aren't implemented

## Code Quality

### Hard Limits

1. ≤100 lines/function, cyclomatic complexity ≤8
2. ≤5 positional params, ≤12 branches, ≤6 returns
3. 100-char line length
4. Ban relative (`..`) imports
5. Google-style docstrings on non-trivial public APIs
6. All code must pass type checking—no `type: ignore` without justification

### Comments

Code should be self-documenting. If you need a comment to explain WHAT the code does, refactor.

- No comments that repeat what code does
- No commented-out code (delete it)
- No obvious comments ("increment counter")
- No comments instead of good naming

### Error Handling

- Fail fast with clear, actionable messages
- Never swallow exceptions silently
- Include context (what operation, what input, suggested fix)

### When Uncertain

- State your assumption and proceed for small decisions
- Ask before changes with significant unintended consequences

## Preferred Tools

| Tool | Purpose | Example |
|------|---------|---------|
| `rg` (ripgrep) | Fast regex search | `rg "pattern"` |
| `fd` | Fast file finder | `fd "*.py"` |
| `fzf` | Fuzzy finder with shell integration | `Ctrl+T` for files |
| `delta` | Better git diffs | Configured automatically |
| `ast-grep` / `sg` | AST-based code search/rewrite | `sg --pattern '$FUNC($$$)' --lang py` |
| `uv` | Python package manager | `uv pip install pkg` |
| `jq` | JSON processor | `jq '.key' file.json` |
| `tmux` | Terminal multiplexer | `tmux new -s dev` |

### ast-grep Examples

```bash
# Find function calls
sg --pattern 'print($$$)' --lang py

# Find class definitions
sg --pattern 'class $NAME: $$$' --lang py

# Find async functions
sg --pattern 'async def $F($$$): $$$' --lang py

# $NAME = identifier, $$$ = any code
# Languages: py, js, ts, rust, go, java, c, cpp
```

## Development

### Python

**Runtime:** Python 3.13 via `uv`

```bash
uv venv                   # Create virtual environment
uv pip install pkg        # Install packages
uv run script.py          # Run with project dependencies
uv run ruff check --fix   # Lint and fix
uv run pytest -q          # Run tests
```

### Node.js

**Runtime:** Node 22 LTS

```bash
npm install / pnpm install
npm test
```

### Bash

All scripts must start with:
```bash
#!/bin/bash
set -euo pipefail
```

## Git Workflow

- Commit messages: imperative mood, ≤72 char subject line
- One logical change per commit
- Never amend/rebase commits already pushed to shared branches
- Never push directly to main—use feature branches and PRs

## Security

### Secrets

- Never commit secrets, API keys, or credentials
- Use `.env` files (gitignored) for local dev
- Reference secrets via environment variables

### Version Verification

When adding dependencies, CI actions, or tool versions:
1. **Always web search** for the current stable version
2. Training data versions are stale—never assume from memory
3. Exception: Skip if user explicitly provides the version

### Python Supply Chain

```bash
pip-audit                           # Check for vulnerabilities
uv pip install --require-hashes     # Verify package integrity
```

Pin exact versions in production (`==` not `>=`).

### Node Supply Chain

```bash
npm audit                 # Check for vulnerabilities
```

Pin exact versions (no `^` or `~`) in production.

## Testing

**Mock boundaries, not logic.** Only mock things that are:
- Slow (network, filesystem)
- Non-deterministic (time, randomness)
- External services you don't control

**Verify tests catch failures:**
1. Write the test for the bug/behavior you're preventing
2. Temporarily break the code to verify the test fails
3. Fix and verify it passes

### Conventions

- Python: `tests/` directory mirroring package structure
- Node/TS: colocated `*.test.ts` files

## Devcontainer Notes

- **`.devcontainer/` is infrastructure**—ignore for code reviews
- **Environment is sandboxed** with bypassPermissions enabled
- **Persists across rebuilds:** command history, Claude config, gh auth
