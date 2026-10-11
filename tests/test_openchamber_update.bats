#!/usr/bin/env bats

# update_openchamber with a fake npm on PATH. FAKE_INSTALLED is the installed
# version (empty = not installed), FAKE_VIEW is the raw `npm view --json` output.
setup() {
    load test_helper
    FAKE_BIN="$TEST_TMPDIR/fakebin"
    STATE="$TEST_TMPDIR/state"
    mkdir -p "$FAKE_BIN" "$STATE"
    cat > "$FAKE_BIN/npm" <<'NPM'
#!/bin/bash
state="$FAKE_STATE"
case "$1" in
    ls)
        v=$(cat "$state/installed" 2>/dev/null)
        if [ -n "$v" ]; then
            printf '{"dependencies":{"@openchamber/web":{"version":"%s"}}}\n' "$v"
        else
            echo '{}'
        fi
        ;;
    view)
        cat "$state/view"
        [ "$(cat "$state/view_rc" 2>/dev/null)" != "1" ]
        ;;
    install)
        echo "$*" >> "$state/install_calls"
        [ "$(cat "$state/install_rc" 2>/dev/null)" = "1" ] && exit 1
        echo "${3##*@}" > "$state/installed"
        ;;
    cache) ;;
esac
NPM
    chmod 755 "$FAKE_BIN/npm"
    export FAKE_STATE="$STATE"
    export PATH="$FAKE_BIN:$PATH"
}

teardown() {
    teardown_helper
}

@test "openchamber_latest_version: picks the highest from an array" {
    echo '["2.0.1","2.1.0","2.0.10"]' > "$STATE/view"
    run openchamber_latest_version
    [ "$output" = "2.1.0" ]
}

@test "openchamber_latest_version: handles a single string" {
    echo '"2.0.3"' > "$STATE/view"
    run openchamber_latest_version
    [ "$output" = "2.0.3" ]
}

@test "openchamber_latest_version: empty on a registry error" {
    echo '{"error":{"code":"E404"}}' > "$STATE/view"
    echo 1 > "$STATE/view_rc"
    run openchamber_latest_version
    [ -z "$output" ]
}

@test "update_openchamber: installs a newer release" {
    echo 2.0.1 > "$STATE/installed"
    echo '["2.0.1","2.0.4"]' > "$STATE/view"
    run update_openchamber
    [ "$status" -eq 0 ]
    [[ "$output" == *"OpenChamber updated: 2.0.1 -> 2.0.4"* ]]
    grep -q "install -g @openchamber/web@2.0.4" "$STATE/install_calls"
}

@test "update_openchamber: skips install when up to date" {
    echo 2.0.4 > "$STATE/installed"
    echo '"2.0.4"' > "$STATE/view"
    run update_openchamber
    [ "$status" -eq 0 ]
    [[ "$output" == *"already up to date (2.0.4)"* ]]
    [ ! -f "$STATE/install_calls" ]
}

@test "update_openchamber: keeps the current version when the lookup fails" {
    echo 2.0.1 > "$STATE/installed"
    echo '{"error":{}}' > "$STATE/view"
    echo 1 > "$STATE/view_rc"
    run update_openchamber
    [ "$status" -eq 0 ]
    [[ "$output" == *"Could not look up"* ]]
    [ ! -f "$STATE/install_calls" ]
}

@test "update_openchamber: a failed install does not stop the container" {
    echo 2.0.1 > "$STATE/installed"
    echo '"2.0.4"' > "$STATE/view"
    echo 1 > "$STATE/install_rc"
    run update_openchamber
    [ "$status" -eq 0 ]
    [[ "$output" == *"OpenChamber update failed"* ]]
    [ "$(cat "$STATE/installed")" = "2.0.1" ]
}
