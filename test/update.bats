#!/usr/bin/env bats
# Runs the update script against the stub docker in test/stubs, never the real
# docker, with all state kept under the per-test temporary directory.

load test_helper

OLD_STAMP='alpha/img:2 sha256:alpha_img_2
zeta/img:1 sha256:zeta_img_1'

setup() {
    deploy_dir="$BATS_TEST_TMPDIR/deploy"
    setup_docker_deploy_dir "$deploy_dir" update

    export XDG_STATE_HOME="$BATS_TEST_TMPDIR/state"
    export FAMILIAR_DEPLOYCHECK_DELAY=0

    stamp_dir="$XDG_STATE_HOME/familiar"
    stamp="$stamp_dir/deployed-images"
    mkdir -p "$stamp_dir"
}

calls() {
    grep -c -- "$1" "$STUB_DIR/docker-calls" || true
}

@test "docker missing" {
    # Only what update needs before its docker check, so no docker is reachable.
    no_docker_dir="$BATS_TEST_TMPDIR/no-docker"
    mkdir -p "$no_docker_dir"
    ln -s "$(command -v dirname)" "$no_docker_dir/dirname"
    run_with_path "$no_docker_dir" "$deploy_dir/update"
    [ "$status" -eq 1 ]
    [[ "$output" == *"docker is not installed or not on PATH"* ]]
}

@test "timeout missing" {
    no_timeout_dir="$BATS_TEST_TMPDIR/no-timeout"
    make_no_timeout_dir "$no_timeout_dir"
    run_with_path "$no_timeout_dir" "$deploy_dir/update"
    [ "$status" -eq 1 ]
    [[ "$output" == *"timeout is not installed or not on PATH"* ]]
    [ -z "$(docker_calls)" ]
}

@test "docker compose version fails" {
    stub version-fails
    run "$deploy_dir/update"
    [ "$status" -eq 1 ]
    [[ "$output" == *"docker compose is not available"* ]]
    [ "$(calls 'compose pull')" -eq 0 ]
}

@test "daemon unreachable" {
    stub info-fails
    run "$deploy_dir/update"
    [ "$status" -eq 1 ]
    [[ "$output" == *"docker daemon is not reachable"* ]]
    [ "$(calls 'compose pull')" -eq 0 ]
}

@test "docker-compose.yaml missing" {
    rm -f "$deploy_dir/docker-compose.yaml"
    run "$deploy_dir/update"
    [ "$status" -eq 1 ]
    [[ "$output" == *"docker-compose.yaml not found"* ]]
    [ "$(calls 'compose pull')" -eq 0 ]
}

@test "missing .env" {
    rm -f "$deploy_dir/.env"
    run "$deploy_dir/update"
    [ "$status" -eq 1 ]
    [[ "$output" == *".env not found"* ]]
    [ "$(calls 'compose pull')" -eq 0 ]
}

@test "invalid delay override dies" {
    export FAMILIAR_DEPLOYCHECK_DELAY=abc
    run "$deploy_dir/update"
    [ "$status" -eq 1 ]
    [[ "$output" == *"must be a whole number"* ]]
}

@test "invalid timeout override dies" {
    FAMILIAR_DEPLOYCHECK_TIMEOUT=abc run "$deploy_dir/update"
    [ "$status" -eq 1 ]
    [[ "$output" == *"FAMILIAR_DEPLOYCHECK_TIMEOUT must be a whole number"* ]]
    [ -z "$(docker_calls)" ]
}

@test "zero timeout override dies" {
    FAMILIAR_DEPLOYCHECK_TIMEOUT=0 run "$deploy_dir/update"
    [ "$status" -eq 1 ]
    [[ "$output" == *"FAMILIAR_DEPLOYCHECK_TIMEOUT must be greater than zero"* ]]
    [ -z "$(docker_calls)" ]
}

@test "pull fails" {
    stub pull-fails
    run "$deploy_dir/update"
    [ "$status" -eq 1 ]
    [[ "$output" == *"docker compose pull failed"* ]]
    [ "$(calls 'compose config')" -eq 0 ]
}

@test "config --images failing" {
    stub config-fails
    run "$deploy_dir/update"
    [ "$status" -eq 1 ]
    [[ "$output" == *"docker compose config --images failed"* ]]
    [ "$(calls 'compose up')" -eq 0 ]
}

@test "config --images empty" {
    stub config-empty
    run "$deploy_dir/update"
    [ "$status" -eq 1 ]
    [[ "$output" == *"listed no images"* ]]
}

@test "image inspect failing" {
    stub inspect-fails zeta/img:1
    run "$deploy_dir/update"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Could not inspect image 'zeta/img:1'"* ]]
    [ "$(calls 'compose up')" -eq 0 ]
}

@test "image inspect returns an empty id" {
    stub inspect-empty alpha/img:2
    run "$deploy_dir/update"
    [ "$status" -eq 1 ]
    [[ "$output" == *"returned no id for image 'alpha/img:2'"* ]]
    [ "$(calls 'compose up')" -eq 0 ]
}

@test "ps fails" {
    stub ps-fails
    run "$deploy_dir/update"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Could not query the broker's state"* ]]
    [ "$(calls deploycheck)" -eq 0 ]
    [ "$(calls 'compose up')" -eq 0 ]
}

@test "unchanged and running: exit 0, no deploycheck, no up, old stamp format matches" {
    stub running
    printf '%s\n' "$OLD_STAMP" >"$stamp"
    run "$deploy_dir/update"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Nothing to do"* ]]
    [ "$(calls deploycheck)" -eq 0 ]
    [ "$(calls 'compose up')" -eq 0 ]
}

@test "stamp unreadable dies" {
    [ "$(id -u)" -ne 0 ] || skip "root can read any file"
    stub running
    printf '%s\n' "$OLD_STAMP" >"$stamp"
    chmod 000 "$stamp"
    run "$deploy_dir/update"
    chmod 600 "$stamp"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Could not read the deploy stamp"* ]]
    [ "$(calls 'compose up')" -eq 0 ]
}

@test "broker not running: no deploycheck, up runs, stamp written in the old format" {
    printf '%s\n' "$OLD_STAMP" >"$stamp"
    run "$deploy_dir/update"
    [ "$status" -eq 0 ]
    [ "$(calls deploycheck)" -eq 0 ]
    [ "$(calls 'compose up')" -eq 1 ]
    [ "$(cat "$stamp")" = "$OLD_STAMP" ]
    [ -z "$(find "$stamp_dir" -name 'deployed-images.*')" ]
}

@test "changed images with broker running: deploycheck then up" {
    stub running
    echo stale >"$stamp"
    stub deploycheck-results 0
    run "$deploy_dir/update"
    [ "$status" -eq 0 ]
    [ "$(calls deploycheck)" -eq 1 ]
    [ "$(calls 'compose up')" -eq 1 ]
    [ "$(cat "$stamp")" = "$OLD_STAMP" ]
}

@test "busy 3 times then safe" {
    stub running
    stub deploycheck-results "2 2 2 0"
    run "$deploy_dir/update"
    [ "$status" -eq 0 ]
    [ "$(calls deploycheck)" -eq 4 ]
    [ "$(calls 'compose up')" -eq 1 ]
    [ -f "$stamp" ]
}

@test "busy 20 times: dies after 20 attempts" {
    stub running
    stub deploycheck-results 2
    run "$deploy_dir/update"
    [ "$status" -eq 1 ]
    [ "$(calls deploycheck)" -eq 20 ]
    [ "$(calls 'compose up')" -eq 0 ]
    [[ "$output" == *"after 20 attempts: broker busy"* ]]
    [[ "$output" != *"Attempt 20 of 20"* ]]
    [ ! -f "$stamp" ]
}

@test "exit 1 retried then safe" {
    stub running
    stub deploycheck-results "1 1 0"
    run "$deploy_dir/update"
    [ "$status" -eq 0 ]
    [ "$(calls deploycheck)" -eq 3 ]
    [[ "$output" == *"deploycheck could not tell whether tasks are running, or docker compose exec failed (exit 1)"* ]]
    [ "$(calls 'compose up')" -eq 1 ]
}

@test "exit 1 for all 20 attempts dies" {
    stub running
    stub deploycheck-results 1
    run "$deploy_dir/update"
    [ "$status" -eq 1 ]
    [ "$(calls deploycheck)" -eq 20 ]
    [[ "$output" == *"after 20 attempts: deploycheck could not tell whether tasks are running, or docker compose exec failed (exit 1)"* ]]
}

@test "docker exec failure retried like unknown" {
    stub running
    stub deploycheck-results "125 0"
    run "$deploy_dir/update"
    [ "$status" -eq 0 ]
    [[ "$output" == *"docker compose exec failed with exit code 125"* ]]
    [ "$(calls deploycheck)" -eq 2 ]
}

@test "deploycheck timed out, then safe" {
    stub running
    stub deploycheck-results "124 0"
    run "$deploy_dir/update"
    [ "$status" -eq 0 ]
    [[ "$output" == *"deploycheck timed out after 30s"* ]]
    [ "$(calls deploycheck)" -eq 2 ]
    # The first check, one re-check after the timeout, and the check after up.
    [ "$(calls 'compose ps')" -eq 3 ]
    [ "$(calls 'compose up')" -eq 1 ]
}

@test "deploycheck killed after the timeout (137) is retried like a timeout" {
    stub running
    stub deploycheck-results "137 0"
    run "$deploy_dir/update"
    [ "$status" -eq 0 ]
    [[ "$output" == *"deploycheck timed out after 30s"* ]]
    [ "$(calls deploycheck)" -eq 2 ]
    [ "$(calls 'compose up')" -eq 1 ]
}

@test "deploycheck timed out for all 20 attempts dies" {
    stub running
    stub deploycheck-results 124
    run "$deploy_dir/update"
    [ "$status" -eq 1 ]
    [ "$(calls deploycheck)" -eq 20 ]
    [[ "$output" == *"after 20 attempts: deploycheck timed out after 30s"* ]]
    [ "$(calls 'compose up')" -eq 0 ]
    [ ! -f "$stamp" ]
}

@test "exec fails, then the broker is reported stopped: up runs without retrying deploycheck" {
    stub running
    stub broker-stops-after-ps 1
    stub deploycheck-results 125
    run "$deploy_dir/update"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Broker has stopped"* ]]
    [[ "$output" != *"Broker is safe to redeploy"* ]]
    [ "$(calls deploycheck)" -eq 1 ]
    [ "$(calls 'compose up')" -eq 1 ]
    [ "$(cat "$stamp")" = "$OLD_STAMP" ]
}

@test "unknown on the last attempt, then the broker is reported stopped: up runs" {
    stub running
    stub broker-stops-after-ps 20
    stub deploycheck-results 1
    run "$deploy_dir/update"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Broker has stopped"* ]]
    [ "$(calls deploycheck)" -eq 20 ]
    [ "$(calls 'compose up')" -eq 1 ]
}

@test "busy does not re-check the broker; the next failed exec does" {
    stub running
    stub broker-stops-after-ps 1
    stub deploycheck-results "2 125"
    run "$deploy_dir/update"
    [ "$status" -eq 0 ]
    [ "$(calls deploycheck)" -eq 2 ]
    # The first check, one re-check after the failed exec, and the check after up.
    [ "$(calls 'compose ps')" -eq 3 ]
    [ "$(calls 'compose up')" -eq 1 ]
}

@test "up -d fails" {
    stub up-fails
    run "$deploy_dir/update"
    [ "$status" -eq 1 ]
    [[ "$output" == *"docker compose up -d failed"* ]]
    [ ! -f "$stamp" ]
}

@test "broker not running after up -d" {
    stub up-leaves-broker-stopped
    run "$deploy_dir/update"
    [ "$status" -eq 1 ]
    [[ "$output" == *"The broker is not running after docker compose up -d"* ]]
    [ ! -f "$stamp" ]
}

@test "stamp directory cannot be created" {
    rm -rf "$XDG_STATE_HOME"
    : >"$XDG_STATE_HOME"
    run "$deploy_dir/update"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Could not create the stamp directory"* ]]
}

@test "stamp directory unwritable" {
    [ "$(id -u)" -ne 0 ] || skip "root can write to any directory"
    chmod 500 "$stamp_dir"
    run "$deploy_dir/update"
    chmod 700 "$stamp_dir"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Could not create a temporary stamp file"* ]]
    [ ! -f "$stamp" ]
}
