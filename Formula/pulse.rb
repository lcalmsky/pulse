class Pulse < Formula
  desc "Menu bar app that shows Claude Code session progress"
  homepage "https://github.com/lcalmsky/pulse"
  url "https://github.com/lcalmsky/pulse/archive/refs/tags/v0.3.0.tar.gz"
  sha256 "0482fcc338f0666f359aaa660b639f111d831915ef930eab5be4caf0cef1a7f4"
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
