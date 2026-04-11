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
            ssh|web|serve|openchamber) ;;
            *)
                log_error "Invalid OPENCODE_MODE='$OPENCODE_MODE'. Must be one of: ssh, web, serve, openchamber"
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

    # Validate SSH_ENABLED if set
    if [ -n "${SSH_ENABLED:-}" ]; then
        case "$SSH_ENABLED" in
            true|false) ;;
            *)
                log_error "Invalid SSH_ENABLED='$SSH_ENABLED'. Must be 'true' or 'false'"
                errors=$((errors + 1))
                ;;
        esac
    fi

    # Warn if no auth method configured (only when SSH is active)
    local ssh_needed=false
    local mode="${OPENCODE_MODE:-serve}"
    if [ "$mode" = "ssh" ] || [ "${SSH_ENABLED:-false}" = "true" ]; then
        ssh_needed=true
    fi
    if [ "$ssh_needed" = "true" ] && [ -z "${SSH_PUBLIC_KEY:-}" ] && [ -z "${SSH_PASSWORD:-}" ]; then
        log_warn "No SSH_PUBLIC_KEY or SSH_PASSWORD set. A random password will be generated."
    fi

    # OpenChamber-specific warnings
    if [ "$mode" = "openchamber" ]; then
        if [ -z "${OPENCHAMBER_UI_PASSWORD:-}" ]; then
            log_warn "OPENCODE_MODE=openchamber but OPENCHAMBER_UI_PASSWORD is unset — UI will be unprotected."
        fi
        if [ -n "${OPENCODE_SERVER_PASSWORD:-}" ]; then
            log_warn "OPENCODE_SERVER_PASSWORD is ignored in openchamber mode — use OPENCHAMBER_UI_PASSWORD instead."
        fi
        if [ -n "${OPENCODE_SERVER_USERNAME:-}" ]; then
            log_warn "OPENCODE_SERVER_USERNAME is ignored in openchamber mode."
        fi
    fi

    if [ $errors -gt 0 ]; then
        log_error "Found $errors configuration error(s). Aborting startup."
        exit 1
    fi

    log_info "Environment validation passed."
}

# Guard: when sourced for testing, stop here and export only function definitions
if [[ "${__SOURCED_FOR_TESTING:-}" == "true" ]]; then
    # shellcheck disable=SC2317
    return 0 2>/dev/null || :
fi

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

# Ensure opencode binary exists (may be missing if volume predates image)
OPENCODE_BIN="/home/coder/.opencode/bin/opencode"
if [ ! -x "$OPENCODE_BIN" ]; then
    if [ -x /etc/skel.coder/.opencode/bin/opencode ]; then
        mkdir -p /home/coder/.opencode/bin
        cp -a /etc/skel.coder/.opencode/bin/opencode "$OPENCODE_BIN"
        chown coder:coder "$OPENCODE_BIN"
        log_info "Restored opencode binary from skeleton."
    else
        log_warn "OpenCode binary not found. Reinstalling..."
        if su - coder -c "curl -fsSL https://opencode.ai/install | bash"; then
            log_info "OpenCode reinstalled successfully."
        else
            log_error "Failed to install OpenCode. Container cannot start."
            exit 1
        fi
    fi
fi

# ==============================================================================
# npm Configuration (for volume-mounted homes that predate image changes)
# ==============================================================================
if [ ! -f /home/coder/.npm-initialized ]; then
    su - coder -c "npm config set fetch-timeout 300000"
    su - coder -c "npm config set fetch-retries 5"
    touch /home/coder/.npm-initialized
    chown coder:coder /home/coder/.npm-initialized
    log_info "npm configuration initialized for container environment."
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
# SSH Setup (only when SSH is needed)
# ==============================================================================
OPENCODE_MODE="${OPENCODE_MODE:-serve}"
SSH_ENABLED="${SSH_ENABLED:-false}"

# Determine if SSH is needed
SSH_NEEDED=false
if [ "$OPENCODE_MODE" = "ssh" ] || [ "$SSH_ENABLED" = "true" ]; then
    SSH_NEEDED=true
fi

if [ "$SSH_NEEDED" = "true" ]; then
    # SSH Host Key Persistence
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

    # SSH Configuration
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
else
    log_info "SSH disabled. Set OPENCODE_MODE=ssh or SSH_ENABLED=true to enable."
fi

# ==============================================================================
# OpenCode Auto-Update
# ==============================================================================
OPENCODE_AUTO_UPDATE="${OPENCODE_AUTO_UPDATE:-false}"

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
            cp -a "$OPENCODE_BIN" /etc/skel.coder/.opencode/bin/opencode 2>/dev/null || true
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
            "command": ["/usr/local/bin/gitea-mcp", "-t", "stdio"],
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
OPENCODE_PORT="${OPENCODE_PORT:-4096}"

# Forward API keys and server config to the opencode process.
# su - coder starts a login shell that auto-sources /etc/profile.d/*.sh
OPENCODE_ENV_FILE="/etc/profile.d/opencode-env.sh"
: > "$OPENCODE_ENV_FILE"
while IFS='=' read -r key val; do
    case "$key" in
        OPENCODE_SERVER_*|ANTHROPIC_*|OPENAI_*|GOOGLE_*|OPENROUTER_*|GROQ_*|GITHUB_TOKEN|AWS_*|AZURE_*)
            printf 'export %s=%q\n' "$key" "$val" >> "$OPENCODE_ENV_FILE"
            ;;
    esac
done < <(env)
chmod 644 "$OPENCODE_ENV_FILE"

if [ -s "$OPENCODE_ENV_FILE" ]; then
    log_info "Forwarded env vars: $(grep -oP '(?<=export )\w+' "$OPENCODE_ENV_FILE" | tr '\n' ' ')"
else
    log_warn "No API keys or server config env vars found to forward."
fi

case "$OPENCODE_MODE" in
    serve)
        if [ "$SSH_ENABLED" = "true" ]; then
            log_info "Starting SSH server in background..."
            /usr/sbin/sshd -e
            SSHD_PID=$!
        fi
        log_info "Starting opencode server on port $OPENCODE_PORT..."
        exec su - coder -c "$OPENCODE_BIN serve --port $OPENCODE_PORT --hostname 0.0.0.0"
        ;;
    web)
        if [ "$SSH_ENABLED" = "true" ]; then
            log_info "Starting SSH server in background..."
            /usr/sbin/sshd -e
            SSHD_PID=$!
        fi
        log_info "Starting opencode web UI on port $OPENCODE_PORT..."
        exec su - coder -c "$OPENCODE_BIN web --port $OPENCODE_PORT --hostname 0.0.0.0"
        ;;
    ssh)
        log_info "Starting SSH server on port 22..."
        exec /usr/sbin/sshd -D -e
        ;;
    openchamber)
        if [ "$SSH_ENABLED" = "true" ]; then
            log_info "Starting SSH server in background..."
            /usr/sbin/sshd -e
            SSHD_PID=$!
        fi
        log_info "Starting OpenChamber web UI on port $OPENCODE_PORT..."

        # OpenChamber spawns its own opencode subprocess. Give the subprocess
        # a different internal port so it doesn't collide with OpenChamber's
        # own --port. The subprocess port is not exposed outside the container.
        OC_INTERNAL_PORT=4097
        if [ "$OPENCODE_PORT" = "$OC_INTERNAL_PORT" ]; then
            OC_INTERNAL_PORT=4098
        fi

        # Strip OPENCODE_SERVER_{PASSWORD,USERNAME} from the forwarded env file.
        # OpenChamber rotates its own managed password for the opencode subprocess
        # (see ensureLocalOpenCodeServerPassword in @openchamber/web), so forwarding
        # a user-set OPENCODE_SERVER_PASSWORD here would be silently consumed by
        # OpenChamber — breaking the warning above that claims it's ignored. Scrub
        # them so OpenChamber's own rotation is authoritative.
        if [ -f "$OPENCODE_ENV_FILE" ]; then
            grep -vE '^export OPENCODE_SERVER_(PASSWORD|USERNAME)=' "$OPENCODE_ENV_FILE" \
                > "${OPENCODE_ENV_FILE}.tmp" && mv "${OPENCODE_ENV_FILE}.tmp" "$OPENCODE_ENV_FILE"
            chmod 644 "$OPENCODE_ENV_FILE"
        fi

        # Forward to the openchamber process and the opencode it spawns.
        # Appended to the same env file sourced by su - coder's login shell.
        # OPENCODE_BINARY points at the full opencode path so openchamber
        # doesn't need to resolve it via PATH (su - may drop user PATH additions).
        {
            printf 'export OPENCODE_PORT=%q\n' "$OC_INTERNAL_PORT"
            printf 'export OPENCHAMBER_OPENCODE_HOSTNAME=%q\n' "127.0.0.1"
            printf 'export OPENCODE_BINARY=%q\n' "$OPENCODE_BIN"
        } >> "$OPENCODE_ENV_FILE"

        # Shell-escape the password to handle special chars safely
        if [ -n "${OPENCHAMBER_UI_PASSWORD:-}" ]; then
            ESCAPED_PW=$(printf %q "$OPENCHAMBER_UI_PASSWORD")
            OPENCHAMBER_CMD="openchamber --port $OPENCODE_PORT --host 0.0.0.0 --foreground --ui-password $ESCAPED_PW"
        else
            log_warn "Starting OpenChamber without --ui-password. UI is unprotected."
            OPENCHAMBER_CMD="openchamber --port $OPENCODE_PORT --host 0.0.0.0 --foreground"
        fi

        # --foreground is mandatory: Docker PID 1 must stay alive. Without it,
        # openchamber daemonizes, su -c returns, and the container exits.
        exec su - coder -c "$OPENCHAMBER_CMD"
        ;;
esac
