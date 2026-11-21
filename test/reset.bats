#!/usr/bin/env bats
# Runs the reset script against the stub docker in test/stubs, never the real
# docker, with all state kept under the per-test temporary directory.

load test_helper

PRECONDITION_CALLS='compose version
info'

BROKER_PS_CALL='compose ps -q --status running broker'

# What a reset makes when the broker is not running beforehand: the gate's ps
# finds no broker, so deploycheck is skipped, and the ps after up finds it.
ALL_CALLS="$PRECONDITION_CALLS
compose pull
compose config --images
image inspect -f {{.Id}} alpha/img:2
image inspect -f {{.Id}} zeta/img:1
compose config
$BROKER_PS_CALL
compose stop
compose rm -f
compose up -d --remove-orphans
$BROKER_PS_CALL"

STAMP_CONTENT="alpha/img:2 sha256:alpha_img_2
zeta/img:1 sha256:zeta_img_1
$(config_stamp_line)"

setup() {
    deploy_dir="$BATS_TEST_TMPDIR/deploy"
    setup_docker_deploy_dir "$deploy_dir" reset

    export XDG_STATE_HOME="$BATS_TEST_TMPDIR/state"
    export FAMILIAR_DEPLOYCHECK_DELAY=0

    stamp_dir="$XDG_STATE_HOME/familiar"
    stamp="$stamp_dir/deployed-images"
    mkdir -p "$stamp_dir"
}

# The calls made up to and including the first one with the given text, in
# the order reset makes them.
calls_through() {
    printf '%s\n' "$ALL_CALLS" | sed "/^$1\$/q"
}

calls() {
    grep -c -- "$1" "$STUB_DIR/docker-calls" || true
}

# Fails unless reset left the containers alone: nothing stopped, removed or
# started, and no stamp written.
assert_containers_untouched() {
    [ "$(calls 'compose stop')" -eq 0 ]
    [ "$(calls 'compose rm')" -eq 0 ]
    [ "$(calls 'compose up')" -eq 0 ]
    [ ! -f "$stamp" ]
}

@test "docker missing" {
    # Only what reset needs before its docker check, so no docker is reachable.
    no_docker_dir="$BATS_TEST_TMPDIR/no-docker"
    mkdir -p "$no_docker_dir"
    ln -s "$(command -v dirname)" "$no_docker_dir/dirname"
    run_with_path "$no_docker_dir" "$deploy_dir/reset"
    [ "$status" -eq 1 ]
    [[ "$output" == *"docker is not installed or not on PATH"* ]]
    [ -z "$(docker_calls)" ]
}

@test "timeout missing" {
    no_timeout_dir="$BATS_TEST_TMPDIR/no-timeout"
    make_no_timeout_dir "$no_timeout_dir"
    run_with_path "$no_timeout_dir" "$deploy_dir/reset"
    [ "$status" -eq 1 ]
    [[ "$output" == *"timeout is not installed or not on PATH"* ]]
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

@test "invalid delay override dies" {
    FAMILIAR_DEPLOYCHECK_DELAY=abc run "$deploy_dir/reset"
    [ "$status" -eq 1 ]
    [[ "$output" == *"FAMILIAR_DEPLOYCHECK_DELAY must be a whole number"* ]]
    [ -z "$(docker_calls)" ]
}

@test "invalid timeout override dies" {
    FAMILIAR_DEPLOYCHECK_TIMEOUT=abc run "$deploy_dir/reset"
    [ "$status" -eq 1 ]
    [[ "$output" == *"FAMILIAR_DEPLOYCHECK_TIMEOUT must be a whole number"* ]]
    [ -z "$(docker_calls)" ]
}

@test "zero timeout override dies" {
    FAMILIAR_DEPLOYCHECK_TIMEOUT=0 run "$deploy_dir/reset"
    [ "$status" -eq 1 ]
    [[ "$output" == *"FAMILIAR_DEPLOYCHECK_TIMEOUT must be greater than zero"* ]]
    [ -z "$(docker_calls)" ]
}

@test "pull fails" {
    stub pull-fails
    run "$deploy_dir/reset"
    [ "$status" -eq 1 ]
    [[ "$output" == *"docker compose pull failed"* ]]
    [ "$(docker_calls)" = "$(calls_through 'compose pull')" ]
    [ ! -f "$stamp" ]
}

@test "config --images failing" {
    stub config-fails
    run "$deploy_dir/reset"
    [ "$status" -eq 1 ]
    [[ "$output" == *"docker compose config --images failed"* ]]
    assert_containers_untouched
}

@test "config --images empty" {
    stub config-empty
    run "$deploy_dir/reset"
    [ "$status" -eq 1 ]
    [[ "$output" == *"listed no images"* ]]
    assert_containers_untouched
}

@test "image inspect failing" {
    stub inspect-fails zeta/img:1
    run "$deploy_dir/reset"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Could not inspect image 'zeta/img:1'"* ]]
    assert_containers_untouched
}

@test "image inspect returns an empty id" {
    stub inspect-empty alpha/img:2
    run "$deploy_dir/reset"
    [ "$status" -eq 1 ]
    [[ "$output" == *"returned no id for image 'alpha/img:2'"* ]]
    assert_containers_untouched
}

@test "resolving the compose configuration fails" {
    stub resolve-config-fails
    run "$deploy_dir/reset"
    [ "$status" -eq 1 ]
    [[ "$output" == *"docker compose config failed"* ]]
    [ "$(docker_calls)" = "$(calls_through 'compose config')" ]
    assert_containers_untouched
}

@test "hashing the compose configuration fails" {
    override_command sha256sum 'exit 1'
    run "$deploy_dir/reset"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Could not hash the compose configuration"* ]]
    [[ "$output" != *"$CONFIG_SECRET_SENTINEL"* ]]
    assert_containers_untouched
}

@test "the stamp records a hash of the configuration, never the configuration" {
    run "$deploy_dir/reset"
    [ "$status" -eq 0 ]
    [[ "$(tail -n 1 "$stamp")" =~ ^config\ [0-9a-f]{64}$ ]]
    [[ "$output" != *"$CONFIG_SECRET_SENTINEL"* ]]
    [ -z "$(grep -rlF -- "$CONFIG_SECRET_SENTINEL" "$stamp_dir" || true)" ]
}

@test "ps fails" {
    stub ps-fails
    run "$deploy_dir/reset"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Could not query the broker's state"* ]]
    [ "$(calls deploycheck)" -eq 0 ]
    assert_containers_untouched
}

@test "image refs are not globbed against files in the script directory" {
    stub config-images 'repo/img:[ab]'
    mkdir -p "$deploy_dir/repo"
    : >"$deploy_dir/repo/img:a"
    run "$deploy_dir/reset"
    [ "$status" -eq 0 ]
    [ "$(grep -cxF 'image inspect -f {{.Id}} repo/img:[ab]' "$STUB_DIR/docker-calls")" -eq 1 ]
    [ "$(grep -cF 'repo/img:a' "$STUB_DIR/docker-calls" || true)" -eq 0 ]
    [ "$(cat "$stamp")" = "repo/img:[ab] sha256:repo_img_[ab]
$(config_stamp_line)" ]
}

@test "broker not running: no deploycheck, containers recreated, stamp written" {
    run "$deploy_dir/reset"
    [ "$status" -eq 0 ]
    [[ "$output" == *"skipping deploycheck"* ]]
    [[ "$output" == *"Containers reset"* ]]
    [ "$(docker_calls)" = "$ALL_CALLS" ]
    assert_deploycheck_timeout_calls 0
    [ "$(cat "$stamp")" = "$STAMP_CONTENT" ]
    [ -z "$(find "$stamp_dir" -name 'deployed-images.*')" ]
}

@test "runs from its own directory when started elsewhere" {
    cd "$BATS_TEST_TMPDIR"
    run "$deploy_dir/reset"
    [ "$status" -eq 0 ]
    [ "$(docker_calls)" = "$ALL_CALLS" ]
}

@test "broker running and safe: deploycheck runs before the containers are stopped" {
    stub running
    stub deploycheck-results 0
    run "$deploy_dir/reset"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Broker is safe to reset"* ]]
    [ "$(docker_calls)" = "$PRECONDITION_CALLS
compose pull
compose config --images
image inspect -f {{.Id}} alpha/img:2
image inspect -f {{.Id}} zeta/img:1
compose config
$BROKER_PS_CALL
compose exec -T broker python -m broker.deploycheck
compose stop
compose rm -f
compose up -d --remove-orphans
$BROKER_PS_CALL" ]
    assert_deploycheck_timeout_calls 1
    [ "$(cat "$stamp")" = "$STAMP_CONTENT" ]
}

@test "images unchanged since the last deploy: still checked and recreated" {
    stub running
    printf '%s\n' "$STAMP_CONTENT" >"$stamp"
    run "$deploy_dir/reset"
    [ "$status" -eq 0 ]
    [[ "$output" != *"Nothing to do"* ]]
    [ "$(calls deploycheck)" -eq 1 ]
    [ "$(calls 'compose stop')" -eq 1 ]
    [ "$(calls 'compose rm -f')" -eq 1 ]
    [ "$(calls 'compose up')" -eq 1 ]
    [ "$(cat "$stamp")" = "$STAMP_CONTENT" ]
}

@test "stale stamp is replaced" {
    echo stale >"$stamp"
    run "$deploy_dir/reset"
    [ "$status" -eq 0 ]
    [ "$(cat "$stamp")" = "$STAMP_CONTENT" ]
}

@test "busy 3 times then safe" {
    stub running
    stub deploycheck-results "2 2 2 0"
    run "$deploy_dir/reset"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Attempt 1 of 20: broker busy, tasks are running"* ]]
    [ "$(calls deploycheck)" -eq 4 ]
    assert_deploycheck_timeout_calls 4
    # Busy answers do not re-check the broker: the gate's ps and the one after up.
    [ "$(calls 'compose ps')" -eq 2 ]
    [ "$(calls 'compose stop')" -eq 1 ]
    [ "$(calls 'compose up')" -eq 1 ]
    [ -f "$stamp" ]
}

@test "busy 20 times: dies after 20 attempts without touching the containers" {
    stub running
    stub deploycheck-results 2
    printf '%s\n' "$STAMP_CONTENT" >"$stamp"
    run "$deploy_dir/reset"
    [ "$status" -eq 1 ]
    [ "$(calls deploycheck)" -eq 20 ]
    [[ "$output" == *"Broker still not safe to reset after 20 attempts: broker busy"* ]]
    [[ "$output" != *"Attempt 20 of 20"* ]]
    [ "$(calls 'compose stop')" -eq 0 ]
    [ "$(calls 'compose rm')" -eq 0 ]
    [ "$(calls 'compose up')" -eq 0 ]
    [ "$(cat "$stamp")" = "$STAMP_CONTENT" ]
}

@test "exit 1 retried then safe" {
    stub running
    stub deploycheck-results "1 1 0"
    run "$deploy_dir/reset"
    [ "$status" -eq 0 ]
    [ "$(calls deploycheck)" -eq 3 ]
    [[ "$output" == *"deploycheck could not tell whether tasks are running, or docker compose exec failed (exit 1)"* ]]
    [ "$(calls 'compose up')" -eq 1 ]
}

@test "exit 1 for all 20 attempts dies" {
    stub running
    stub deploycheck-results 1
    run "$deploy_dir/reset"
    [ "$status" -eq 1 ]
    [ "$(calls deploycheck)" -eq 20 ]
    [[ "$output" == *"after 20 attempts: deploycheck could not tell whether tasks are running, or docker compose exec failed (exit 1)"* ]]
    assert_containers_untouched
}

@test "docker exec failure retried like unknown" {
    stub running
    stub deploycheck-results "125 0"
    run "$deploy_dir/reset"
    [ "$status" -eq 0 ]
    [[ "$output" == *"docker compose exec (or timeout) failed with exit code 125"* ]]
    [ "$(calls deploycheck)" -eq 2 ]
    [ "$(calls 'compose up')" -eq 1 ]
}

@test "deploycheck timed out, then safe" {
    stub running
    stub deploycheck-results "124 0"
    run "$deploy_dir/reset"
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
    run "$deploy_dir/reset"
    [ "$status" -eq 0 ]
    [[ "$output" == *"deploycheck timed out after 30s"* ]]
    [ "$(calls deploycheck)" -eq 2 ]
    [ "$(calls 'compose up')" -eq 1 ]
}

@test "deploycheck timed out for all 20 attempts dies" {
    stub running
    stub deploycheck-results 124
    run "$deploy_dir/reset"
    [ "$status" -eq 1 ]
    [ "$(calls deploycheck)" -eq 20 ]
    assert_deploycheck_timeout_calls 20
    [[ "$output" == *"after 20 attempts: deploycheck timed out after 30s"* ]]
    assert_containers_untouched
}

@test "exec fails, then the broker is reported stopped: reset runs without retrying deploycheck" {
    stub running
    stub broker-stops-after-ps 1
    stub deploycheck-results 125
    run "$deploy_dir/reset"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Broker has stopped"* ]]
    [[ "$output" != *"Broker is safe to reset"* ]]
    [ "$(calls deploycheck)" -eq 1 ]
    [ "$(calls 'compose stop')" -eq 1 ]
    [ "$(calls 'compose up')" -eq 1 ]
    [ "$(cat "$stamp")" = "$STAMP_CONTENT" ]
}

@test "unknown on the last attempt, then the broker is reported stopped: reset runs" {
    stub running
    stub broker-stops-after-ps 20
    stub deploycheck-results 1
    run "$deploy_dir/reset"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Broker has stopped"* ]]
    [ "$(calls deploycheck)" -eq 20 ]
    [ "$(calls 'compose up')" -eq 1 ]
}

@test "stop fails" {
    stub stop-fails
    run "$deploy_dir/reset"
    [ "$status" -eq 1 ]
    [[ "$output" == *"docker compose stop failed"* ]]
    [ "$(docker_calls)" = "$(calls_through 'compose stop')" ]
    [ ! -f "$stamp" ]
}

@test "rm fails" {
    stub rm-fails
    run "$deploy_dir/reset"
    [ "$status" -eq 1 ]
    [[ "$output" == *"docker compose rm -f failed"* ]]
    [ "$(docker_calls)" = "$(calls_through 'compose rm -f')" ]
    [ ! -f "$stamp" ]
}

@test "up fails" {
    stub up-fails
    run "$deploy_dir/reset"
    [ "$status" -eq 1 ]
    [[ "$output" == *"docker compose up -d --remove-orphans failed"* ]]
    [ "$(docker_calls)" = "$(calls_through 'compose up -d --remove-orphans')" ]
    [ ! -f "$stamp" ]
}

@test "broker not running after up" {
    stub up-leaves-broker-stopped
    run "$deploy_dir/reset"
    [ "$status" -eq 1 ]
    [[ "$output" == *"The broker is not running after docker compose up -d --remove-orphans"* ]]
    [ "$(docker_calls)" = "$ALL_CALLS" ]
    [ ! -f "$stamp" ]
}

@test "stamp directory cannot be created" {
    rm -rf "$XDG_STATE_HOME"
    : >"$XDG_STATE_HOME"
    run "$deploy_dir/reset"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Could not create the stamp directory"* ]]
}

@test "stamp directory unwritable" {
    [ "$(id -u)" -ne 0 ] || skip "root can write to any directory"
    chmod 500 "$stamp_dir"
    run "$deploy_dir/reset"
    chmod 700 "$stamp_dir"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Could not create a temporary stamp file"* ]]
    [ ! -f "$stamp" ]
}

@test "sorting the image list fails" {
    override_command sort 'exit 1'
    run "$deploy_dir/reset"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Could not sort the image list"* ]]
    assert_containers_untouched
}

@test "working out the stamp directory fails" {
    real_dirname=$(command -v dirname)
    # Only the stamp path fails, so reset still finds its own directory.
    override_command dirname "case \"\$1\" in
    */deployed-images) exit 1 ;;
esac
exec '$real_dirname' \"\$@\""
    run "$deploy_dir/reset"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Could not work out the stamp directory"* ]]
    [ ! -f "$stamp" ]
}

@test "writing the temporary stamp fails: no stamp and no temporary file left" {
    # A temporary path in a directory that does not exist, so the write fails.
    override_command mktemp "printf '%s\\n' '$stamp_dir/missing/deployed-images.tmp'"
    run "$deploy_dir/reset"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Could not write the temporary stamp file"* ]]
    [ ! -f "$stamp" ]
    [ -z "$(find "$stamp_dir" -name 'deployed-images.*')" ]
}

@test "moving the temporary stamp into place fails: no stamp and no temporary file left" {
    override_command mv 'exit 1'
    run "$deploy_dir/reset"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Could not move the temporary stamp file into place"* ]]
    [ ! -f "$stamp" ]
    [ -z "$(find "$stamp_dir" -name 'deployed-images.*')" ]
}

@test "an update after a reset with unchanged images does nothing" {
    cp "$BATS_TEST_DIRNAME/../update" "$deploy_dir/update"
    run "$deploy_dir/reset"
    [ "$status" -eq 0 ]
    run "$deploy_dir/update"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Nothing to do"* ]]
    [ "$(calls deploycheck)" -eq 0 ]
    [ "$(calls 'compose up')" -eq 1 ]
}
