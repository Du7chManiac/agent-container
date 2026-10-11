#!/usr/bin/env bats

# update_opencode with fake curl/su on PATH. latest is the body of the release
# metadata endpoint (missing = lookup fails), installed the version the fake
# binary reports, and su_calls records every installer run.
setup() {
    load test_helper
    FAKE_BIN="$TEST_TMPDIR/fakebin"
    STATE="$TEST_TMPDIR/state"
    mkdir -p "$FAKE_BIN" "$STATE"
    export FAKE_STATE="$STATE"
    BIN="$TEST_TMPDIR/opencode"
    cat > "$BIN" <<'OC'
#!/bin/bash
echo "opencode v$(cat "$FAKE_STATE/installed")"
OC
    chmod 755 "$BIN"
    cat > "$FAKE_BIN/curl" <<'CURL'
#!/bin/bash
[ -f "$FAKE_STATE/latest" ] || exit 22
cat "$FAKE_STATE/latest"
CURL
    cat > "$FAKE_BIN/su" <<'SU'
#!/bin/bash
echo "$4" >> "$FAKE_STATE/su_calls"
[ "$(cat "$FAKE_STATE/su_rc" 2>/dev/null)" = "1" ] && exit 1
v=$(sed -n 's/.*--version \([^ ]*\).*/\1/p' <<< "$4")
echo "${v:-9.9.9}" > "$FAKE_STATE/installed"
SU
    chmod 755 "$FAKE_BIN/curl" "$FAKE_BIN/su"
    export PATH="$FAKE_BIN:$PATH"
    export OPENCODE_SKEL_BIN="$TEST_TMPDIR/skel/opencode"
    mkdir -p "$TEST_TMPDIR/skel"
}

teardown() {
    teardown_helper
}

@test "opencode_latest_version: reads version from metadata" {
    echo '{"version":"2.0.20","package":"@opencode/cli"}' > "$STATE/latest"
    run opencode_latest_version
    [ "$output" = "2.0.20" ]
}

@test "opencode_latest_version: empty when the lookup fails" {
    run opencode_latest_version
    [ -z "$output" ]
}

@test "update_opencode: skips the installer when already current" {
    echo 2.0.20 > "$STATE/installed"
    echo '{"version":"2.0.20","package":"@opencode/cli"}' > "$STATE/latest"
    run update_opencode "$BIN"
    [ "$status" -eq 0 ]
    [[ "$output" == *"already up to date (2.0.20)"* ]]
    [ ! -f "$STATE/su_calls" ]
}

@test "update_opencode: installs the resolved version when newer" {
    echo 2.0.16 > "$STATE/installed"
    echo '{"version":"2.0.20","package":"@opencode/cli"}' > "$STATE/latest"
    run update_opencode "$BIN"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OpenCode updated: 2.0.16 -> 2.0.20"* ]]
    grep -q -- "--version 2.0.20" "$STATE/su_calls"
    [ -f "$OPENCODE_SKEL_BIN" ]
}

@test "update_opencode: falls back to the unpinned installer when lookup fails" {
    echo 2.0.16 > "$STATE/installed"
    run update_opencode "$BIN"
    [ "$status" -eq 0 ]
    [ -f "$STATE/su_calls" ]
    ! grep -q -- "--version" "$STATE/su_calls"
}

@test "update_opencode: keeps going when the installer fails" {
    echo 2.0.16 > "$STATE/installed"
    echo '{"version":"2.0.20","package":"@opencode/cli"}' > "$STATE/latest"
    echo 1 > "$STATE/su_rc"
    run update_opencode "$BIN"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OpenCode update failed"* ]]
}
