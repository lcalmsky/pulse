class Pulse < Formula
  desc "Menu bar app that shows Claude Code session progress"
  homepage "https://github.com/lcalmsky/pulse"
  url "https://github.com/lcalmsky/pulse/archive/refs/tags/v0.2.0.tar.gz"
  sha256 "a036dc3fc3b986194e79109fe4166b1b6cbb59e1c6188741577518dad3f72cf1"
  head "https://github.com/lcalmsky/pulse.git", branch: "main"

  depends_on :macos

  def install
    system({ "SWIFT_BUILD_DISABLE_SANDBOX" => "1" }, "./scripts/bundle.sh", prefix)
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
