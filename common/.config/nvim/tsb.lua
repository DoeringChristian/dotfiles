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

-- Visual settings
vim.opt.swapfile = false
vim.opt.number = false
vim.opt.signcolumn = 'no'

-- Set read-only after buffer loads
vim.api.nvim_create_autocmd('BufReadPost', {
  callback = function()
    vim.opt_local.readonly = true
    vim.opt_local.modifiable = false
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
  leap.set_default_keymaps()
  leap.setup {
    case_sensitive = false,
    relative_directions = true,
    labels = { 's', 'f', 'n', 'u', 't', 'r', 'j', 'k', 'l', 'o', 'd', 'w', 'e', 'h', 'm', 'v', 'g', 'c', '.', 'z' },
    safe_labels = { 's', 'f', 'n', 'u', 't', 'r' },
  }
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

-- Scroll to bottom on open
vim.api.nvim_create_autocmd('VimEnter', {
  callback = function()
    vim.cmd 'normal! G'
  end,
})
