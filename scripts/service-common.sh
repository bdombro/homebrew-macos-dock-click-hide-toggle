#!/usr/bin/env bash
# Shared by the local installer and uninstaller; never invoked by Homebrew.
name=macos-dock-click-hide-toggle
label="local.$name"
installation="$HOME/.local/share/$name"
executable="$installation/$name"
agents="$HOME/Library/LaunchAgents"
plist="$agents/$label.plist"
log="$installation/daemon.log"
domain="gui/$(id -u)"
service="$domain/$label"

require_user() {
  if [[ "$(id -u)" -eq 0 ]]; then
    echo "Run this command as your logged-in user, without sudo." >&2
    exit 1
  fi
}

unload() {
  local output status
  if output="$(launchctl print "$service" 2>&1)"; then
    launchctl bootout "$service"
  else
    status=$?
    if [[ "$status" -ne 113 ]]; then
      printf 'Cannot inspect %s (status %s):\n%s\n' "$service" "$status" "$output" >&2
      return "$status"
    fi
  fi
}
