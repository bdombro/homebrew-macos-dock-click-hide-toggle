class MacosDockClickHideToggle < Formula
  desc "Click a frontmost application's Dock icon to hide it"
  homepage "https://github.com/bdombro/macos-dock-click-hide-toggle"
  url "https://github.com/bdombro/macos-dock-click-hide-toggle/releases/download/v0.1.0/macos-dock-click-hide-toggle-0.1.0-macos-arm64.tar.gz"
  version "0.1.0"
  sha256 "29153e830a2be426287c7f1566bc740f708ccb7c8f0b9f9b2d8aa0ed7d099f96"
  license "ISC"

  depends_on :macos
  depends_on arch: :arm64
  on_macos do
    depends_on macos: :ventura
  end

  def install
    bin.install "macos-dock-click-hide-toggle"
  end

  service do
    run [opt_bin/"macos-dock-click-hide-toggle", "start"]
    keep_alive successful_exit: false
    # Homebrew includes Aqua in its generated session types; use without sudo.
    working_dir var
    log_path var/"log/macos-dock-click-hide-toggle.log"
    error_log_path var/"log/macos-dock-click-hide-toggle.log"
  end

  test do
    assert_match "Usage:", shell_output("#{bin}/macos-dock-click-hide-toggle --help")
  end
end
