--- !!! DO NOT EDIT OR RENAME !!!
PLUGIN = {}

--- Backend plugin name. Referenced from mise.toml as "src:<name>",
--- e.g.  [tools]  "src:stow" = "latest"
PLUGIN.name = "src"
PLUGIN.version = "0.1.0"
PLUGIN.homepage = "https://github.com/DoeringChristian/toolbox"
PLUGIN.license = "MIT"
PLUGIN.description = "mise backend that builds tools from source (the analog of the dotfiles' pixi ext/<name> recipes) — for tools with no binary backend, e.g. GNU stow, passage"

PLUGIN.notes = {
  "Each tool is a from-source recipe in registry.lua (fetch spec + build commands).",
  "Build is hermetic: make/perl come from conda-forge via `mise x` — no host toolchain.",
}
