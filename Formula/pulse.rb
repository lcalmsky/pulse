class Pulse < Formula
  desc "Menu bar app that shows Claude Code session progress"
  homepage "https://github.com/lcalmsky/pulse"
  url "https://github.com/lcalmsky/pulse/archive/refs/tags/v0.4.0.tar.gz"
  sha256 "142bbf45b5610ecc5f6e2e4413c84d9ffd89d5ab995843d694ca98d71234d846"
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
