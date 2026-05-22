-- Tmux scrollback buffer config
vim.g.mapleader = ' '
vim.g.maplocalleader = ' '
vim.opt.termguicolors = true

-- Load catppuccin colorscheme
vim.opt.runtimepath:append(vim.fn.stdpath 'data' .. '/lazy/catppuccin')
local ok_cat, _ = pcall(vim.cmd.colorscheme, 'catppuccin-macchiato')
if not ok_cat then
  vim.api.nvim_set_hl(0, 'Normal', { bg = '#24273a', fg = '#cad3f5' })
end

-- Catppuccin Macchiato ANSI palette (matches kitty theme)
vim.g.terminal_color_0 = '#494d64'
vim.g.terminal_color_1 = '#ed8796'
vim.g.terminal_color_2 = '#a6da95'
vim.g.terminal_color_3 = '#eed49f'
vim.g.terminal_color_4 = '#8aadf4'
vim.g.terminal_color_5 = '#f5bde6'
vim.g.terminal_color_6 = '#8bd5ca'
vim.g.terminal_color_7 = '#b8c0e0'
vim.g.terminal_color_8 = '#5b6078'
vim.g.terminal_color_9 = '#ed8796'
vim.g.terminal_color_10 = '#a6da95'
vim.g.terminal_color_11 = '#eed49f'
vim.g.terminal_color_12 = '#8aadf4'
vim.g.terminal_color_13 = '#f5bde6'
vim.g.terminal_color_14 = '#8bd5ca'
vim.g.terminal_color_15 = '#a5adcb'

-- Clipboard sync to system
vim.opt.clipboard = 'unnamedplus'

-- Visual settings
vim.opt.swapfile = false
vim.opt.number = false
vim.opt.signcolumn = 'no'

-- Colorize ANSI escape sequences via baleia.nvim, then set read-only
vim.opt.runtimepath:append(vim.fn.stdpath 'data' .. '/lazy/baleia.nvim')
vim.api.nvim_create_autocmd('BufReadPost', {
  callback = function(args)
    local ok, baleia = pcall(require, 'baleia')
    if ok then
      local b = baleia.setup({ strip_ansi_codes = true })
      b.once(args.buf)
    end
    vim.defer_fn(function()
      vim.bo[args.buf].modifiable = false
      vim.bo[args.buf].readonly = true
    end, 1000)
  end,
})

-- better-escape.vim
vim.opt.runtimepath:append(vim.fn.stdpath 'data' .. '/lazy/better-escape.vim')
vim.g.better_escape_shortcut = { 'jk', 'jK', 'JK', 'Jk' }
vim.g.better_escape_interval = 1000

-- leap.nvim
vim.opt.runtimepath:append(vim.fn.stdpath 'data' .. '/lazy/leap.nvim')
local ok_leap, leap = pcall(require, 'leap')
if ok_leap then
  leap.setup {
    case_sensitive = false,
    relative_directions = true,
    labels = { 's', 'f', 'n', 'u', 't', 'r', 'j', 'k', 'l', 'o', 'd', 'w', 'e', 'h', 'm', 'v', 'g', 'c', '.', 'z' },
    safe_labels = { 's', 'f', 'n', 'u', 't', 'r' },
  }
  vim.keymap.set({ 'n', 'x', 'o' }, 's', '<Plug>(leap)')
  vim.keymap.set('n', 'S', '<Plug>(leap-backward)')
  vim.api.nvim_set_hl(0, 'LeapBackdrop', { link = 'Comment' })
end

-- yanky.nvim for clipboard
vim.opt.runtimepath:append(vim.fn.stdpath 'data' .. '/lazy/yanky.nvim')
local ok_yanky, yanky = pcall(require, 'yanky')
if ok_yanky then
  yanky.setup { system_clipboard = { sync_with_ring = true } }
  vim.keymap.set({ 'n', 'x' }, 'y', '<Plug>(YankyYank)', { silent = true })
  vim.keymap.set({ 'n', 'x' }, 'p', '<Plug>(YankyPutAfter)', { silent = true })
  vim.keymap.set({ 'n', 'x' }, 'P', '<Plug>(YankyPutBefore)', { silent = true })
end

-- Quit keybindings
vim.keymap.set('n', 'q', '<cmd>q!<cr>', { noremap = true, silent = true })
vim.keymap.set('n', 'i', '<cmd>q!<cr>', { noremap = true, silent = true })
vim.keymap.set('n', '<Esc>', '<cmd>q!<cr>', { noremap = true, silent = true })

-- Center cursor on screen (position set by +line from tmux-scrollback script)
vim.api.nvim_create_autocmd('VimEnter', {
  callback = function()
    vim.cmd 'normal! zz'
  end,
})
