class Pulse < Formula
  desc "Menu bar app that shows Claude Code session progress"
  homepage "https://github.com/lcalmsky/pulse"
  url "https://github.com/lcalmsky/pulse/archive/refs/tags/v0.15.0.tar.gz"
  sha256 "cfa56f47ba1be214087b32dfca9bc8034a7d1efc7b85b1bc55b1712c3cd0d82e"
  head "https://github.com/lcalmsky/pulse.git", branch: "main"

  depends_on :macos

  def install
    ENV["SWIFT_BUILD_DISABLE_SANDBOX"] = "1"
    system "./scripts/bundle.sh", prefix
    bin.install_symlink prefix/"Pulse.app/Contents/MacOS/pulse"
    bin.install "scripts/pulse-page.sh" => "pulse-page"
  end

  def caveats
    <<~EOS
      If System Settings > Accessibility > Display > Reduce transparency is on,
      Pulse draws a solid background instead of glass.
    EOS
  end

  service do
    run [opt_prefix/"Pulse.app/Contents/MacOS/pulse"]
    keep_alive true
  end

  test do
    assert_match "pulse", shell_output("#{bin}/pulse --version")
  end
end
