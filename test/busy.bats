#!/usr/bin/env bats
# Runs the busy script against the stub docker in test/stubs, never the real
# docker, with all state kept under the per-test temporary directory.

load test_helper

PRECONDITION_CALLS='compose version
info'

PS_CALLS="$PRECONDITION_CALLS
compose ps -q --status running broker"

ALL_CALLS="$PS_CALLS
compose exec -T broker python -m broker.deploycheck"

setup() {
    deploy_dir="$BATS_TEST_TMPDIR/deploy"
    setup_docker_deploy_dir "$deploy_dir" busy
}

@test "docker missing" {
    # Only what busy needs before its docker check, so no docker is reachable.
    no_docker_dir="$BATS_TEST_TMPDIR/no-docker"
    mkdir -p "$no_docker_dir"
    ln -s "$(command -v dirname)" "$no_docker_dir/dirname"
    run_with_path "$no_docker_dir" "$deploy_dir/busy"
    [ "$status" -eq 1 ]
    [[ "$output" == *"docker is not installed or not on PATH"* ]]
    [ -z "$(docker_calls)" ]
}

@test "timeout missing" {
    no_timeout_dir="$BATS_TEST_TMPDIR/no-timeout"
    make_no_timeout_dir "$no_timeout_dir"
    run_with_path "$no_timeout_dir" "$deploy_dir/busy"
    [ "$status" -eq 1 ]
    [[ "$output" == *"timeout is not installed or not on PATH"* ]]
    [ -z "$(docker_calls)" ]
}

@test "invalid timeout override dies" {
    FAMILIAR_DEPLOYCHECK_TIMEOUT=abc run "$deploy_dir/busy"
    [ "$status" -eq 1 ]
    [[ "$output" == *"FAMILIAR_DEPLOYCHECK_TIMEOUT must be a whole number"* ]]
    [ -z "$(docker_calls)" ]
}

@test "zero timeout override dies" {
    FAMILIAR_DEPLOYCHECK_TIMEOUT=0 run "$deploy_dir/busy"
    [ "$status" -eq 1 ]
    [[ "$output" == *"FAMILIAR_DEPLOYCHECK_TIMEOUT must be greater than zero"* ]]
    [ -z "$(docker_calls)" ]
}

@test "docker compose version fails" {
    stub version-fails
    run "$deploy_dir/busy"
    [ "$status" -eq 1 ]
    [[ "$output" == *"docker compose is not available"* ]]
    [ "$(docker_calls)" = "compose version" ]
}

@test "daemon unreachable" {
    stub info-fails
    run "$deploy_dir/busy"
    [ "$status" -eq 1 ]
    [[ "$output" == *"docker daemon is not reachable"* ]]
    [ "$(docker_calls)" = "$PRECONDITION_CALLS" ]
}

@test "docker-compose.yaml missing" {
    rm -f "$deploy_dir/docker-compose.yaml"
    run "$deploy_dir/busy"
    [ "$status" -eq 1 ]
    [[ "$output" == *"docker-compose.yaml not found"* ]]
    [ "$(docker_calls)" = "$PRECONDITION_CALLS" ]
}

@test "missing .env" {
    rm -f "$deploy_dir/.env"
    run "$deploy_dir/busy"
    [ "$status" -eq 1 ]
    [[ "$output" == *".env not found"* ]]
    [ "$(docker_calls)" = "$PRECONDITION_CALLS" ]
}

@test "broker state query fails" {
    stub ps-fails
    run "$deploy_dir/busy"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Could not query the broker's state"* ]]
    [ "$(docker_calls)" = "$PS_CALLS" ]
}

@test "broker not running: safe without deploycheck" {
    run "$deploy_dir/busy"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Broker is not running, so no tasks can be in flight"* ]]
    [ "$(docker_calls)" = "$PS_CALLS" ]
}

@test "deploycheck safe" {
    stub running
    stub deploycheck-results 0
    run "$deploy_dir/busy"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Broker is idle; safe to redeploy"* ]]
    [ "$(docker_calls)" = "$ALL_CALLS" ]
}

@test "deploycheck busy exits 2 without retrying" {
    stub running
    stub deploycheck-results "2 0"
    run "$deploy_dir/busy"
    [ "$status" -eq 2 ]
    [[ "$output" == *"Broker busy, tasks are running"* ]]
    [ "$(docker_calls)" = "$ALL_CALLS" ]
}

@test "deploycheck unknown exits 1 without retrying" {
    stub running
    stub deploycheck-results "1 0"
    run "$deploy_dir/busy"
    [ "$status" -eq 1 ]
    [[ "$output" == *"deploycheck could not tell whether tasks are running, or docker compose exec failed (exit 1)"* ]]
    [ "$(docker_calls)" = "$ALL_CALLS" ]
}

@test "docker compose exec failure exits 1" {
    stub running
    stub deploycheck-results 125
    run "$deploy_dir/busy"
    [ "$status" -eq 1 ]
    [[ "$output" == *"docker compose exec (or timeout) failed with exit code 125"* ]]
    [ "$(docker_calls)" = "$ALL_CALLS" ]
}

@test "deploycheck timed out exits 1" {
    stub running
    stub deploycheck-results "124 0"
    run "$deploy_dir/busy"
    [ "$status" -eq 1 ]
    [[ "$output" == *"deploycheck timed out after 30s"* ]]
    [ "$(docker_calls)" = "$ALL_CALLS" ]
}

@test "deploycheck killed after the timeout (137) exits 1 as a timeout" {
    stub running
    stub deploycheck-results "137 0"
    run "$deploy_dir/busy"
    [ "$status" -eq 1 ]
    [[ "$output" == *"deploycheck timed out after 30s"* ]]
    [ "$(docker_calls)" = "$ALL_CALLS" ]
}

@test "runs from its own directory when started elsewhere" {
    cd "$BATS_TEST_TMPDIR"
    run "$deploy_dir/busy"
    [ "$status" -eq 0 ]
    [ "$(docker_calls)" = "$PS_CALLS" ]
}
