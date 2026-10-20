class DeadhdBar < Formula
  desc "macOS 메뉴 막대에서 deadhd 세션 진행 상황을 보여 주는 앱"
  homepage "https://github.com/lcalmsky/deadhd-bar"
  head "https://github.com/lcalmsky/deadhd-bar.git", branch: "main"

  depends_on :macos

  def install
    system "swift", "build", "-c", "release", "--disable-sandbox"
    bin.install ".build/release/deadhd-bar"
  end

  service do
    run [opt_bin/"deadhd-bar"]
    keep_alive true
  end

  test do
    assert_match "deadhd-bar", shell_output("#{bin}/deadhd-bar --version")
  end
end
