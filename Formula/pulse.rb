class Pulse < Formula
  desc "Menu bar app that shows Claude Code session progress"
  homepage "https://github.com/lcalmsky/pulse"
  url "https://github.com/lcalmsky/pulse/archive/refs/tags/v0.4.1.tar.gz"
  sha256 "77c4d9a28b798ea854963e03f88b54e9efa838dcfbfbaced8120770bcc010fc0"
  head "https://github.com/lcalmsky/pulse.git", branch: "main"

  depends_on :macos

  def install
    ENV["SWIFT_BUILD_DISABLE_SANDBOX"] = "1"
    system "./scripts/bundle.sh", prefix
    bin.install_symlink prefix/"Pulse.app/Contents/MacOS/pulse"
  end

  service do
    run [opt_prefix/"Pulse.app/Contents/MacOS/pulse"]
    keep_alive true
  end

  test do
    assert_match "pulse", shell_output("#{bin}/pulse --version")
  end
end
