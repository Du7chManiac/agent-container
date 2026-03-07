#!/bin/bash
set -euo pipefail

# ==============================================================================
# Logging Helpers
# ==============================================================================
log_info()  { echo "[INFO]  $*"; }
log_warn()  { echo "[WARN]  $*" >&2; }
log_error() { echo "[ERROR] $*" >&2; }

# ==============================================================================
# Cleanup Trap
# ==============================================================================
cleanup() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        log_error "Entrypoint exited with code $exit_code"
    fi
    # Stop background sshd if running
    if [ -n "${SSHD_PID:-}" ] && kill -0 "$SSHD_PID" 2>/dev/null; then
        log_info "Stopping background SSH server (PID $SSHD_PID)..."
        kill "$SSHD_PID" 2>/dev/null || true
    fi
}
trap cleanup EXIT

# ==============================================================================
# Environment Variable Validation
# ==============================================================================
validate_env() {
    local errors=0

    # Validate OPENCODE_MODE
    if [ -n "${OPENCODE_MODE:-}" ]; then
        case "$OPENCODE_MODE" in
            ssh|web|serve) ;;
            *)
                log_error "Invalid OPENCODE_MODE='$OPENCODE_MODE'. Must be one of: ssh, web, serve"
                errors=$((errors + 1))
                ;;
        esac
    fi

    # Validate OPENCODE_PORT is a valid port number
    if [ -n "${OPENCODE_PORT:-}" ]; then
        if ! echo "$OPENCODE_PORT" | grep -qE '^[0-9]+$' || \
           [ "$OPENCODE_PORT" -lt 1 ] || [ "$OPENCODE_PORT" -gt 65535 ]; then
            log_error "Invalid OPENCODE_PORT='$OPENCODE_PORT'. Must be a number between 1 and 65535"
            errors=$((errors + 1))
        fi
    fi

    # Validate TZ if set
    if [ -n "${TZ:-}" ] && [ ! -f "/usr/share/zoneinfo/$TZ" ]; then
        log_error "Invalid timezone TZ='$TZ'. File /usr/share/zoneinfo/$TZ not found"
        errors=$((errors + 1))
    fi

    # Validate GIT_REPO_URL format if set
    if [ -n "${GIT_REPO_URL:-}" ]; then
        if ! echo "$GIT_REPO_URL" | grep -qE '^(https?://|git@|ssh://)'; then
            log_warn "GIT_REPO_URL='$GIT_REPO_URL' doesn't look like a valid git URL"
        fi
    fi

    # Validate Gitea config: both URL and token must be set together
    if { [ -n "${GITEA_URL:-}" ] && [ -z "${GITEA_TOKEN:-}" ]; } || \
       { [ -z "${GITEA_URL:-}" ] && [ -n "${GITEA_TOKEN:-}" ]; }; then
        log_error "GITEA_URL and GITEA_TOKEN must both be set (or both empty)"
        errors=$((errors + 1))
    fi

    # Validate OPENCODE_CONFIG_JSON is valid JSON if set
    if [ -n "${OPENCODE_CONFIG_JSON:-}" ]; then
        if ! echo "$OPENCODE_CONFIG_JSON" | jq empty 2>/dev/null; then
            log_error "OPENCODE_CONFIG_JSON is not valid JSON"
            errors=$((errors + 1))
        fi
    fi

    # Warn if no auth method configured
    if [ -z "${SSH_PUBLIC_KEY:-}" ] && [ -z "${SSH_PASSWORD:-}" ]; then
        log_warn "No SSH_PUBLIC_KEY or SSH_PASSWORD set. A random password will be generated."
    fi

    if [ $errors -gt 0 ]; then
        log_error "Found $errors configuration error(s). Aborting startup."
        exit 1
    fi

    log_info "Environment validation passed."
}

validate_env

# ==============================================================================
# First-boot Home Directory Initialization
# ==============================================================================
if [ ! -f /home/coder/.initialized ]; then
    cp -rn /etc/skel.coder/. /home/coder/
    touch /home/coder/.initialized
    chown -R coder:coder /home/coder
    log_info "Initialized home directory from skeleton."
fi

# ==============================================================================
# Timezone
# ==============================================================================
if [ -n "${TZ:-}" ]; then
    ln -snf "/usr/share/zoneinfo/$TZ" /etc/localtime
    echo "$TZ" > /etc/timezone
    log_info "Timezone set to $TZ."
fi

# ==============================================================================
# SSH Host Key Persistence
# ==============================================================================
HOST_KEY_DIR="/etc/ssh/host_keys"
mkdir -p "$HOST_KEY_DIR"

if [ -f "$HOST_KEY_DIR/ssh_host_ed25519_key" ]; then
    cp "$HOST_KEY_DIR"/ssh_host_* /etc/ssh/
    log_info "Restored persisted SSH host keys."
else
    ssh-keygen -A
    cp /etc/ssh/ssh_host_* "$HOST_KEY_DIR/"
    log_info "Generated and persisted new SSH host keys."
fi

# ==============================================================================
# SSH Configuration
# ==============================================================================
sed -i 's/#PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/#PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config

# Smart password auth: disable when key is provided without password
if [ -n "${SSH_PUBLIC_KEY:-}" ] && [ -z "${SSH_PASSWORD:-}" ]; then
    sed -i 's/#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
    log_info "Password authentication disabled (key-only mode)."
else
    sed -i 's/#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
fi

# SSH public key auth
if [ -n "${SSH_PUBLIC_KEY:-}" ]; then
    mkdir -p /home/coder/.ssh
    echo "$SSH_PUBLIC_KEY" > /home/coder/.ssh/authorized_keys
    chmod 700 /home/coder/.ssh
    chmod 600 /home/coder/.ssh/authorized_keys
    chown -R coder:coder /home/coder/.ssh
    log_info "SSH public key configured."
fi

# SSH password auth
if [ -n "${SSH_PASSWORD:-}" ]; then
    echo "coder:$SSH_PASSWORD" | chpasswd
    log_info "SSH password configured for user 'coder'."
elif [ -z "${SSH_PUBLIC_KEY:-}" ]; then
    GENERATED_PW=$(openssl rand -base64 16)
    echo "coder:$GENERATED_PW" | chpasswd
    log_warn "No SSH_PUBLIC_KEY or SSH_PASSWORD set."
    log_warn "Generated password for 'coder': $GENERATED_PW"
fi

# ==============================================================================
# OpenCode Auto-Update
# ==============================================================================
OPENCODE_AUTO_UPDATE="${OPENCODE_AUTO_UPDATE:-false}"
OPENCODE_BIN="/home/coder/.local/bin/opencode"

update_opencode() {
    log_info "Checking for OpenCode updates..."

    # Get current version (handle missing binary gracefully)
    local current_version=""
    if [ -x "$OPENCODE_BIN" ]; then
        current_version=$(su - coder -c "opencode --version" 2>/dev/null || echo "unknown")
    fi
    log_info "Current OpenCode version: ${current_version:-not installed}"

    # Download latest version
    if su - coder -c "curl -fsSL https://opencode.ai/install | bash" 2>/dev/null; then
        local new_version=""
        if [ -x "$OPENCODE_BIN" ]; then
            new_version=$(su - coder -c "opencode --version" 2>/dev/null || echo "unknown")
        fi

        if [ "$current_version" != "$new_version" ]; then
            log_info "OpenCode updated: ${current_version} -> ${new_version}"
            # Update skeleton so new containers also get the latest
            cp -a "$OPENCODE_BIN" /etc/skel.coder/.local/bin/opencode 2>/dev/null || true
        else
            log_info "OpenCode is already up to date (${new_version})."
        fi
    else
        log_warn "OpenCode update failed. Continuing with current version."
    fi
}

if [ "$OPENCODE_AUTO_UPDATE" = "true" ] || [ "$OPENCODE_AUTO_UPDATE" = "1" ]; then
    update_opencode
fi

# ==============================================================================
# OpenCode Config
# ==============================================================================
OPENCODE_CONFIG_DIR="/home/coder/.config/opencode"
OPENCODE_CONFIG_FILE="${OPENCODE_CONFIG_DIR}/opencode.json"

if [ ! -f "$OPENCODE_CONFIG_FILE" ]; then
    mkdir -p "$OPENCODE_CONFIG_DIR"
    cat > "$OPENCODE_CONFIG_FILE" <<'EOCFG'
{
  "$schema": "https://opencode.ai/config.json",
  "permission": {
    "*": "allow"
  }
}
EOCFG
    chown -R coder:coder "$OPENCODE_CONFIG_DIR"
    log_info "Default opencode config created with full permissions."
fi

# Override config from env var if provided
if [ -n "${OPENCODE_CONFIG_JSON:-}" ]; then
    echo "$OPENCODE_CONFIG_JSON" > "$OPENCODE_CONFIG_FILE"
    chown coder:coder "$OPENCODE_CONFIG_FILE"
    log_info "OpenCode config overridden from OPENCODE_CONFIG_JSON env var."
fi

# ==============================================================================
# Gitea MCP Server
# ==============================================================================
if [ -n "${GITEA_URL:-}" ] && [ -n "${GITEA_TOKEN:-}" ]; then
    GITEA_MCP_CONFIG=$(jq -n \
        --arg host "$GITEA_URL" \
        --arg token "$GITEA_TOKEN" \
        '{
            "type": "local",
            "command": ["gitea-mcp", "-t", "stdio"],
            "enabled": true,
            "environment": {
                "GITEA_HOST": $host,
                "GITEA_ACCESS_TOKEN": $token
            }
        }')

    jq --argjson gitea "$GITEA_MCP_CONFIG" '.mcp.gitea = $gitea' \
        "$OPENCODE_CONFIG_FILE" > "${OPENCODE_CONFIG_FILE}.tmp" \
        && mv "${OPENCODE_CONFIG_FILE}.tmp" "$OPENCODE_CONFIG_FILE"
    chown coder:coder "$OPENCODE_CONFIG_FILE"
    log_info "Gitea MCP server configured for $GITEA_URL."
fi

# Ensure directories exist and are owned by coder
mkdir -p /home/coder/.local/share/opencode
chown -R coder:coder /home/coder/.local/share/opencode
chown -R coder:coder /home/coder/.config

# ==============================================================================
# Git Repo Cloning
# ==============================================================================
if [ -n "${GIT_REPO_URL:-}" ]; then
    CLONE_DIR="/home/coder/workspace/$(basename "$GIT_REPO_URL" .git)"
    if [ ! -d "$CLONE_DIR" ]; then
        BRANCH_FLAG=""
        if [ -n "${GIT_BRANCH:-}" ]; then
            BRANCH_FLAG="--branch $GIT_BRANCH"
        fi
        log_info "Cloning $GIT_REPO_URL into $CLONE_DIR..."
        if su - coder -c "git clone $BRANCH_FLAG '$GIT_REPO_URL' '$CLONE_DIR'"; then
            log_info "Repository cloned successfully."
        else
            log_error "Failed to clone repository from $GIT_REPO_URL"
            log_warn "Continuing without repository — check your GIT_REPO_URL and network."
        fi
    else
        log_info "Repository already exists at $CLONE_DIR, skipping clone."
    fi
fi

# ==============================================================================
# Git Config
# ==============================================================================
if [ -n "${GIT_USER_NAME:-}" ]; then
    su - coder -c "git config --global user.name '$GIT_USER_NAME'"
fi
if [ -n "${GIT_USER_EMAIL:-}" ]; then
    su - coder -c "git config --global user.email '$GIT_USER_EMAIL'"
fi

# ==============================================================================
# Start Services
# ==============================================================================
OPENCODE_MODE="${OPENCODE_MODE:-ssh}"
OPENCODE_PORT="${OPENCODE_PORT:-4096}"

case "$OPENCODE_MODE" in
    web)
        log_info "Starting SSH server in background..."
        /usr/sbin/sshd -e
        SSHD_PID=$!
        log_info "Starting opencode web UI on port $OPENCODE_PORT..."
        exec su - coder -c "opencode web --port $OPENCODE_PORT --hostname 0.0.0.0"
        ;;
    serve)
        log_info "Starting SSH server in background..."
        /usr/sbin/sshd -e
        SSHD_PID=$!
        log_info "Starting opencode server on port $OPENCODE_PORT..."
        exec su - coder -c "opencode serve --port $OPENCODE_PORT --hostname 0.0.0.0"
        ;;
    ssh|*)
        log_info "Starting SSH server on port 22..."
        exec /usr/sbin/sshd -D -e
        ;;
esac
