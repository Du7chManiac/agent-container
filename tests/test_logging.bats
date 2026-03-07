#!/usr/bin/env bats

setup() {
    load test_helper
}

teardown() {
    teardown_helper
}

@test "log_info writes with [INFO] prefix" {
    run log_info "hello world"
    [ "$status" -eq 0 ]
    [ "$output" = "[INFO]  hello world" ]
}

@test "log_warn writes with [WARN] prefix" {
    run log_warn "something suspicious"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[WARN]  something suspicious"* ]]
}

@test "log_error writes with [ERROR] prefix" {
    run log_error "something broke"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[ERROR] something broke"* ]]
}

@test "log_info handles multiple arguments" {
    run log_info "multiple" "words" "here"
    [ "$output" = "[INFO]  multiple words here" ]
}

@test "log_info handles empty string" {
    run log_info ""
    [ "$output" = "[INFO]  " ]
}

@test "log_error handles special characters" {
    run log_error 'Error: file "test.txt" not found'
    [ "$status" -eq 0 ]
    [[ "$output" == *'Error: file "test.txt" not found'* ]]
}
