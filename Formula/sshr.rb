class Sshr < Formula
  desc "Resilient SSH sessions with automatic reconnection"
  homepage "https://github.com/DoeringChristian/sshr"
  head "https://github.com/DoeringChristian/sshr.git", branch: "main"
  # no tagged release -> head-only; install with:  brew install --HEAD sshr
  depends_on "rust" => :build

  def install
    system "cargo", "install", *std_cargo_args
    (share/"sshr").install Dir["share/sshr/*"] if Dir.exist?("share/sshr")
  end
end
