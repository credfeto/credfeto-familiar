#!/usr/bin/env bats
# Runs the busy script against the stub docker in test/stubs, never the real
# docker, with all state kept under the per-test temporary directory.

PRECONDITION_CALLS='compose version
info'

PS_CALLS="$PRECONDITION_CALLS
compose ps -q --status running broker"

ALL_CALLS="$PS_CALLS
compose exec -T broker python -m broker.deploycheck"

setup() {
    deploy_dir="$BATS_TEST_TMPDIR/deploy"
    mkdir -p "$deploy_dir"
    cp "$BATS_TEST_DIRNAME/../busy" "$deploy_dir/busy"
    : >"$deploy_dir/docker-compose.yaml"
    : >"$deploy_dir/.env"

    export STUB_DIR="$BATS_TEST_TMPDIR/stub"
    mkdir -p "$STUB_DIR"
    : >"$STUB_DIR/docker-calls"

    PATH="$BATS_TEST_DIRNAME/stubs:$PATH"
}

# Sets a stub docker behaviour: the file's name selects it, and its content
# (if any) is the behaviour's argument.
stub() {
    printf '%s' "${2:-}" >"$STUB_DIR/$1"
}

docker_calls() {
    cat "$STUB_DIR/docker-calls"
}

@test "docker missing" {
    # Only what busy needs before its docker check, so no docker is reachable.
    no_docker_dir="$BATS_TEST_TMPDIR/no-docker"
    mkdir -p "$no_docker_dir"
    ln -s "$(command -v dirname)" "$no_docker_dir/dirname"
    saved_path="$PATH"
    PATH="$no_docker_dir"
    run "$deploy_dir/busy"
    PATH="$saved_path"
    [ "$status" -eq 1 ]
    [[ "$output" == *"docker is not installed or not on PATH"* ]]
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
    [[ "$output" == *"deploycheck could not tell whether tasks are running"* ]]
    [ "$(docker_calls)" = "$ALL_CALLS" ]
}

@test "docker compose exec failure exits 1" {
    stub running
    stub deploycheck-results 125
    run "$deploy_dir/busy"
    [ "$status" -eq 1 ]
    [[ "$output" == *"docker compose exec failed with exit code 125"* ]]
    [ "$(docker_calls)" = "$ALL_CALLS" ]
}

@test "runs from its own directory when started elsewhere" {
    cd "$BATS_TEST_TMPDIR"
    run "$deploy_dir/busy"
    [ "$status" -eq 0 ]
    [ "$(docker_calls)" = "$PS_CALLS" ]
}
