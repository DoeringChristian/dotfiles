class Zathura < Formula
  desc "Keyboard-driven document viewer"
  homepage "https://pwmt.org/projects/zathura/"
  url "https://github.com/pwmt/zathura/archive/refs/tags/2026.02.09.tar.gz"
  sha256 "ee890591608a79e75e9719054c4f29c4a611172484e93e43126651d3d5cd9477"
  license "Zlib"
  head "https://github.com/pwmt/zathura.git", branch: "develop"

  depends_on "cmake" => :build
  depends_on "meson" => :build
  depends_on "ninja" => :build
  depends_on "pkg-config" => :build
  depends_on "sphinx-doc" => :build
  depends_on "adwaita-icon-theme"
  depends_on "cairo"
  depends_on "desktop-file-utils"
  depends_on "gettext"
  depends_on "girara"
  depends_on "glib"
  depends_on "gtk+3"
  depends_on "intltool"
  depends_on "json-glib"
  depends_on "libmagic"
  depends_on "sqlite"

  uses_from_macos "python" => :build

  def install
    args = std_meson_args + %w[
      -Dsynctex=disabled
      -Dseccomp=auto
      -Dlandlock=auto
      -Dmanpages=auto
      -Dtests=disabled
    ]

    system "meson", "setup", "build", *args
    system "meson", "compile", "-C", "build"
    system "meson", "install", "-C", "build"
  end

  test do
    assert_match "zathura", shell_output("#{bin}/zathura --version")
  end
end
