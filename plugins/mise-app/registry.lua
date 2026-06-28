-- registry.lua -- THE GUI-app list for the `app:` backend.
--
-- Streamlined model: NO hand-maintained versions or checksums. Each app declares
--   * repo  -- GitHub <owner>/<name>; versions are resolved live from its
--              releases feed, so `"app:kitty" = "latest"` tracks upstream and a
--              pinned `"app:kitty" = "0.47.4"` just has to exist as a release.
--   * platforms[<os>-<arch>].url -- a download-URL TEMPLATE with {version}
--              (and the asset naming baked in). The file is fetched straight from
--              GitHub over HTTPS at install time -- no sha256 to record or bump.
--
-- Integrity rests on HTTPS to GitHub (same trust model as `mise use github:...`
-- or `curl | sh`). To re-introduce byte-pinning later, add a `sha256` next to a
-- url and have backend_install verify it; absence just means "trust HTTPS".
--
-- format:
--   "dmg"      -- macOS disk image; mount with hdiutil, lift out <app> bundle.
--   "txz"      -- tar.xz extracting to bin/ lib/ share/ at top level.
--   "appimage" -- self-extracting AppImage (--appimage-extract).
-- binpaths/icon are relative to the .app bundle (dmg), the extract root (txz),
-- or located inside the AppDir defensively (appimage).

return {
  kitty = {
    repo = "kovidgoyal/kitty",
    bins = { "kitty", "kitten" },
    launcher = {
      display = "kitty",
      bundle_id = "net.kovidgoyal.kitty",
      description = "Fast, feature-rich, GPU-based terminal emulator",
      categories = "System;TerminalEmulator;",
      wm_class = "kitty",
      exec = "kitty",
    },
    platforms = {
      -- macOS ships a single universal .dmg for both arches.
      ["darwin-arm64"] = {
        url = "https://github.com/kovidgoyal/kitty/releases/download/v{version}/kitty-{version}.dmg",
        format = "dmg", app = "kitty.app",
        binpaths = { kitty = "Contents/MacOS/kitty", kitten = "Contents/MacOS/kitten" },
        icon = "Contents/Resources/kitty.icns",
      },
      ["darwin-amd64"] = {
        url = "https://github.com/kovidgoyal/kitty/releases/download/v{version}/kitty-{version}.dmg",
        format = "dmg", app = "kitty.app",
        binpaths = { kitty = "Contents/MacOS/kitty", kitten = "Contents/MacOS/kitten" },
        icon = "Contents/Resources/kitty.icns",
      },
      ["linux-amd64"] = {
        url = "https://github.com/kovidgoyal/kitty/releases/download/v{version}/kitty-{version}-x86_64.txz",
        format = "txz",
        binpaths = { kitty = "bin/kitty", kitten = "bin/kitten" },
        icon = "share/icons/hicolor/256x256/apps/kitty.png",
      },
      ["linux-arm64"] = {
        url = "https://github.com/kovidgoyal/kitty/releases/download/v{version}/kitty-{version}-arm64.txz",
        format = "txz",
        binpaths = { kitty = "bin/kitty", kitten = "bin/kitten" },
        icon = "share/icons/hicolor/256x256/apps/kitty.png",
      },
    },
  },

  tev = {
    repo = "Tom94/tev",
    bins = { "tev" },
    launcher = {
      display = "tev",
      bundle_id = "org.tom94.tev",
      description = "High dynamic range (HDR) image viewer",
      categories = "Graphics;Viewer;RasterGraphics;",
      wm_class = "tev",
      exec = "tev",
    },
    platforms = {
      ["darwin-arm64"] = {
        url = "https://github.com/Tom94/tev/releases/download/v{version}/tev.dmg",
        format = "dmg", app = "tev.app",
        binpaths = { tev = "Contents/MacOS/tev" },
        icon = "Contents/Resources/icon.icns",
      },
      ["darwin-amd64"] = {
        url = "https://github.com/Tom94/tev/releases/download/v{version}/tev-intel.dmg",
        format = "dmg", app = "tev.app",
        binpaths = { tev = "Contents/MacOS/tev" },
        icon = "Contents/Resources/icon.icns",
      },
      ["linux-amd64"] = {
        url = "https://github.com/Tom94/tev/releases/download/v{version}/tev.appimage",
        format = "appimage",
        binpaths = { tev = "tev" },
        icon = "tev.png",
      },
      ["linux-arm64"] = {
        url = "https://github.com/Tom94/tev/releases/download/v{version}/tev-arm.appimage",
        format = "appimage",
        binpaths = { tev = "tev" },
        icon = "tev.png",
      },
    },
  },
}
