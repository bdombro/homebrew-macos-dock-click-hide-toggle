set shell := ["zsh", "-eu", "-o", "pipefail", "-c"]
set positional-arguments

# List available tasks.
_:
    @just --list

# Build and sign the executable in build/bin.
build:
    bun ./scripts/build.ts

# Install the built executable as a local user service.
install:
    bun ./scripts/install.ts

# Remove the local user service, preserving its logs.
uninstall:
    bun ./scripts/install.ts --uninstall

# Prepare or publish a versioned Homebrew release.
release *args:
    bun ./scripts/release.ts "$@"

# Type-check the Bun maintenance scripts without emitting files.
scripts-typecheck:
    bun run tsc --noEmit
