#!/usr/bin/env bash

# Source entrypoint functions without executing top-level code
export __SOURCED_FOR_TESTING=true

# Create temp directory for test artifacts
export TEST_TMPDIR
TEST_TMPDIR="$(mktemp -d)"

# Source the entrypoint (guard stops execution at the imperative section)
# shellcheck source=../entrypoint.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../entrypoint.sh"

teardown_helper() {
    rm -rf "$TEST_TMPDIR"
}
