#!/usr/bin/env bats

setup() {
    load test_helper
    unset OPENCODE_SERVER_PASSWORD OPENCODE_PASSWORD
    BIN_DIR="$TEST_TMPDIR/bin"
    SKEL_DIR="$TEST_TMPDIR/skel"
    DATA_DIR="$TEST_TMPDIR/data"
    mkdir -p "$BIN_DIR" "$SKEL_DIR" "$DATA_DIR"
    printf 'canary\n' > "$DATA_DIR/session.txt"
}

teardown() {
    teardown_helper
}

write_fake_opencode() {
    local path="$1"
    local version="$2"
    cat > "$path" <<EOF
#!/bin/sh
echo "$version"
EOF
    chmod 755 "$path"
}

@test "opencode_version_of: reads a bare version" {
    write_fake_opencode "$BIN_DIR/opencode" "1.18.32"
    [ "$(opencode_version_of "$BIN_DIR/opencode")" = "1.18.32" ]
}

@test "opencode_version_of: strips a leading v and a name prefix" {
    cat > "$BIN_DIR/opencode" <<'EOF'
#!/bin/sh
echo "opencode v2.0.16"
EOF
    chmod 755 "$BIN_DIR/opencode"
    [ "$(opencode_version_of "$BIN_DIR/opencode")" = "2.0.16" ]
}

@test "opencode_is_v2: accepts 2.x and rejects 1.x" {
    opencode_is_v2 "2.0.16"
    ! opencode_is_v2 "1.18.32"
    ! opencode_is_v2 ""
}

@test "ensure_opencode_binary: replaces a v1 binary and leaves data alone" {
    write_fake_opencode "$BIN_DIR/opencode" "1.18.32"
    write_fake_opencode "$SKEL_DIR/opencode" "2.0.16"
    run ensure_opencode_binary "$BIN_DIR/opencode" "$SKEL_DIR/opencode"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Replaced OpenCode 1.18.32 with 2.0.16"* ]]
    [ "$(opencode_version_of "$BIN_DIR/opencode")" = "2.0.16" ]
    [ "$(cat "$DATA_DIR/session.txt")" = "canary" ]
}

@test "ensure_opencode_binary: leaves an existing 2.x binary in place" {
    write_fake_opencode "$BIN_DIR/opencode" "2.1.0"
    write_fake_opencode "$SKEL_DIR/opencode" "2.0.16"
    run ensure_opencode_binary "$BIN_DIR/opencode" "$SKEL_DIR/opencode"
    [ "$status" -eq 0 ]
    [[ "$output" == *"already v2"* ]]
    [ "$(opencode_version_of "$BIN_DIR/opencode")" = "2.1.0" ]
}

@test "ensure_opencode_binary: installs from the skeleton when the binary is missing" {
    write_fake_opencode "$SKEL_DIR/opencode" "2.0.16"
    run ensure_opencode_binary "$BIN_DIR/opencode" "$SKEL_DIR/opencode"
    [ "$status" -eq 0 ]
    [ "$(opencode_version_of "$BIN_DIR/opencode")" = "2.0.16" ]
}

@test "ensure_opencode_binary: fails when the skeleton is missing" {
    write_fake_opencode "$BIN_DIR/opencode" "1.18.32"
    run ensure_opencode_binary "$BIN_DIR/opencode" "$SKEL_DIR/missing"
    [ "$status" -eq 1 ]
    [ "$(opencode_version_of "$BIN_DIR/opencode")" = "1.18.32" ]
}

@test "ensure_server_password: generates a password once and reuses the file" {
    local file="$TEST_TMPDIR/server-password"
    ensure_server_password "$file"
    local first="$OPENCODE_SERVER_PASSWORD"
    [ -n "$first" ]
    [ "$(tr -d '\n' < "$file")" = "$first" ]
    # GNU stat uses -c; BSD stat uses -f. Calling -f first makes GNU stat
    # treat the format string as a filesystem path and can abort the test.
    if stat -c '%a' "$file" >/dev/null 2>&1; then
        [ "$(stat -c '%a' "$file")" = "600" ]
    else
        [ "$(stat -f '%Lp' "$file")" = "600" ]
    fi

    unset OPENCODE_SERVER_PASSWORD
    ensure_server_password "$file"
    [ "$OPENCODE_SERVER_PASSWORD" = "$first" ]
}

@test "ensure_server_password: explicit password wins and does not write the file" {
    local file="$TEST_TMPDIR/server-password"
    export OPENCODE_SERVER_PASSWORD="from-env"
    ensure_server_password "$file"
    [ "$OPENCODE_SERVER_PASSWORD" = "from-env" ]
    [ ! -f "$file" ]
}

@test "scrub_managed_opencode_auth: removes a password-only env file" {
    local file="$TEST_TMPDIR/opencode-env.sh"
    printf '%s\n' "export OPENCODE_SERVER_PASSWORD=secret" > "$file"
    scrub_managed_opencode_auth "$file"
    ! grep -q 'OPENCODE_SERVER_PASSWORD' "$file"
    bash -n "$file"
}

@test "scrub_managed_opencode_auth: keeps unrelated exports" {
    local file="$TEST_TMPDIR/opencode-env.sh"
    printf '%s\n' \
        "export OPENCODE_SERVER_PASSWORD=secret" \
        "export OPENCODE_PASSWORD=other" \
        "export ANTHROPIC_API_KEY=sk-test" > "$file"
    scrub_managed_opencode_auth "$file"
    ! grep -q 'OPENCODE_SERVER_PASSWORD' "$file"
    ! grep -q 'OPENCODE_PASSWORD' "$file"
    grep -q 'ANTHROPIC_API_KEY=sk-test' "$file"
}

@test "ensure_server_password: OPENCODE_PASSWORD is used when the server password is unset" {
    local file="$TEST_TMPDIR/server-password"
    export OPENCODE_PASSWORD="from-v2-name"
    ensure_server_password "$file"
    [ "$OPENCODE_SERVER_PASSWORD" = "from-v2-name" ]
    [ ! -f "$file" ]
}
