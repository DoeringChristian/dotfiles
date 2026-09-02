class ZathuraPdfMupdf < Formula
  desc "MuPDF backend plugin for zathura"
  homepage "https://pwmt.org/projects/zathura-pdf-mupdf/"
  url "https://github.com/pwmt/zathura-pdf-mupdf/archive/refs/tags/2026.02.03.tar.gz"
  sha256 "0e718162054a0cd673bfa654f5d52ae03428665d154b00c897abf7014375bfff"
  license "Zlib"

  depends_on "cmake" => :build
  depends_on "meson" => :build
  depends_on "ninja" => :build
  depends_on "pkg-config" => :build
  depends_on "cairo"
  depends_on "girara"
  depends_on "glib"
  depends_on "mupdf"
  depends_on "doeringc/local/zathura"

  def install
    args = std_meson_args + [
      "-Dplugindir=#{lib}/zathura",
      "-Dtests=disabled",
      "-Dpdf=enabled",
    ]

    system "meson", "setup", "build", *args
    system "meson", "compile", "-C", "build"
    system "meson", "install", "-C", "build"
  end

  def post_install
    zathura_plugin_dir = Formula["doeringc/local/zathura"].opt_lib/"zathura"
    zathura_plugin_dir.mkpath
    Dir[lib/"zathura"/shared_library("libpdf-mupdf")].each do |plugin|
      ln_sf plugin, zathura_plugin_dir/File.basename(plugin)
    end
  end

  def caveats
    <<~EOS
      This plugin is linked into Zathura's plugin directory by post_install.
      If PDFs do not open after upgrading, rerun:
        brew postinstall doeringc/local/zathura-pdf-mupdf
    EOS
  end

  test do
    assert_path_exists lib/"zathura"/shared_library("libpdf-mupdf")
  end
end
