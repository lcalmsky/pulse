class DeadhdBar < Formula
  desc "macOS 메뉴 막대에서 Claude Code 세션 진행 상황을 보여 주는 앱"
  homepage "https://github.com/lcalmsky/deadhd-bar"
  head "https://github.com/lcalmsky/deadhd-bar.git", branch: "main"

  depends_on :macos

  def install
    system({ "SWIFT_BUILD_DISABLE_SANDBOX" => "1" }, "./scripts/bundle.sh", prefix)
    bin.install_symlink prefix/"DeadhdBar.app/Contents/MacOS/deadhd-bar"
  end

  service do
    run [opt_prefix/"DeadhdBar.app/Contents/MacOS/deadhd-bar"]
    keep_alive true
  end

  test do
    assert_match "deadhd-bar", shell_output("#{bin}/deadhd-bar --version")
  end
end
