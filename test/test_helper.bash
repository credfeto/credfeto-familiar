# shellcheck shell=bash
# Scaffolding shared by the bats suites in test/, loaded with `load test_helper`.
# Each suite copies the script under test into a deploy directory under the
# per-test temporary directory and runs it against the stubs in test/stubs,
# never the real commands.

# Copies the named script ($2) into the given deploy directory ($1), starts an
# empty log of the calls made to the named stub command ($3), and puts the
# stubs first on PATH. Each suite assigns its own deploy_dir and passes it in,
# so shellcheck can see where the variable it uses is assigned.
setup_deploy_dir() {
    mkdir -p "$1"
    cp "$BATS_TEST_DIRNAME/../$2" "$1/$2"

    export STUB_DIR="$BATS_TEST_TMPDIR/stub"
    mkdir -p "$STUB_DIR"
    : >"$STUB_DIR/$3-calls"

    PATH="$BATS_TEST_DIRNAME/stubs:$PATH"

    # The scripts drive docker and sudo, so refuse to run any test unless the
    # stub shadows the real command.
    require_stub "$3"
}

# Fails unless the named command resolves to its stub in test/stubs.
require_stub() {
    resolved=$(command -v "$1" || true)
    if [ "$resolved" != "$BATS_TEST_DIRNAME/stubs/$1" ]; then
        printf '%s resolves to "%s", not the stub in %s/stubs\n' "$1" "$resolved" "$BATS_TEST_DIRNAME" >&2
        return 1
    fi
}

# setup_deploy_dir for a script that drives the stub docker, with the empty
# docker-compose.yaml and .env every such script checks for.
setup_docker_deploy_dir() {
    setup_deploy_dir "$1" "$2" docker
    : >"$1/docker-compose.yaml"
    : >"$1/.env"
}

# Sets a stub behaviour: the file's name selects it, and its content (if any)
# is the behaviour's argument.
stub() {
    printf '%s' "${2:-}" >"$STUB_DIR/$1"
}

docker_calls() {
    cat "$STUB_DIR/docker-calls"
}

# Makes a directory ($1) holding only dirname and the stub docker, so a script
# run with it as PATH gets past its docker check but finds no timeout.
make_no_timeout_dir() {
    mkdir -p "$1"
    ln -s "$(command -v dirname)" "$1/dirname"
    ln -s "$BATS_TEST_DIRNAME/stubs/docker" "$1/docker"
}

# Runs the given script ($2) with PATH set to only the given directory ($1).
run_with_path() {
    saved_path="$PATH"
    PATH="$1"
    run "$2"
    PATH="$saved_path"
}
