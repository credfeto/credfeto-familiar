#!/usr/bin/env bats
# Runs a copy of the install script against the stub sudo and systemctl in
# test/stubs, never the real ones, with all state kept under the per-test
# temporary directory.

load test_helper

setup() {
    deploy_dir="$BATS_TEST_TMPDIR/deploy"
    setup_deploy_dir "$deploy_dir" install sudo
    mkdir -p "$deploy_dir/systemd"
    : >"$deploy_dir/systemd/familiar-update.service"
    : >"$deploy_dir/systemd/familiar-update.timer"

    # install runs sudo, so refuse to run any test unless the stubs shadow the
    # real sudo and systemctl.
    require_stub sudo
    require_stub systemctl

    ALL_CALLS="cp $deploy_dir/systemd/familiar-update.service /etc/systemd/system/
cp $deploy_dir/systemd/familiar-update.timer /etc/systemd/system/
systemctl daemon-reload
systemctl enable familiar-update.timer
systemctl restart familiar-update.timer"
}

require_stub() {
    resolved=$(command -v "$1" || true)
    if [ "$resolved" != "$BATS_TEST_DIRNAME/stubs/$1" ]; then
        printf '%s resolves to "%s", not the stub in %s/stubs\n' "$1" "$resolved" "$BATS_TEST_DIRNAME" >&2
        return 1
    fi
}

sudo_calls() {
    cat "$STUB_DIR/sudo-calls"
}

# The calls made up to and including the one matching the pattern, in the
# order install makes them.
calls_through() {
    printf '%s\n' "$ALL_CALLS" | sed "\\#$1\$#q"
}

@test "sudo missing" {
    # Only what install needs before its sudo check, so no sudo is reachable.
    no_sudo_dir="$BATS_TEST_TMPDIR/no-sudo"
    mkdir -p "$no_sudo_dir"
    ln -s "$(command -v dirname)" "$no_sudo_dir/dirname"
    run_with_path "$no_sudo_dir" "$deploy_dir/install"
    [ "$status" -eq 1 ]
    [[ "$output" == *"sudo is not installed or not on PATH"* ]]
    [ -z "$(sudo_calls)" ]
}

@test "systemctl missing" {
    # The stub sudo but no systemctl, so the real sudo is still unreachable.
    no_systemctl_dir="$BATS_TEST_TMPDIR/no-systemctl"
    mkdir -p "$no_systemctl_dir"
    ln -s "$(command -v dirname)" "$no_systemctl_dir/dirname"
    ln -s "$BATS_TEST_DIRNAME/stubs/sudo" "$no_systemctl_dir/sudo"
    run_with_path "$no_systemctl_dir" "$deploy_dir/install"
    [ "$status" -eq 1 ]
    [[ "$output" == *"systemctl is not installed or not on PATH"* ]]
    [ -z "$(sudo_calls)" ]
}

@test "service unit missing" {
    rm -f "$deploy_dir/systemd/familiar-update.service"
    run "$deploy_dir/install"
    [ "$status" -eq 1 ]
    [[ "$output" == *"familiar-update.service not found in $deploy_dir/systemd"* ]]
    [ -z "$(sudo_calls)" ]
}

@test "timer unit missing" {
    rm -f "$deploy_dir/systemd/familiar-update.timer"
    run "$deploy_dir/install"
    [ "$status" -eq 1 ]
    [[ "$output" == *"familiar-update.timer not found in $deploy_dir/systemd"* ]]
    [ -z "$(sudo_calls)" ]
}

@test "copying the service fails" {
    stub cp-service-fails
    run "$deploy_dir/install"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Could not copy familiar-update.service to /etc/systemd/system/"* ]]
    [ "$(sudo_calls)" = "$(calls_through 'familiar-update.service /etc/systemd/system/')" ]
}

@test "copying the timer fails" {
    stub cp-timer-fails
    run "$deploy_dir/install"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Could not copy familiar-update.timer to /etc/systemd/system/"* ]]
    [ "$(sudo_calls)" = "$(calls_through 'familiar-update.timer /etc/systemd/system/')" ]
}

@test "daemon-reload fails" {
    stub daemon-reload-fails
    run "$deploy_dir/install"
    [ "$status" -eq 1 ]
    [[ "$output" == *"systemctl daemon-reload failed"* ]]
    [ "$(sudo_calls)" = "$(calls_through '^systemctl daemon-reload')" ]
}

@test "enable fails" {
    stub enable-fails
    run "$deploy_dir/install"
    [ "$status" -eq 1 ]
    [[ "$output" == *"systemctl enable familiar-update.timer failed"* ]]
    [ "$(sudo_calls)" = "$(calls_through '^systemctl enable familiar-update.timer')" ]
}

@test "restart fails" {
    stub restart-fails
    run "$deploy_dir/install"
    [ "$status" -eq 1 ]
    [[ "$output" == *"systemctl restart familiar-update.timer failed"* ]]
    [ "$(sudo_calls)" = "$ALL_CALLS" ]
}

@test "install succeeds" {
    run "$deploy_dir/install"
    [ "$status" -eq 0 ]
    [[ "$output" == *"familiar-update.timer installed and running"* ]]
    [ "$(sudo_calls)" = "$ALL_CALLS" ]
}

@test "finds its units when started by a relative path from elsewhere" {
    cd "$BATS_TEST_TMPDIR"
    run ./deploy/install
    [ "$status" -eq 0 ]
    [ "$(sudo_calls)" = "$ALL_CALLS" ]
}
