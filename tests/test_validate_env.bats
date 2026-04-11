#!/usr/bin/env bats

setup() {
    load test_helper
    # Clear all env vars that validate_env checks
    unset OPENCODE_MODE OPENCODE_PORT TZ GIT_REPO_URL
    unset GITEA_URL GITEA_TOKEN OPENCODE_CONFIG_JSON
    unset SSH_PUBLIC_KEY SSH_PASSWORD SSH_ENABLED
    unset OPENCHAMBER_UI_PASSWORD OPENCODE_SERVER_PASSWORD OPENCODE_SERVER_USERNAME
}

teardown() {
    teardown_helper
}

# --- OPENCODE_MODE ---

@test "validate_env: accepts OPENCODE_MODE=ssh" {
    export OPENCODE_MODE=ssh
    run validate_env
    [ "$status" -eq 0 ]
}

@test "validate_env: accepts OPENCODE_MODE=web" {
    export OPENCODE_MODE=web
    run validate_env
    [ "$status" -eq 0 ]
}

@test "validate_env: accepts OPENCODE_MODE=serve" {
    export OPENCODE_MODE=serve
    run validate_env
    [ "$status" -eq 0 ]
}

@test "validate_env: accepts OPENCODE_MODE=openchamber" {
    export OPENCODE_MODE=openchamber
    export OPENCHAMBER_UI_PASSWORD=secret
    run validate_env
    [ "$status" -eq 0 ]
}

@test "validate_env: rejects OPENCODE_MODE=invalid" {
    export OPENCODE_MODE=invalid
    run validate_env
    [ "$status" -ne 0 ]
    [[ "$output" == *"Invalid OPENCODE_MODE"* ]]
}

@test "validate_env: accepts unset OPENCODE_MODE" {
    unset OPENCODE_MODE
    run validate_env
    [ "$status" -eq 0 ]
}

# --- OPENCODE_PORT ---

@test "validate_env: accepts OPENCODE_PORT=4096" {
    export OPENCODE_PORT=4096
    run validate_env
    [ "$status" -eq 0 ]
}

@test "validate_env: accepts OPENCODE_PORT=1 (minimum)" {
    export OPENCODE_PORT=1
    run validate_env
    [ "$status" -eq 0 ]
}

@test "validate_env: accepts OPENCODE_PORT=65535 (maximum)" {
    export OPENCODE_PORT=65535
    run validate_env
    [ "$status" -eq 0 ]
}

@test "validate_env: rejects OPENCODE_PORT=0" {
    export OPENCODE_PORT=0
    run validate_env
    [ "$status" -ne 0 ]
    [[ "$output" == *"Invalid OPENCODE_PORT"* ]]
}

@test "validate_env: rejects OPENCODE_PORT=65536" {
    export OPENCODE_PORT=65536
    run validate_env
    [ "$status" -ne 0 ]
    [[ "$output" == *"Invalid OPENCODE_PORT"* ]]
}

@test "validate_env: rejects OPENCODE_PORT=abc" {
    export OPENCODE_PORT=abc
    run validate_env
    [ "$status" -ne 0 ]
    [[ "$output" == *"Invalid OPENCODE_PORT"* ]]
}

@test "validate_env: rejects OPENCODE_PORT=-1" {
    export OPENCODE_PORT=-1
    run validate_env
    [ "$status" -ne 0 ]
    [[ "$output" == *"Invalid OPENCODE_PORT"* ]]
}

# --- TZ ---

@test "validate_env: accepts valid TZ" {
    if [ ! -f /usr/share/zoneinfo/UTC ]; then
        skip "zoneinfo not available"
    fi
    export TZ=UTC
    run validate_env
    [ "$status" -eq 0 ]
}

@test "validate_env: rejects invalid TZ" {
    export TZ=Fake/Nowhere
    run validate_env
    [ "$status" -ne 0 ]
    [[ "$output" == *"Invalid timezone"* ]]
}

@test "validate_env: accepts unset TZ" {
    unset TZ
    run validate_env
    [ "$status" -eq 0 ]
}

# --- GIT_REPO_URL ---

@test "validate_env: accepts https git URL" {
    export GIT_REPO_URL=https://github.com/user/repo.git
    run validate_env
    [ "$status" -eq 0 ]
}

@test "validate_env: accepts ssh git URL" {
    export GIT_REPO_URL=git@github.com:user/repo.git
    run validate_env
    [ "$status" -eq 0 ]
}

@test "validate_env: warns on invalid git URL format" {
    export GIT_REPO_URL=not-a-url
    run validate_env
    # Warning only, not an error
    [ "$status" -eq 0 ]
    [[ "$output" == *"doesn't look like a valid git URL"* ]]
}

# --- GITEA_URL + GITEA_TOKEN pairing ---

@test "validate_env: accepts both GITEA vars set" {
    export GITEA_URL=https://gitea.example.com
    export GITEA_TOKEN=abc123
    run validate_env
    [ "$status" -eq 0 ]
}

@test "validate_env: accepts both GITEA vars unset" {
    unset GITEA_URL GITEA_TOKEN
    run validate_env
    [ "$status" -eq 0 ]
}

@test "validate_env: rejects GITEA_URL without GITEA_TOKEN" {
    export GITEA_URL=https://gitea.example.com
    unset GITEA_TOKEN
    run validate_env
    [ "$status" -ne 0 ]
    [[ "$output" == *"must both be set"* ]]
}

@test "validate_env: rejects GITEA_TOKEN without GITEA_URL" {
    unset GITEA_URL
    export GITEA_TOKEN=abc123
    run validate_env
    [ "$status" -ne 0 ]
    [[ "$output" == *"must both be set"* ]]
}

# --- OPENCODE_CONFIG_JSON ---

@test "validate_env: accepts valid JSON config" {
    export OPENCODE_CONFIG_JSON='{"key":"value"}'
    run validate_env
    [ "$status" -eq 0 ]
}

@test "validate_env: rejects invalid JSON config" {
    export OPENCODE_CONFIG_JSON='not json {'
    run validate_env
    [ "$status" -ne 0 ]
    [[ "$output" == *"not valid JSON"* ]]
}

# --- SSH_ENABLED validation ---

@test "validate_env: accepts SSH_ENABLED=true" {
    export SSH_ENABLED=true
    run validate_env
    [ "$status" -eq 0 ]
}

@test "validate_env: accepts SSH_ENABLED=false" {
    export SSH_ENABLED=false
    run validate_env
    [ "$status" -eq 0 ]
}

@test "validate_env: accepts unset SSH_ENABLED" {
    unset SSH_ENABLED
    run validate_env
    [ "$status" -eq 0 ]
}

@test "validate_env: rejects SSH_ENABLED=invalid" {
    export SSH_ENABLED=invalid
    run validate_env
    [ "$status" -ne 0 ]
    [[ "$output" == *"Invalid SSH_ENABLED"* ]]
}

# --- SSH auth warning (only when SSH is active) ---

@test "validate_env: warns when no SSH auth configured and OPENCODE_MODE=ssh" {
    export OPENCODE_MODE=ssh
    unset SSH_PUBLIC_KEY SSH_PASSWORD
    run validate_env
    [ "$status" -eq 0 ]
    [[ "$output" == *"random password will be generated"* ]]
}

@test "validate_env: warns when no SSH auth configured and SSH_ENABLED=true" {
    export SSH_ENABLED=true
    unset SSH_PUBLIC_KEY SSH_PASSWORD
    run validate_env
    [ "$status" -eq 0 ]
    [[ "$output" == *"random password will be generated"* ]]
}

@test "validate_env: no SSH warning in default serve mode" {
    unset OPENCODE_MODE SSH_ENABLED SSH_PUBLIC_KEY SSH_PASSWORD
    run validate_env
    [ "$status" -eq 0 ]
    [[ "$output" != *"random password"* ]]
}

@test "validate_env: no warning when SSH_PUBLIC_KEY is set" {
    export OPENCODE_MODE=ssh
    export SSH_PUBLIC_KEY="ssh-ed25519 AAAA..."
    run validate_env
    [ "$status" -eq 0 ]
    [[ "$output" != *"random password"* ]]
}

# --- OpenChamber mode warnings ---

@test "validate_env: warns when openchamber mode has no UI password" {
    export OPENCODE_MODE=openchamber
    unset OPENCHAMBER_UI_PASSWORD
    run validate_env
    [ "$status" -eq 0 ]
    [[ "$output" == *"UI will be unprotected"* ]]
}

@test "validate_env: warns when OPENCODE_SERVER_PASSWORD set in openchamber mode" {
    export OPENCODE_MODE=openchamber
    export OPENCODE_SERVER_PASSWORD=foo
    export OPENCHAMBER_UI_PASSWORD=bar
    run validate_env
    [ "$status" -eq 0 ]
    [[ "$output" == *"OPENCODE_SERVER_PASSWORD is ignored"* ]]
}

@test "validate_env: warns when OPENCODE_SERVER_USERNAME set in openchamber mode" {
    export OPENCODE_MODE=openchamber
    export OPENCODE_SERVER_USERNAME=someuser
    export OPENCHAMBER_UI_PASSWORD=bar
    run validate_env
    [ "$status" -eq 0 ]
    [[ "$output" == *"OPENCODE_SERVER_USERNAME is ignored"* ]]
}

@test "validate_env: no openchamber warning in serve mode" {
    unset OPENCODE_MODE OPENCHAMBER_UI_PASSWORD
    run validate_env
    [ "$status" -eq 0 ]
    [[ "$output" != *"UI will be unprotected"* ]]
}

# --- Multiple errors accumulate ---

@test "validate_env: reports multiple errors at once" {
    export OPENCODE_MODE=bad
    export OPENCODE_PORT=abc
    export GITEA_URL=https://example.com
    unset GITEA_TOKEN
    run validate_env
    [ "$status" -ne 0 ]
    [[ "$output" == *"3 configuration error(s)"* ]]
}
