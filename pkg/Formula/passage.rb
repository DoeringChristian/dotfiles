class Passage < Formula
  desc "Age-backed password store (a pass fork by FiloSottile)"
  homepage "https://github.com/FiloSottile/passage"
  head "https://github.com/FiloSottile/passage.git", branch: "main"
  # no tagged release -> head-only; install with:  brew install --HEAD passage

  depends_on "age"

  def install
    system "make", "install", "PREFIX=#{prefix}"
  end
end
