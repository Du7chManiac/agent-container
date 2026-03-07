# OpenCode Docker Container for Dokploy

A Docker container running [opencode](https://opencode.ai) — an open-source AI coding agent with a terminal UI — accessible via SSH. Designed for 24/7 deployment on [Dokploy](https://dokploy.com) (self-hosted PaaS) or any Docker host.

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

## Dokploy Deployment

### Step-by-step

1. **Create a Compose service** in Dokploy:
   - Go to your Dokploy dashboard
   - Create a new **Compose** project
   - Point it to this repository (or paste the `docker-compose.yml` contents)

2. **Set environment variables** in Dokploy's Environment tab:
   - `SSH_PUBLIC_KEY` — your public key for SSH access
   - `SSH_PORT` — the host port for SSH (default: `2222`)
   - Any API keys you need (see [Environment Variables](#environment-variables))

3. **Expose the SSH port**:
   - In Dokploy's **Ports** settings, ensure the SSH port (default `2222`) is exposed
   - This is a TCP port, not HTTP — it cannot go through Traefik's HTTP proxy

4. **Deploy** the service

5. **Connect via SSH**:
   ```bash
   ssh coder@your-server-ip -p 2222
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

6. Your credentials are stored in `~/.local/share/opencode/` which is persisted via the `opencode-auth` Docker volume — they survive container restarts and redeployments.

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

Then connect:
```bash
ssh coder@your-server -p 2222
```

### Password Authentication

Set `SSH_PASSWORD` in your `.env`:

```bash
SSH_PASSWORD=your-secure-password
```

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

The `~/workspace` directory is backed by the `workspace` Docker volume and persists across restarts.

### Git Identity

Set your commit identity via environment variables:

```bash
GIT_USER_NAME="Your Name"
GIT_USER_EMAIL="you@example.com"
```

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

The config file is persisted in the `opencode-config` volume. SSH in and edit it:

```bash
nano ~/.config/opencode/opencode.json
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

Note: Packages installed via `sudo` will not persist across container restarts. To make them permanent, add them to the `Dockerfile`.

## Volume Reference

| Volume | Container Path | Purpose |
|--------|---------------|---------|
| `opencode-auth` | `/home/coder/.local/share/opencode` | OpenCode authentication credentials and session data |
| `opencode-config` | `/home/coder/.config/opencode` | OpenCode configuration (`opencode.json`) |
| `workspace` | `/home/coder/workspace` | Cloned repositories and project files |

All three volumes are Docker named volumes, which persist data across container restarts, rebuilds, and redeployments.

## Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `SSH_PUBLIC_KEY` | No* | — | SSH public key for key-based auth |
| `SSH_PASSWORD` | No* | — | Password for SSH password auth |
| `SSH_PORT` | No | `2222` | Host port mapped to container SSH |
| `GIT_REPO_URL` | No | — | Repository URL to clone on startup |
| `GIT_BRANCH` | No | — | Branch to checkout (default: repo default) |
| `GIT_USER_NAME` | No | — | Git commit author name |
| `GIT_USER_EMAIL` | No | — | Git commit author email |
| `OPENCODE_CONFIG_JSON` | No | — | Full opencode config JSON (overrides default) |
| `ANTHROPIC_API_KEY` | No | — | Anthropic API key |
| `OPENAI_API_KEY` | No | — | OpenAI API key |
| `GOOGLE_API_KEY` | No | — | Google Gemini API key |
| `OPENROUTER_API_KEY` | No | — | OpenRouter API key |
| `GITHUB_TOKEN` | No | — | GitHub PAT for `gh` CLI |

\* At least one of `SSH_PUBLIC_KEY` or `SSH_PASSWORD` is recommended. If neither is set, a random password is generated and logged.

## Troubleshooting

### Cannot connect via SSH

- Verify the SSH port is exposed: `docker compose ps` should show `0.0.0.0:2222->22/tcp`
- Check container logs: `docker compose logs opencode`
- Ensure your firewall allows the SSH port
- On Dokploy, confirm the port is configured in the Ports settings

### Authentication credentials lost after restart

- Verify the `opencode-auth` volume exists: `docker volume ls | grep opencode-auth`
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

### Dokploy network not found

If you see an error about `dokploy-network`:
- Running on Dokploy: The network should exist automatically. Try redeploying.
- Running standalone: Create it manually (`docker network create dokploy-network`) or remove the `networks` section from `docker-compose.yml`.
