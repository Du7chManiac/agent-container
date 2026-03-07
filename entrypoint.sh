#!/bin/bash
set -e

# --- First-boot Home Directory Initialization ---
if [ ! -f /home/coder/.initialized ]; then
    cp -rn /etc/skel.coder/. /home/coder/
    touch /home/coder/.initialized
    chown -R coder:coder /home/coder
    echo "Initialized home directory from skeleton."
fi

# --- Timezone ---
if [ -n "$TZ" ]; then
    ln -snf "/usr/share/zoneinfo/$TZ" /etc/localtime
    echo "$TZ" > /etc/timezone
    echo "Timezone set to $TZ."
fi

# --- SSH Host Key Persistence ---
HOST_KEY_DIR="/etc/ssh/host_keys"
mkdir -p "$HOST_KEY_DIR"

if [ -f "$HOST_KEY_DIR/ssh_host_ed25519_key" ]; then
    cp "$HOST_KEY_DIR"/ssh_host_* /etc/ssh/
    echo "Restored persisted SSH host keys."
else
    ssh-keygen -A
    cp /etc/ssh/ssh_host_* "$HOST_KEY_DIR/"
    echo "Generated and persisted new SSH host keys."
fi

# --- SSH Configuration ---
sed -i 's/#PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/#PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config

# Smart password auth: disable when key is provided without password
if [ -n "$SSH_PUBLIC_KEY" ] && [ -z "$SSH_PASSWORD" ]; then
    sed -i 's/#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
    echo "Password authentication disabled (key-only mode)."
else
    sed -i 's/#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
fi

# SSH public key auth
if [ -n "$SSH_PUBLIC_KEY" ]; then
    mkdir -p /home/coder/.ssh
    echo "$SSH_PUBLIC_KEY" > /home/coder/.ssh/authorized_keys
    chmod 700 /home/coder/.ssh
    chmod 600 /home/coder/.ssh/authorized_keys
    chown -R coder:coder /home/coder/.ssh
    echo "SSH public key configured."
fi

# SSH password auth
if [ -n "$SSH_PASSWORD" ]; then
    echo "coder:$SSH_PASSWORD" | chpasswd
    echo "SSH password configured for user 'coder'."
else
    if [ -z "$SSH_PUBLIC_KEY" ]; then
        GENERATED_PW=$(openssl rand -base64 16)
        echo "coder:$GENERATED_PW" | chpasswd
        echo "WARNING: No SSH_PUBLIC_KEY or SSH_PASSWORD set."
        echo "Generated password for 'coder': $GENERATED_PW"
    fi
fi

# --- OpenCode Config ---
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
    echo "Default opencode config created with full permissions."
fi

# Override config from env var if provided
if [ -n "$OPENCODE_CONFIG_JSON" ]; then
    echo "$OPENCODE_CONFIG_JSON" > "$OPENCODE_CONFIG_FILE"
    chown coder:coder "$OPENCODE_CONFIG_FILE"
    echo "OpenCode config overridden from OPENCODE_CONFIG_JSON env var."
fi

# Ensure directories exist and are owned by coder
mkdir -p /home/coder/.local/share/opencode
chown -R coder:coder /home/coder/.local/share/opencode
chown -R coder:coder /home/coder/.config

# --- Git Repo Cloning ---
if [ -n "$GIT_REPO_URL" ]; then
    CLONE_DIR="/home/coder/workspace/$(basename "$GIT_REPO_URL" .git)"
    if [ ! -d "$CLONE_DIR" ]; then
        BRANCH_FLAG=""
        if [ -n "$GIT_BRANCH" ]; then
            BRANCH_FLAG="--branch $GIT_BRANCH"
        fi
        echo "Cloning $GIT_REPO_URL into $CLONE_DIR..."
        su - coder -c "git clone $BRANCH_FLAG '$GIT_REPO_URL' '$CLONE_DIR'"
        echo "Repository cloned successfully."
    else
        echo "Repository already exists at $CLONE_DIR, skipping clone."
    fi
fi

# --- Git Config ---
if [ -n "$GIT_USER_NAME" ]; then
    su - coder -c "git config --global user.name '$GIT_USER_NAME'"
fi
if [ -n "$GIT_USER_EMAIL" ]; then
    su - coder -c "git config --global user.email '$GIT_USER_EMAIL'"
fi

# --- Start SSH Daemon ---
echo "Starting SSH server on port 22..."
exec /usr/sbin/sshd -D -e
