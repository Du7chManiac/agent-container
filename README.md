# OpenCode Docker Container for Dokploy

A Docker container running [opencode](https://opencode.ai) — an open-source AI coding agent with a terminal UI — accessible via SSH, web browser, or remote TUI client. Designed for 24/7 deployment on [Dokploy](https://dokploy.com) (self-hosted PaaS) or any Docker host.

## Quick Start

```bash
# 1. Clone this repo
git clone https://github.com/Du7chManiac/agent-container.git
cd agent-container

# 2. Configure environment
cp .env.example .env
# Edit .env — at minimum set SSH_PUBLIC_KEY or SSH_PASSWORD

# 3. Start the container
docker compose up -d

# 4. SSH into the container
ssh coder@localhost -p 2222

# 5. Launch opencode
opencode
```

## Access Modes

The container supports three access modes, controlled by the `OPENCODE_MODE` environment variable:

### SSH Mode (default)

```bash
OPENCODE_MODE=ssh
```

Traditional SSH access. Connect via SSH and run `opencode` interactively in your terminal. SSH is always available in all modes.

### Web Mode

```bash
OPENCODE_MODE=web
```

Starts the opencode web UI — a full browser-based interface for interacting with the AI agent. Access it at:

```
http://your-server-ip:4096
```

SSH remains available in the background for troubleshooting.

### Serve Mode

```bash
OPENCODE_MODE=serve
```

Starts a headless HTTP API server (REST + SSE). This allows:

- **Remote TUI** — Connect a local opencode terminal client to the remote server:
  ```bash
  opencode attach http://your-server-ip:4096
  ```
- **Multiple clients** — Several browsers or TUI clients can connect simultaneously to the same server, sharing session state
- **API access** — Full REST API with OpenAPI 3.1 spec available at `/doc`

SSH remains available in the background.

### Authentication for Web/Serve Modes

Protect your web/serve endpoint with HTTP Basic Auth:

```bash
OPENCODE_SERVER_PASSWORD=your-secure-password
OPENCODE_SERVER_USERNAME=opencode   # optional, defaults to "opencode"
```

These env vars are read directly by opencode. When set, browsers will show a native login dialog and `opencode attach` clients should set `OPENCODE_SERVER_PASSWORD` locally.

### Port Configuration

The web/serve port defaults to `4096`. Change it with:

```bash
OPENCODE_PORT=8080
```

## Dokploy Deployment

### Step-by-step

1. **Create a Compose service** in Dokploy:
   - Go to your Dokploy dashboard
   - Create a new **Compose** project
   - Point it to this repository (or paste the `docker-compose.yml` contents)

2. **Set environment variables** in Dokploy's Environment tab:
   - `SSH_PUBLIC_KEY` — your public key for SSH access
   - `SSH_PORT` — the host port for SSH (default: `2222`)
   - `OPENCODE_MODE` — set to `web` or `serve` for browser/remote access
   - Any API keys you need (see [Environment Variables](#environment-variables))

3. **Expose ports**:
   - SSH port (default `2222`) — TCP port, cannot go through Traefik
   - OpenCode port (default `4096`) — HTTP port, can be proxied through Traefik for web/serve modes

4. **Deploy** the service

5. **Connect**:
   ```bash
   # SSH
   ssh coder@your-server-ip -p 2222

   # Browser (web mode)
   open http://your-server-ip:4096

   # Remote TUI (serve mode)
   opencode attach http://your-server-ip:4096
   ```

### Network Note

The `docker-compose.yml` references `dokploy-network` as an external network. This network is automatically created by Dokploy. If running standalone without Dokploy, either:
- Create it manually: `docker network create dokploy-network`
- Or remove the `networks` section from `docker-compose.yml`

## Authentication with OpenCode Go

[OpenCode Go](https://opencode.ai) ($10/month) provides access to multiple AI models without needing individual API keys.

1. SSH into the container:
   ```bash
   ssh coder@your-server -p 2222
   ```

2. Start opencode:
   ```bash
   opencode
   ```

3. Run the `/connect` command in the opencode TUI

4. Select **OpenCode Go** as the provider

5. A URL will be displayed — open it in your local browser, complete the authentication, and paste the resulting key back into the terminal

6. Your credentials are stored in `~/.local/share/opencode/` which is persisted via the `coder-home` Docker volume — they survive container restarts and redeployments.

## Alternative: API Keys

If you prefer using your own API keys instead of OpenCode Go, set them as environment variables:

```bash
# In your .env file
ANTHROPIC_API_KEY=sk-ant-...
OPENAI_API_KEY=sk-...
GOOGLE_API_KEY=AI...
```

These are passed into the container and opencode will detect them automatically.

## SSH Access

### Key-based Authentication (Recommended)

Set `SSH_PUBLIC_KEY` in your `.env` to the contents of your public key:

```bash
SSH_PUBLIC_KEY="ssh-ed25519 AAAAC3... user@machine"
```

When only a key is provided (no `SSH_PASSWORD`), password authentication is automatically disabled for improved security.

Then connect:
```bash
ssh coder@your-server -p 2222
```

### Password Authentication

Set `SSH_PASSWORD` in your `.env`:

```bash
SSH_PASSWORD=your-secure-password
```

### Both Key and Password

If both `SSH_PUBLIC_KEY` and `SSH_PASSWORD` are set, both authentication methods are enabled.

### No Credentials Set

If neither `SSH_PUBLIC_KEY` nor `SSH_PASSWORD` is configured, the entrypoint generates a random password and prints it to the container logs. Check with:

```bash
docker compose logs opencode
```

## Repository Management

### Auto-clone on Startup

Set `GIT_REPO_URL` to automatically clone a repository when the container starts:

```bash
GIT_REPO_URL=https://github.com/user/repo.git
GIT_BRANCH=main  # optional
```

The clone is idempotent — if the directory already exists (from a previous run), it is skipped.

### Manual Cloning

SSH in and clone repos into `~/workspace/`:

```bash
cd ~/workspace
git clone https://github.com/user/repo.git
```

The `~/workspace` directory is part of the `coder-home` volume and persists across restarts.

### Git Identity

Set your commit identity via environment variables:

```bash
GIT_USER_NAME="Your Name"
GIT_USER_EMAIL="you@example.com"
```

## Gitea Integration

The container includes the [official Gitea MCP server](https://gitea.com/gitea/gitea-mcp), pre-installed as a Go binary. When configured, this gives the AI agent direct access to your Gitea instance — it can manage repositories, issues, pull requests, branches, releases, and more.

### Setup

Set these environment variables:

```bash
GITEA_URL=https://gitea.example.com    # Your Gitea instance URL
GITEA_TOKEN=your-personal-access-token  # Gitea PAT with appropriate scopes
```

On startup, the entrypoint automatically injects the Gitea MCP server configuration into `opencode.json`. The AI agent will have access to Gitea tools in its next session.

### Generating a Gitea Token

1. Go to your Gitea instance → **Settings** → **Applications** → **Access Tokens**
2. Create a new token with the scopes you need (e.g., `repo`, `issue`, `admin:org`)
3. Copy the token into `GITEA_TOKEN`

### What the Agent Can Do

With the Gitea MCP server, the AI agent can:
- Create, list, and manage repositories
- Create, edit, and search issues
- Manage pull requests and code reviews
- Work with branches, tags, and releases
- Search code across repositories
- Manage organizations and teams

## Customizing OpenCode Config

### Default Config

On first start, if no config exists, the container creates `~/.config/opencode/opencode.json` with full permissions:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "permission": {
    "*": "allow"
  }
}
```

This grants opencode permission to execute all tools without prompting.

### Override via Environment Variable

Set `OPENCODE_CONFIG_JSON` to a full JSON config string to override the default:

```bash
OPENCODE_CONFIG_JSON='{"$schema":"https://opencode.ai/config.json","provider":"anthropic","model":"claude-sonnet-4-20250514","permission":{"*":"allow"}}'
```

### Edit Directly

The config file is persisted in the `coder-home` volume. SSH in and edit it:

```bash
nano ~/.config/opencode/opencode.json
```

## Timezone

By default the container runs in UTC. Set the `TZ` environment variable to use a different timezone:

```bash
TZ=America/New_York
```

This affects system logs, git commit timestamps, and all time-related operations. See [the full list of timezone names](https://en.wikipedia.org/wiki/List_of_tz_database_time_zones).

## Multi-Architecture Support

The Docker image supports both **amd64** (x86_64) and **arm64** (aarch64) architectures. The correct Go binary is automatically selected during the build based on the target platform. To build for a specific architecture:

```bash
docker buildx build --platform linux/arm64 -t opencode-agent .
```

## Included Development Tools

| Tool | Version | Notes |
|------|---------|-------|
| **Node.js** | 22.x LTS | Via NodeSource |
| **npm** | Bundled with Node.js | |
| **Python 3** | System (3.12) | With pip and venv |
| **Go** | 1.23.6 | Official binary |
| **Git** | System | |
| **GitHub CLI (gh)** | Latest | Authenticate with `GITHUB_TOKEN` env var |
| **Gitea MCP** | Latest | Official Go binary, auto-configured via env vars |
| **build-essential** | System | gcc, g++, make |
| **ripgrep (rg)** | System | Fast file search |
| **fd-find (fd)** | System | Fast file finder |
| **jq** | System | JSON processor |
| **tmux** | System | Terminal multiplexer |
| **vim / nano** | System | Text editors |
| **curl / wget** | System | HTTP clients |
| **htop** | System | Process viewer |

The `coder` user has passwordless `sudo` access, so you can install additional tools as needed:

```bash
sudo apt-get update && sudo apt-get install -y <package>
```

Note: Packages installed via `sudo` are now persisted across restarts thanks to the `coder-home` volume. However, they will not survive a full image rebuild — to make them permanent across rebuilds, add them to the `Dockerfile`.

## Volume Reference

| Volume | Container Path | Purpose |
|--------|---------------|---------|
| `coder-home` | `/home/coder` | Entire home directory — config, auth, workspace, bash history, installed tools, dotfiles |
| `ssh-host-keys` | `/etc/ssh/host_keys` | SSH host keys — prevents "host key changed" warnings after restarts |

Both volumes are Docker named volumes, which persist data across container restarts, rebuilds, and redeployments.

### First-boot Initialization

On first start (when the `coder-home` volume is empty), the entrypoint copies a skeleton directory into `/home/coder` with the opencode binary and default directory structure. Subsequent starts reuse the existing home directory contents.

### Health Check

The container includes a Docker HEALTHCHECK that verifies the SSH daemon is accepting connections. Docker and Dokploy will report the container as `healthy` once SSH is ready, and will flag it as `unhealthy` if the SSH daemon becomes unresponsive.

## Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `SSH_PUBLIC_KEY` | No* | — | SSH public key for key-based auth |
| `SSH_PASSWORD` | No* | — | Password for SSH password auth |
| `SSH_PORT` | No | `2222` | Host port mapped to container SSH |
| `TZ` | No | `UTC` | Timezone (e.g., `America/New_York`) |
| `OPENCODE_MODE` | No | `ssh` | Access mode: `ssh`, `web`, or `serve` |
| `OPENCODE_PORT` | No | `4096` | Port for web/serve modes |
| `OPENCODE_SERVER_PASSWORD` | No | — | HTTP Basic Auth password for web/serve |
| `OPENCODE_SERVER_USERNAME` | No | `opencode` | HTTP Basic Auth username for web/serve |
| `GIT_REPO_URL` | No | — | Repository URL to clone on startup |
| `GIT_BRANCH` | No | — | Branch to checkout (default: repo default) |
| `GIT_USER_NAME` | No | — | Git commit author name |
| `GIT_USER_EMAIL` | No | — | Git commit author email |
| `OPENCODE_AUTO_UPDATE` | No | `false` | Set to `true` to update OpenCode on startup |
| `OPENCODE_CONFIG_JSON` | No | — | Full opencode config JSON (overrides default) |
| `ANTHROPIC_API_KEY` | No | — | Anthropic API key |
| `OPENAI_API_KEY` | No | — | OpenAI API key |
| `GOOGLE_API_KEY` | No | — | Google Gemini API key |
| `OPENROUTER_API_KEY` | No | — | OpenRouter API key |
| `GITHUB_TOKEN` | No | — | GitHub PAT for `gh` CLI |
| `GITEA_URL` | No | — | Gitea instance URL |
| `GITEA_TOKEN` | No | — | Gitea personal access token |

\* At least one of `SSH_PUBLIC_KEY` or `SSH_PASSWORD` is recommended. If neither is set, a random password is generated and logged. When only `SSH_PUBLIC_KEY` is set, password authentication is disabled automatically.

## Auto-Update

By default, the container uses the OpenCode version that was installed when the image was built. To check for and install the latest version on every container start, set:

```bash
OPENCODE_AUTO_UPDATE=true
```

The update runs before services start. If the update fails (e.g., due to network issues), the container continues with the existing version.

## Environment Validation

On startup, the entrypoint validates all configuration before proceeding. Invalid configuration causes the container to exit immediately with clear error messages instead of failing silently later. The following checks are performed:

- `OPENCODE_MODE` must be one of `ssh`, `web`, or `serve`
- `OPENCODE_PORT` must be a number between 1 and 65535
- `TZ` must be a valid timezone from the tz database
- `GITEA_URL` and `GITEA_TOKEN` must both be set or both empty
- `OPENCODE_CONFIG_JSON` must be valid JSON if set
- `GIT_REPO_URL` format is checked (warning only)
- A warning is shown if no SSH authentication method is configured

## Development

### Prerequisites

- [shellcheck](https://www.shellcheck.net/) — static analysis for shell scripts
- [bats-core](https://github.com/bats-core/bats-core) — installed automatically by `make`

### Running Tests

```bash
# Run lint + unit tests
make test

# Run shellcheck only
make lint

# Run bats unit tests only
make test-unit

# Build Docker image (smoke test)
make build
```

### Test Structure

```
tests/
  test_helper.bash          # Shared setup: sources entrypoint functions
  test_logging.bats         # Tests for log_info, log_warn, log_error
  test_validate_env.bats    # Tests for all env validation paths (~27 tests)
```

### CI

GitHub Actions runs on every push to `main` and on all pull requests:
- **lint** — shellcheck on `entrypoint.sh`
- **unit-tests** — all bats test suites
- **docker-build** — Docker image build smoke test

## Troubleshooting

### Cannot connect via SSH

- Verify the SSH port is exposed: `docker compose ps` should show `0.0.0.0:2222->22/tcp`
- Check container logs: `docker compose logs opencode`
- Ensure your firewall allows the SSH port
- On Dokploy, confirm the port is configured in the Ports settings

### Web UI not accessible

- Verify `OPENCODE_MODE=web` is set in your `.env`
- Check the port is exposed: `docker compose ps` should show `0.0.0.0:4096->4096/tcp`
- Check container logs: `docker compose logs opencode`
- Ensure your firewall allows port 4096 (or your custom `OPENCODE_PORT`)

### Cannot attach remote TUI

- Verify `OPENCODE_MODE=serve` is set
- Ensure the port is reachable from your local machine
- If auth is enabled, set `OPENCODE_SERVER_PASSWORD` on your local machine before running `opencode attach`

### "Host key changed" warning after rebuild

If you see `WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED`, the SSH host keys were regenerated. This should not happen during normal restarts (keys are persisted in the `ssh-host-keys` volume), but can occur if:
- The `ssh-host-keys` volume was deleted
- You rebuilt with `docker compose down -v`

Fix: Remove the old host key from your local `~/.ssh/known_hosts`:
```bash
ssh-keygen -R "[localhost]:2222"
```

### Authentication credentials lost after restart

- Verify the `coder-home` volume exists: `docker volume ls | grep coder-home`
- Ensure you're not using `docker compose down -v` (the `-v` flag deletes volumes)

### opencode command not found

- The binary should be at `~/.local/bin/opencode`. Check with: `ls -la ~/.local/bin/`
- If missing, reinstall: `curl -fsSL https://opencode.ai/install | bash`

### Container exits immediately

- Check logs: `docker compose logs opencode`
- Common cause: SSH daemon fails to start. Ensure `/run/sshd` exists (it's created in the Dockerfile)

### Git clone fails on startup

- Verify `GIT_REPO_URL` is accessible from the container
- For private repos, ensure SSH keys or tokens are configured
- Check logs for specific git error messages

### Gitea MCP not working

- Verify both `GITEA_URL` and `GITEA_TOKEN` are set
- Check that the token has appropriate scopes in your Gitea instance
- Inspect the generated config: `cat ~/.config/opencode/opencode.json`
- Check container logs for "Gitea MCP server configured" message

### Dokploy network not found

If you see an error about `dokploy-network`:
- Running on Dokploy: The network should exist automatically. Try redeploying.
- Running standalone: Create it manually (`docker network create dokploy-network`) or remove the `networks` section from `docker-compose.yml`.
