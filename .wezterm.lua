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

config.font = wezterm.font 'FiraCode Nerd Font'
config.font_size = 10.

config.hide_tab_bar_if_only_one_tab = true
config.use_fancy_tab_bar = false
config.tab_bar_at_bottom = true

config.window_padding = {
    top = 0,
    bottom = 0,
    left = 0,
    right = 0,
}


-- Spawn a fish shell in login mode
config.default_prog = { 'fish' }

local a = wezterm.action

local function is_inside_vim(pane)
    local tty = pane:get_tty_name()
    if tty == nil then return true end

    local success, stdout, stderr = wezterm.run_child_process
        { 'sh', '-c',
            'ps -o state= -o comm= -t' .. wezterm.shell_quote_arg(tty) .. ' | ' ..
            'grep -iqE \'^[^TXZ ]+ +(\\S+\\/)?g?(view|l?n?vim?x?)(diff)?$\'' }


    return success
end

local function is_outside_vim(pane) return not is_inside_vim(pane) end

local function bind_if(cond, key, mods, action)
    local function callback(win, pane)
        if cond(pane) then
            win:perform_action(action, pane)
        else
            win:perform_action(a.SendKey({ key = key, mods = mods }), pane)
        end
    end

    return { key = key, mods = mods, action = wezterm.action_callback(callback) }
end

config.leader = { key = " ", mods = "CTRL", timeout_milliseconds = 1000 }
config.keys = {
    {
        key = "n",
        mods = "ALT",
        action = a.SpawnTab 'CurrentPaneDomain',
    },
    {
        key = "k",
        mods = "ALT",
        action = a.SplitPane { direction = 'Up', command = { domain = 'CurrentPaneDomain' } },
    },
    {
        key = "j",
        mods = "ALT",
        action = a.SplitPane { direction = 'Down', command = { domain = 'CurrentPaneDomain' } },
    },
    {
        key = "l",
        mods = "ALT",
        action = a.ActivateTabRelative(1),
    },
    {
        key = "h",
        mods = "ALT",
        action = a.ActivateTabRelative(-1),
    },
    {
        key = "l",
        mods = "LEADER",
        action = a.SplitPane { direction = "Right", command = { domain = 'CurrentPaneDomain' } },
    },
    {
        key = "h",
        mods = "LEADER",
        action = a.SplitPane { direction = "Left", command = { domain = 'CurrentPaneDomain' } },
    },
    {
        key = "q",
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
    bind_if(is_outside_vim, 'h', 'CTRL', a.ActivatePaneDirection('Left')),
    bind_if(is_outside_vim, 'l', 'CTRL', a.ActivatePaneDirection('Right')),
    bind_if(is_outside_vim, 'j', 'CTRL', a.ActivatePaneDirection('Down')),
    bind_if(is_outside_vim, 'k', 'CTRL', a.ActivatePaneDirection('Up')),
    { key = 'd', mods = 'ALT',       action = a.ScrollByPage(1) },
    { key = 'u', mods = 'ALT',       action = a.ScrollByPage(-1) },
    { key = 'j', mods = 'ALT|SHIFT', action = a.ScrollByLine(1) },
    { key = 'k', mods = 'ALT|SHIFT', action = a.ScrollByLine(-1) },
    { key = 'k', mods = 'LEADER',    action = a.ActivateCopyMode },
    { key = ' ', mods = 'LEADER',    action = a.ActivateCopyMode },
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
