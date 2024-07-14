-- Pull in the wezterm API
local wezterm = require 'wezterm'

-- This table will hold the configuration.
local config = {}

-- In newer versions of wezterm, use the config_builder which will
-- help provide clearer error messages
if wezterm.config_builder then
    config = wezterm.config_builder()
end

-- This is where you actually apply your config choices

-- For example, changing the color scheme:
-- config.color_scheme = 'GruvboxDarkHard'
config.color_scheme = "Catppuccin Mocha"

-- config.enable_wayland = false
-- config.front_end = 'WebGpu'

-- config.default_cursor_style = 'BlinkingBar'

config.font = wezterm.font 'FiraCode Nerd Font'
config.font_size = 10.

config.hide_tab_bar_if_only_one_tab = false
config.use_fancy_tab_bar = false
config.tab_bar_at_bottom = true

config.window_padding = {
    top = 0,
    bottom = 0,
    left = 0,
    right = 0,
}
config.front_end = "WebGpu"


-- Spawn a fish shell in login mode
config.default_prog = { "fish" }

local a = wezterm.action

config.leader = { key = " ", mods = "CTRL", timeout_milliseconds = 1000 }
config.keys = {
    -- panes: navigation
    { key = 'k', mods = "ALT", action = a.ActivatePaneDirection('Up') },
    { key = 'j', mods = "ALT", action = a.ActivatePaneDirection('Down') },
    { key = 'h', mods = "ALT", action = a.ActivatePaneDirection('Left') },
    { key = 'l', mods = "ALT", action = a.ActivatePaneDirection('Right') },

    {
        key = "x",
        mods = "ALT",
        action = a.CloseCurrentPane { confirm = false },
    },
    {
        key = "-",
        mods = "ALT",
        action = a.DecreaseFontSize,
    },
    {
        key = "=",
        mods = "ALT",
        action = a.IncreaseFontSize,
    },

    { key = 'd', mods = 'ALT',    action = a.ScrollByPage(1) },
    { key = 'u', mods = 'ALT',    action = a.ScrollByPage(-1) },
    { key = ' ', mods = 'LEADER', action = a.ActivateCopyMode },

    { key = ":", mods = "ALT",    action = a.ActivateCommandPalette },
}


local copy_mode = nil
if wezterm.gui then
    copy_mode = wezterm.gui.default_key_tables().copy_mode
    table.insert(
        copy_mode,
        { key = 'i', mods = 'NONE', action = a.CopyMode 'Close' }
    )
end
config.key_tables = {
    copy_mode = copy_mode,
}

-- and finally, return the configuration to wezterm
return config
