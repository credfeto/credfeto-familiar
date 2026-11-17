#!/usr/bin/env bats
# Runs the reset script against the stub docker in test/stubs, never the real
# docker, with all state kept under the per-test temporary directory.

PRECONDITION_CALLS='compose version
info'

ALL_CALLS="$PRECONDITION_CALLS
compose pull
compose stop
compose rm -f
compose up -d --remove-orphans"

setup() {
    deploy_dir="$BATS_TEST_TMPDIR/deploy"
    mkdir -p "$deploy_dir"
    cp "$BATS_TEST_DIRNAME/../reset" "$deploy_dir/reset"
    : >"$deploy_dir/docker-compose.yaml"
    : >"$deploy_dir/.env"

    export STUB_DIR="$BATS_TEST_TMPDIR/stub"
    mkdir -p "$STUB_DIR"
    : >"$STUB_DIR/docker-calls"

    PATH="$BATS_TEST_DIRNAME/stubs:$PATH"
}

# Sets a stub docker behaviour: the file's name selects it.
stub() {
    : >"$STUB_DIR/$1"
}

docker_calls() {
    cat "$STUB_DIR/docker-calls"
}

# The calls made up to and including the named one, in the order reset makes
# them.
calls_through() {
    printf '%s\n' "$ALL_CALLS" | sed "/^$1\$/q"
}

@test "docker missing" {
    # Only what reset needs before its docker check, so no docker is reachable.
    no_docker_dir="$BATS_TEST_TMPDIR/no-docker"
    mkdir -p "$no_docker_dir"
    ln -s "$(command -v dirname)" "$no_docker_dir/dirname"
    saved_path="$PATH"
    PATH="$no_docker_dir"
    run "$deploy_dir/reset"
    PATH="$saved_path"
    [ "$status" -eq 1 ]
    [[ "$output" == *"docker is not installed or not on PATH"* ]]
    [ -z "$(docker_calls)" ]
}

@test "docker compose version fails" {
    stub version-fails
    run "$deploy_dir/reset"
    [ "$status" -eq 1 ]
    [[ "$output" == *"docker compose is not available"* ]]
    [ "$(docker_calls)" = "compose version" ]
}

@test "daemon unreachable" {
    stub info-fails
    run "$deploy_dir/reset"
    [ "$status" -eq 1 ]
    [[ "$output" == *"docker daemon is not reachable"* ]]
    [ "$(docker_calls)" = "$PRECONDITION_CALLS" ]
}

@test "docker-compose.yaml missing" {
    rm -f "$deploy_dir/docker-compose.yaml"
    run "$deploy_dir/reset"
    [ "$status" -eq 1 ]
    [[ "$output" == *"docker-compose.yaml not found"* ]]
    [ "$(docker_calls)" = "$PRECONDITION_CALLS" ]
}

@test "missing .env" {
    rm -f "$deploy_dir/.env"
    run "$deploy_dir/reset"
    [ "$status" -eq 1 ]
    [[ "$output" == *".env not found"* ]]
    [ "$(docker_calls)" = "$PRECONDITION_CALLS" ]
}

@test "pull fails" {
    stub pull-fails
    run "$deploy_dir/reset"
    [ "$status" -eq 1 ]
    [[ "$output" == *"docker compose pull failed"* ]]
    [ "$(docker_calls)" = "$(calls_through 'compose pull')" ]
}

@test "stop fails" {
    stub stop-fails
    run "$deploy_dir/reset"
    [ "$status" -eq 1 ]
    [[ "$output" == *"docker compose stop failed"* ]]
    [ "$(docker_calls)" = "$(calls_through 'compose stop')" ]
}

@test "rm fails" {
    stub rm-fails
    run "$deploy_dir/reset"
    [ "$status" -eq 1 ]
    [[ "$output" == *"docker compose rm -f failed"* ]]
    [ "$(docker_calls)" = "$(calls_through 'compose rm -f')" ]
}

@test "up fails" {
    stub up-fails
    run "$deploy_dir/reset"
    [ "$status" -eq 1 ]
    [[ "$output" == *"docker compose up -d --remove-orphans failed"* ]]
    [ "$(docker_calls)" = "$ALL_CALLS" ]
}

@test "reset succeeds" {
    run "$deploy_dir/reset"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Containers reset"* ]]
    [ "$(docker_calls)" = "$ALL_CALLS" ]
}

@test "runs from its own directory when started elsewhere" {
    cd "$BATS_TEST_TMPDIR"
    run "$deploy_dir/reset"
    [ "$status" -eq 0 ]
    [ "$(docker_calls)" = "$ALL_CALLS" ]
}
