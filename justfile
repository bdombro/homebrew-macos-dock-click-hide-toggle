# Homebrew tap-from-repo workflow, adapted from argsbarg/examples/homebrew.
set shell := ["zsh", "-eu", "-o", "pipefail", "-c"]
set positional-arguments

export PATH := justfile_directory() + "/node_modules/.bin:" + env_var("PATH")
tap := "bdombro/macos-dock-click-hide-toggle"
name := "macos-dock-click-hide-toggle"
formula := tap + "/" + name
brew_prefix := `brew --prefix`
tap_parent := brew_prefix + "/Library/Taps/bdombro"
tap_path := tap_parent + "/homebrew-" + name

# List available tasks.
_:
    @just --list

# Build and sign arm64/macOS 13+ output in build/bin; never install.
build:
    bun scripts/build.ts

# Alias for the local Homebrew installation.
install: install-local

# Remove the old keg/tap, build, stage a local formula and install; leave stopped.
install-local: uninstall build
    #!/bin/zsh
    set -eu -o pipefail
    mkdir -p '{{tap_parent}}'
    [[ ! -e '{{tap_path}}' && ! -L '{{tap_path}}' ]] || { print -u2 'Refusing to create source tap: path already exists.'; exit 1; }
    ln -s '{{justfile_directory()}}' '{{tap_path}}'
    bun scripts/dev-formula.ts install
    trap 'bun scripts/dev-formula.ts reset' EXIT
    HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1 brew install --formula '{{formula}}'

# Switch from the local tap to the public repository; leave stopped.
install-production: uninstall
    brew tap '{{tap}}'
    HOMEBREW_NO_INSTALL_CLEANUP=1 brew install --formula '{{formula}}'

# Alias for quick local rebuild/replacement.
reinstall: reinstall-local

# Stop service, rebuild and replace the Homebrew executable (install-local first).
reinstall-local:
    #!/bin/zsh
    set -eu -o pipefail
    [[ -L '{{tap_path}}' && "$(readlink '{{tap_path}}')" == '{{justfile_directory()}}' ]] || { print -u2 'Run just install-local first.'; exit 1; }
    installed="$(brew list --formula --full-name)"
    if ! print -r -- "$installed" | grep -Fx -e '{{formula}}' -e '{{name}}' >/dev/null; then
      print -u2 'Run just install-local first.'
      exit 1
    fi
    brew services stop '{{formula}}'
    just build
    destination="$(brew --prefix '{{formula}}')/bin/{{name}}"
    install -m 755 'build/bin/{{name}}' "$destination"

# Remove the Homebrew keg and this tap only; keep logs and never start services.
uninstall:
    #!/bin/zsh
    set -eu -o pipefail
    installed="$(brew list --formula --full-name)"
    if print -r -- "$installed" | grep -Fx -e '{{formula}}' -e '{{name}}' >/dev/null; then
      brew services stop '{{formula}}'
      HOMEBREW_NO_INSTALL_CLEANUP=1 brew uninstall --formula '{{formula}}'
    fi
    taps="$(brew tap)"
    if print -r -- "$taps" | grep -Fx '{{tap}}' >/dev/null; then
      brew untap '{{tap}}'
    fi

# Install the checked-in public release formula via this checkout and test (stopped).
test-release: uninstall
    #!/bin/zsh
    set -eu -o pipefail
    mkdir -p '{{tap_parent}}'
    [[ ! -e '{{tap_path}}' && ! -L '{{tap_path}}' ]] || { print -u2 'Refusing to create source tap: path already exists.'; exit 1; }
    ln -s '{{justfile_directory()}}' '{{tap_path}}'
    HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1 brew install --formula '{{formula}}'
    brew test '{{formula}}'

# Bump, build and publish; --dry-run previews, --prepare only writes local files.
release *args:
    bun scripts/release.ts "$@"


