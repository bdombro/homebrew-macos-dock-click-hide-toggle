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

# Switch from the local tap to the explicit public repository; leave stopped.
install-production: uninstall
    brew tap '{{tap}}' 'https://github.com/bdombro/macos-dock-click-hide-toggle.git'
    HOMEBREW_NO_INSTALL_CLEANUP=1 brew install --formula '{{formula}}'

# Alias for quick local rebuild/replacement.
reinstall: reinstall-local

# Stop service, rebuild and replace the Homebrew executable (install-local first).
reinstall-local: _guard-tap
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
uninstall: _guard-tap
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

# Refuse unknown tap paths before any destructive Homebrew operation.
[private]
_guard-tap:
    #!/bin/zsh
    set -eu -o pipefail
    tap_dir='{{tap_path}}'
    if [[ -L "$tap_dir" ]]; then
      [[ -d "$tap_dir" ]] || { print -u2 'Refusing dangling tap symlink.'; exit 1; }
      target="$(cd -P "$tap_dir" && pwd -P)"
      source="$(cd -P '{{justfile_directory()}}' && pwd -P)"
      [[ "$target" == "$source" ]] || { print -u2 'Refusing tap symlink to another checkout.'; exit 1; }
    elif [[ -e "$tap_dir" ]]; then
      [[ -d "$tap_dir" ]] || { print -u2 'Refusing non-directory tap path.'; exit 1; }
      expected="$(cd -P '{{tap_parent}}' && pwd -P)/homebrew-{{name}}"
      top="$(git -C "$tap_dir" rev-parse --show-toplevel)"
      physical_top="$(cd -P "$top" && pwd -P)"
      [[ "$physical_top" == "$expected" ]] || { print -u2 'Refusing tap path that is not its own Git checkout.'; exit 1; }
      origin="$(git -C "$tap_dir" remote get-url origin)"
      case "$origin" in
        'https://github.com/bdombro/macos-dock-click-hide-toggle'|'https://github.com/bdombro/macos-dock-click-hide-toggle.git'|'git@github.com:bdombro/macos-dock-click-hide-toggle.git') ;;
        *) print -u2 'Refusing tap checkout with an unauthorized origin.'; exit 1 ;;
      esac
      dirty="$(git -C "$tap_dir" status --porcelain --untracked-files=all)"
      [[ -z "$dirty" ]] || { print -u2 'Refusing to remove a modified tap checkout; preserve its edits first.'; exit 1; }
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


