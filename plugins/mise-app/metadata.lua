--- !!! DO NOT EDIT OR RENAME !!!
PLUGIN = {}

--- Backend plugin name. Referenced from mise.toml as "app:<name>",
--- e.g.  [tools]  "app:kitty" = "0.47.4"
PLUGIN.name = "app"
PLUGIN.version = "0.1.0"
PLUGIN.homepage = "https://github.com/DoeringChristian/toolbox"
PLUGIN.license = "MIT"
PLUGIN.description = "mise backend that installs GUI apps from sha256-pinned official prebuilt binaries (.dmg/.txz/AppImage), the mise analog of the dotfiles' pixi ext/<name> recipes"

PLUGIN.notes = {
  "Each app is a sha256-pinned binary reference declared in registry.lua.",
  "Only the version recorded in registry.lua is installable (it carries the checksums).",
  "Creates a desktop launcher (.app shim on macOS / .desktop on Linux); set",
  "MISE_APP_NO_LAUNCHER=1 to skip, or MISE_APP_LAUNCHER_DIR to relocate it.",
}
