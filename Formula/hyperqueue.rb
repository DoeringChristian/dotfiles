class Hyperqueue < Formula
  desc "Scheduler for sub-node tasks on HPC clusters (prebuilt `hq`)"
  homepage "https://github.com/It4innovations/hyperqueue"
  version "0.26.2"
  license "MIT"
  # Linux only: the upstream release binary needs just the system libc/libstdc++,
  # whereas building it pulls bindgen -> Homebrew's libclang, which needs a newer
  # glibc than older hosts (Ubuntu 22.04) have. macOS: the Brewfile's cargo entry.

  on_linux do
    on_intel do
      url "https://github.com/It4innovations/hyperqueue/releases/download/v0.26.2/hq-v0.26.2-linux-x64.tar.gz"
      sha256 "e15dae9113e1a307a97a66bfe90f74f78c6016239436b5d9f1e4efec480e84b5"
    end
    on_arm do
      url "https://github.com/It4innovations/hyperqueue/releases/download/v0.26.2/hq-v0.26.2-linux-arm64-linux.tar.gz"
      sha256 "84643db82f891ca86c7614f06f9d74d2537db660e0f830ced9ad56f86a5523eb"
    end
  end

  depends_on :linux

  def install
    bin.install "hq"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/hq --version")
  end
end
