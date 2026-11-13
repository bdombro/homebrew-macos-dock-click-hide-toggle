set shell := ["zsh", "-eu", "-o", "pipefail", "-c"]
set positional-arguments

# List available tasks.
_:
    @just --list

# Build and sign the executable in build/bin.
build:
    python3 ./scripts/build.py

# Install the built executable as a local user service.
install:
    python3 ./scripts/install.py

# Remove the local user service, preserving its logs.
uninstall:
    python3 ./scripts/install.py --uninstall

# Prepare or publish a versioned Homebrew release.
release *args:
    python3 ./scripts/release.py "$@"
