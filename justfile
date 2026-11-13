set shell := ["bash", "-eu", "-o", "pipefail", "-c"]
set positional-arguments

_:
    @just --list

build:
    ./scripts/build.sh

install:
    ./scripts/install.sh

uninstall:
    ./scripts/uninstall.sh

test:
    ./scripts/test.sh

release *args:
    ./scripts/release.sh "$@"
