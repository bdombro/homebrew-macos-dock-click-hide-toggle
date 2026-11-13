class MacosDockClickHideToggle < Formula
  desc "Click a frontmost application's Dock icon to hide it"
  homepage "https://github.com/bdombro/macos-dock-click-hide-toggle"
  url "https://github.com/bdombro/macos-dock-click-hide-toggle/releases/download/v0.1.2/macos-dock-click-hide-toggle-0.1.2-macos-arm64.tar.gz"
  sha256 "8a09ab8ff9b14dede80e3ac3096b736682687cdd90b613c98427ac899767a3d9"
  license "ISC"

  depends_on arch: :arm64
  depends_on :macos
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
    assert_equal version.to_s, shell_output("#{bin}/macos-dock-click-hide-toggle --version").strip
  end
end
