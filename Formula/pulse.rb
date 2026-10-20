class Pulse < Formula
  desc "macOS 메뉴 막대에서 Claude Code 세션 진행 상황을 보여 주는 앱"
  homepage "https://github.com/lcalmsky/pulse"
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
