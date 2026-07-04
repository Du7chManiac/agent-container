#!/usr/bin/env bats

setup() {
    load test_helper
    ENV_FILE="$TEST_TMPDIR/opencode-env.sh"
}

teardown() {
    teardown_helper
}

@test "write_opencode_env_file: forwards matching vars" {
    export ANTHROPIC_API_KEY="sk-test-123"
    write_opencode_env_file "$ENV_FILE"
    unset ANTHROPIC_API_KEY
    source "$ENV_FILE"
    [ "$ANTHROPIC_API_KEY" = "sk-test-123" ]
}

@test "write_opencode_env_file: excludes non-matching vars" {
    export MY_PRIVATE_SECRET="do-not-forward"
    write_opencode_env_file "$ENV_FILE"
    ! grep -q "MY_PRIVATE_SECRET" "$ENV_FILE"
    unset MY_PRIVATE_SECRET
}

@test "write_opencode_env_file: preserves multi-line values" {
    export AWS_TEST_CERT="-----BEGIN-----
line2
-----END-----"
    write_opencode_env_file "$ENV_FILE"
    local expected="$AWS_TEST_CERT"
    unset AWS_TEST_CERT
    source "$ENV_FILE"
    [ "$AWS_TEST_CERT" = "$expected" ]
}

@test "write_opencode_env_file: multi-line values do not leak extra exports" {
    export AWS_TEST_CERT="line1
FAKE_INJECTED=oops"
    write_opencode_env_file "$ENV_FILE"
    unset AWS_TEST_CERT
    ! grep -q '^export FAKE_INJECTED' "$ENV_FILE"
    source "$ENV_FILE"
    [ -z "${FAKE_INJECTED:-}" ]
}

@test "write_opencode_env_file: preserves special characters" {
    export OPENCODE_SERVER_PASSWORD='p@$$ "word" '\''with'\'' spaces'
    local expected="$OPENCODE_SERVER_PASSWORD"
    write_opencode_env_file "$ENV_FILE"
    unset OPENCODE_SERVER_PASSWORD
    source "$ENV_FILE"
    [ "$OPENCODE_SERVER_PASSWORD" = "$expected" ]
}

@test "write_opencode_env_file: values containing '=' survive" {
    export GITEA_TOKEN="abc=def=ghi"
    write_opencode_env_file "$ENV_FILE"
    unset GITEA_TOKEN
    source "$ENV_FILE"
    [ "$GITEA_TOKEN" = "abc=def=ghi" ]
}

@test "write_opencode_env_file: truncates previous contents" {
    echo "export STALE=1" > "$ENV_FILE"
    write_opencode_env_file "$ENV_FILE"
    ! grep -q "STALE" "$ENV_FILE"
}

@test "write_opencode_env_file: generated file is valid shell" {
    export ANTHROPIC_API_KEY="sk-test"
    export AWS_MULTILINE="a
b"
    write_opencode_env_file "$ENV_FILE"
    bash -n "$ENV_FILE"
}
