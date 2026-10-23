class Pulse < Formula
  desc "Menu bar app that shows Claude Code session progress"
  homepage "https://github.com/lcalmsky/pulse"
  url "https://github.com/lcalmsky/pulse/archive/refs/tags/v0.5.2.tar.gz"
  sha256 "575b5666df6c71fb1b5430686419a870d273fb9c413c7b66a43f4353d21c3f64"
  head "https://github.com/lcalmsky/pulse.git", branch: "main"

  depends_on :macos

  def install
    ENV["SWIFT_BUILD_DISABLE_SANDBOX"] = "1"
    system "./scripts/bundle.sh", prefix
    bin.install_symlink prefix/"Pulse.app/Contents/MacOS/pulse"
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
