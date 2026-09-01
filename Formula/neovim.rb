class Neovim < Formula
  desc "Ambitious Vim-fork focused on extensibility and agility"
  homepage "https://neovim.io/"
  license "Apache-2.0"
  head "https://github.com/neovim/neovim.git", branch: "master"

  depends_on "cmake" => :build
  depends_on "gettext" => :build
  depends_on "libuv"
  depends_on "lpeg"
  depends_on "luajit"
  depends_on "luv"
  depends_on "tree-sitter"
  depends_on "unibilium"
  depends_on "utf8proc"

  on_macos do
    depends_on "gettext"
  end

  on_linux do
    # Keep the source build on Homebrew's libc toolchain. Without this explicit
    # dependency CMake can find Ubuntu's /usr/include/libintl.h while Homebrew's
    # GCC injects Homebrew glibc headers, producing an incompatible mixed sysroot.
    depends_on "glibc"
  end

  def install
    # HEAD has no fixed parser resources. Derive the versions and checksums from
    # the dependency manifest in the checked-out Neovim revision, as core does.
    cmake_deps = (buildpath/"cmake.deps/deps.txt").read.lines
    cmake_deps.each do |line|
      next unless line.match?(/TREESITTER_[^_]+_URL/)

      parser, parser_url = line.split
      parser_name = parser.delete_suffix("_URL")
      parser_sha256 = cmake_deps.find { |candidate| candidate.include?("#{parser_name}_SHA256") }.split.last
      parser_name = parser_name.downcase.tr("_", "-")

      resource parser_name do
        url parser_url
        sha256 parser_sha256
      end
    end

    resources.each do |resource|
      source_directory = buildpath/"deps-build/build/src"/resource.name
      build_directory = buildpath/"deps-build/build"/resource.name
      parser_name = resource.name.split("-").last
      cmakelists = (parser_name == "markdown") ? "MarkdownParserCMakeLists.txt" : "TreesitterParserCMakeLists.txt"

      resource.stage(source_directory)
      cp buildpath/"cmake.deps/cmake"/cmakelists, source_directory/"CMakeLists.txt"

      system "cmake", "-S", source_directory, "-B", build_directory,
             "-DPARSERLANG=#{parser_name}", *std_cmake_args
      system "cmake", "--build", build_directory
      system "cmake", "--install", build_directory
    end

    inreplace "src/nvim/os/stdpaths.c" do |s|
      s.gsub! "/etc/xdg/", "#{etc}/xdg/:\\0"
      if HOMEBREW_PREFIX.to_s != HOMEBREW_DEFAULT_PREFIX
        s.gsub! "/usr/local/share/:/usr/share/", "#{HOMEBREW_PREFIX}/share/:\\0"
      end
    end

    inreplace "cmake/GenerateVersion.cmake", "--dirty", "--dirty=-Homebrew"

    args = [
      "-DLUV_LIBRARY=#{formula_opt_lib("luv")/shared_library("libluv")}",
      "-DLIBUV_LIBRARY=#{formula_opt_lib("libuv")/shared_library("libuv")}",
      "-DLPEG_LIBRARY=#{formula_opt_lib("lpeg")/shared_library("liblpeg")}",
    ]
    if OS.linux?
      # Neovim's FindLibintl otherwise selects /usr/include on glibc systems.
      # Pinning this cache entry prevents host and Homebrew glibc headers from
      # being combined in one GCC invocation.
      args << "-DLIBINTL_INCLUDE_DIR=#{formula_opt_include("glibc")}"
    end

    system "cmake", "-S", ".", "-B", "build", *args, *std_cmake_args
    system "cmake", "--build", "build"
    system "cmake", "--install", "build"
  end

  test do
    refute_match "dirty", shell_output("#{bin}/nvim --version")
  end
end
