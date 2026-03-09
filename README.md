# OpenCode Docker Container for Dokploy

A Docker container running [opencode](https://opencode.ai) — an open-source AI coding agent with a terminal UI — accessible via browser, remote TUI client, or SSH. Designed for 24/7 deployment on [Dokploy](https://dokploy.com) (self-hosted PaaS) or any Docker host.

## Quick Start

For Dokploy deployment, see [Dokploy Deployment](#dokploy-deployment).

For standalone Docker usage:

```bash
# 1. Clone this repo
git clone https://github.com/Du7chManiac/agent-container.git
cd agent-container

# 2. Create the external network
docker network create dokploy-network

# 3. Start the container
docker compose up -d

# 4. Access via browser or remote TUI
# Browser (web mode): http://localhost:4096
# Remote TUI (serve mode): opencode attach http://localhost:4096
```

> **Note:** When running standalone, you may need to add `ports` back to `docker-compose.yml` or use `docker exec` to access the container. See `env.example` for all configurable environment variables.

## Access Modes

The container supports three access modes, controlled by the `OPENCODE_MODE` environment variable:

### Serve Mode (default)

```bash
OPENCODE_MODE=serve
```

Starts a headless HTTP API server (REST + SSE). This allows:

- **Remote TUI** — Connect a local opencode terminal client to the remote server:
  ```bash
  opencode attach https://your-domain.example.com
  ```
- **Multiple clients** — Several browsers or TUI clients can connect simultaneously to the same server, sharing session state
- **API access** — Full REST API with OpenAPI 3.1 spec available at `/doc`

### Web Mode

```bash
OPENCODE_MODE=web
```

Starts the opencode web UI — a full browser-based interface for interacting with the AI agent. Access it at:

```
https://your-domain.example.com
```

### SSH Mode (advanced)

```bash
OPENCODE_MODE=ssh
```

Traditional SSH access — connect via SSH and run `opencode` interactively. See [SSH Access](#ssh-access) for setup details.

### Authentication for Web/Serve Modes

Protect your web/serve endpoint with HTTP Basic Auth:

```bash
OPENCODE_SERVER_PASSWORD=your-secure-password
OPENCODE_SERVER_USERNAME=opencode   # optional, defaults to "opencode"
```

These env vars are read directly by opencode. When set, browsers will show a native login dialog.

> **Known limitation:** The `opencode attach` CLI does not currently support password authentication. Setting `OPENCODE_SERVER_PASSWORD` on the client side or passing `-p` has no effect — the CLI does not send credentials as HTTP Basic Auth headers. This is tracked upstream in [opencode#8458](https://github.com/anomalyco/opencode/issues/8458) and in [#14](https://github.com/Du7chManiac/agent-container/issues/14). If you need remote TUI access, either disable password protection and rely on network-level security (e.g., Tailscale VPN), or use **web mode** where the browser handles Basic Auth natively.

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

2. **Set environment variables** in Dokploy's **Environment** tab:
   - `OPENCODE_SERVER_PASSWORD` — secure your web/serve endpoint
   - Any API keys you need (see [Environment Variables](#environment-variables))
   - For `OPENCODE_CONFIG_JSON`, paste the JSON as a single line

3. **Configure domain** — In Dokploy's **Domains** settings:
   - Add a domain (e.g., `opencode.example.com`)
   - Set the container port to `4096` (or your custom `OPENCODE_PORT`)
   - Traefik handles SSL termination and HTTP routing automatically

4. **Deploy** the service

5. **Connect**:
   ```bash
   # Browser (web mode)
   https://opencode.example.com

   # Remote TUI (serve mode — default)
   opencode attach https://opencode.example.com
   ```

### Optional: Enable SSH Access

For Dokploy, add a TCP port mapping in the **Ports** settings (e.g., host `2222` → container `22`). See [SSH Access](#ssh-access) for full setup.

### Network Note

The `docker-compose.yml` references `dokploy-network` as an external network. This network is automatically created by Dokploy. If running standalone without Dokploy, either:
- Create it manually: `docker network create dokploy-network`
- Or remove the `networks` section from `docker-compose.yml`

## Authentication with OpenCode Go

[OpenCode Go](https://opencode.ai) ($10/month) provides access to multiple AI models without needing individual API keys.

1. Access the container (via web UI, remote TUI, or SSH)

2. Start opencode (if using SSH):
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

SSH is disabled by default. There are two ways to enable it:

- **SSH-only mode**: Set `OPENCODE_MODE=ssh` — SSH runs as the foreground process (no web/serve)
- **SSH alongside serve/web**: Set `SSH_ENABLED=true` — starts SSH in the background alongside the primary mode

The default SSH port mapping is `2222` on the host (configurable via `SSH_PORT`). Connect with:

```bash
ssh coder@your-server -p 2222
```

### Key-based Authentication (Recommended)

Set `SSH_PUBLIC_KEY` to the contents of your public key:

```bash
SSH_PUBLIC_KEY="ssh-ed25519 AAAAC3... user@machine"
```

When only a key is provided (no `SSH_PASSWORD`), password authentication is automatically disabled for improved security.

Then connect:
```bash
ssh coder@your-server -p 2222
```

### Password Authentication

Set `SSH_PASSWORD`:

```bash
SSH_PASSWORD=your-secure-password
```

### Both Key and Password

If both `SSH_PUBLIC_KEY` and `SSH_PASSWORD` are set, both authentication methods are enabled.

### No Credentials Set

If SSH is enabled but neither `SSH_PUBLIC_KEY` nor `SSH_PASSWORD` is configured, the entrypoint generates a random password and prints it to the container logs. Check with:

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

Access the container and clone repos into `~/workspace/`:

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

## OpenCode Config

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

The config file is persisted in the `coder-home` volume. Access the container and edit it:

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
| **Go** | 1.26.1 | Official binary |
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

The container includes a Docker HEALTHCHECK that adapts to the active mode:
- **serve/web**: Checks the HTTP endpoint on the configured port
- **ssh**: Verifies the SSH daemon is accepting connections

Docker and Dokploy will report the container as `healthy` once the primary service is ready.

## Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `OPENCODE_MODE` | No | `serve` | Access mode: `serve`, `web`, or `ssh` |
| `OPENCODE_PORT` | No | `4096` | Port for web/serve modes |
| `OPENCODE_AUTO_UPDATE` | No | `false` | Set to `true` to update OpenCode on startup |
| `OPENCODE_SERVER_PASSWORD` | No | — | HTTP Basic Auth password for web/serve |
| `OPENCODE_SERVER_USERNAME` | No | `opencode` | HTTP Basic Auth username for web/serve |
| `SSH_ENABLED` | No | `false` | Start SSH in background for serve/web modes |
| `SSH_PUBLIC_KEY` | No | — | SSH public key for key-based auth |
| `SSH_PASSWORD` | No | — | Password for SSH password auth |
| `TZ` | No | `UTC` | Timezone (e.g., `America/New_York`) |
| `GIT_REPO_URL` | No | — | Repository URL to clone on startup |
| `GIT_BRANCH` | No | — | Branch to checkout (default: repo default) |
| `GIT_USER_NAME` | No | — | Git commit author name |
| `GIT_USER_EMAIL` | No | — | Git commit author email |
| `OPENCODE_CONFIG_JSON` | No | — | Full opencode config JSON (overrides default) |
| `ANTHROPIC_API_KEY` | No | — | Anthropic API key |
| `OPENAI_API_KEY` | No | — | OpenAI API key |
| `GOOGLE_API_KEY` | No | — | Google Gemini API key |
| `OPENROUTER_API_KEY` | No | — | OpenRouter API key |
| `GROQ_API_KEY` | No | — | Groq API key |
| `GITHUB_TOKEN` | No | — | GitHub PAT for `gh` CLI |
| `GITEA_URL` | No | — | Gitea instance URL |
| `GITEA_TOKEN` | No | — | Gitea personal access token |
| `SSH_PORT` | No | `2222` | Host port mapped to container SSH port 22 |

> **Note:** Environment variables matching `AWS_*` and `AZURE_*` patterns are also automatically forwarded into the container.

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
- `SSH_ENABLED` must be `true` or `false` if set
- `TZ` must be a valid timezone from the tz database
- `GITEA_URL` and `GITEA_TOKEN` must both be set or both empty
- `OPENCODE_CONFIG_JSON` must be valid JSON if set
- `GIT_REPO_URL` format is checked (warning only)
- A warning is shown if SSH is enabled but no authentication method is configured

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
  test_validate_env.bats    # Tests for all env validation paths (~33 tests)
```

### CI

GitHub Actions runs on every push to `main` and on all pull requests:
- **lint** — shellcheck on `entrypoint.sh`
- **unit-tests** — all bats test suites
- **docker-build** — Docker image build smoke test

## Troubleshooting

### Web UI / Serve mode not accessible

- Verify the container is running: `docker compose ps`
- Check container logs: `docker compose logs opencode`
- On Dokploy, confirm a domain is configured pointing to the container's port 4096
- If auth is enabled, ensure `OPENCODE_SERVER_PASSWORD` is set correctly

### Cannot attach remote TUI

- The default mode is `serve` — verify the container is running
- Ensure the port/domain is reachable from your local machine
- **If password auth is enabled**, `opencode attach` will fail with `404 page not found`. The CLI does not support sending Basic Auth credentials yet ([upstream issue](https://github.com/anomalyco/opencode/issues/8458)). Workaround: disable `OPENCODE_SERVER_PASSWORD` and use network-level access control (e.g., Tailscale), or switch to web mode

### Cannot connect via SSH

- SSH is disabled by default. Ensure `OPENCODE_MODE=ssh` or `SSH_ENABLED=true` is set
- On Dokploy, confirm a TCP port mapping (e.g., 2222 → 22) is configured in the Ports settings
- Check container logs: `docker compose logs opencode`
- Ensure your firewall allows the SSH port

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

- The binary should be at `~/.opencode/bin/opencode`. Check with: `ls -la ~/.opencode/bin/`
- If missing, reinstall: `curl -fsSL https://opencode.ai/install | bash`

### Container exits immediately

- Check logs: `docker compose logs opencode`
- Common cause: opencode binary missing or corrupt. Try setting `OPENCODE_AUTO_UPDATE=true`

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

See [Network Note](#network-note) under Dokploy Deployment.
