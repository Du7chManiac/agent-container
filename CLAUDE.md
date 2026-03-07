# CLAUDE.md

## Project Overview

Docker container packaging the [OpenCode](https://opencode.ai) AI coding agent for deployment on [Dokploy](https://dokploy.com) or any Docker host. Provides SSH, web, and serve access modes.

## Key Files

- `entrypoint.sh` — Main initialization script. Validates env vars, configures SSH, sets up OpenCode config, handles auto-update, clones repos, and starts services.
- `Dockerfile` — Multi-arch Ubuntu 24.04 image with Node.js 22, Go 1.23, Python 3, GitHub CLI, and Gitea MCP.
- `docker-compose.yml` — Compose config with named volumes (`coder-home`, `ssh-host-keys`) and `dokploy-network`.
- `.env.example` — All 20 configurable environment variables with descriptions.

## Architecture

The container runs as a non-root `coder` user (UID 1000) with passwordless sudo. The entrypoint runs as root to configure SSH and system settings, then drops to `coder` for OpenCode services via `su - coder -c`.

### Entrypoint Flow

1. Validate environment variables (fails fast on errors)
2. Initialize home directory from skeleton (first boot only)
3. Configure timezone, SSH host keys, SSH auth
4. Auto-update OpenCode binary (if `OPENCODE_AUTO_UPDATE=true`)
5. Generate/override OpenCode config, configure Gitea MCP
6. Clone git repo (if `GIT_REPO_URL` set)
7. Start services based on `OPENCODE_MODE` (ssh/web/serve)

### Testing Guard

`entrypoint.sh` has a guard at line ~95 that allows tests to `source` it and access function definitions (log helpers, `validate_env`, `cleanup`) without executing side effects. Set `__SOURCED_FOR_TESTING=true` before sourcing.

## Development Commands

```bash
make test        # Run shellcheck lint + bats unit tests
make lint        # Run shellcheck only
make test-unit   # Run bats tests only
make build       # Build Docker image
```

## Test Structure

Tests use [bats-core](https://github.com/bats-core/bats-core) (auto-installed by `make`).

- `tests/test_helper.bash` — Sources entrypoint functions via the testing guard
- `tests/test_logging.bats` — 6 tests for `log_info`, `log_warn`, `log_error`
- `tests/test_validate_env.bats` — 27 tests covering all validation paths

## Shell Script Conventions

- `set -euo pipefail` for strict error handling
- All env var references use `${VAR:-}` to prevent unbound variable errors
- Logging via `log_info`, `log_warn` (stderr), `log_error` (stderr)
- `EXIT` trap handles cleanup of background processes
- All shell scripts must pass `shellcheck -s bash`

## Common Patterns

- **Adding a new env var**: Add to `.env.example`, add validation in `validate_env()` if needed, use `${VAR:-}` syntax, add to README env var table.
- **Adding a new test**: Create a `.bats` file in `tests/`, load `test_helper` in `setup()`, call `teardown_helper` in `teardown()`. Add the file to the Makefile `test-unit` target.
- **Adding a new entrypoint section**: Place between the testing guard and the "Start Services" section. Use `log_info`/`log_warn`/`log_error` for output. Use `${VAR:-}` for env var access.
