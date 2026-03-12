-- Core settings (match .vimrc)
vim.opt.wrap = true
vim.opt.tabstop = 4
vim.opt.shiftwidth = 4
vim.opt.autoindent = true
vim.opt.smartindent = true
vim.opt.number = false
vim.opt.foldmethod = "marker"
vim.opt.hidden = true
vim.opt.winminheight = 0
vim.opt.background = "dark"
vim.opt.showmode = true
vim.opt.termguicolors = true
vim.opt.signcolumn = "yes"
vim.opt.updatetime = 250
vim.opt.completeopt = { "menu", "menuone", "noselect" }

vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- Split navigation (Ctrl-HJKL)
vim.keymap.set("n", "<C-J>", "<C-W>j<C-W>_")
vim.keymap.set("n", "<C-K>", "<C-W>k<C-W>_")
vim.keymap.set("n", "<C-H>", "<C-W>h<C-W>|")
vim.keymap.set("n", "<C-L>", "<C-W>l<C-W>|")

-- Toggle dark/light background
vim.keymap.set("n", "<F9>", ":set bg=dark<CR>")
vim.keymap.set("n", "<F10>", ":set bg=light<CR>")

-- Shift-Space to exit insert mode
vim.keymap.set("i", "<S-Space>", "<Esc>")

-- Toggle paste mode
vim.keymap.set("n", "<F2>", ":set invpaste paste?<CR>")

-- Toggle whitespace visibility
vim.keymap.set("n", "<F5>", ":set listchars=eol:¬,tab:>·,trail:~,extends:>,precedes:<,space:␣ list!<CR>")

-- Save shortcut
vim.keymap.set("n", "<Leader>w", ":w<CR>")

-- Format shortcut: \f
vim.keymap.set("n", "\\f", function()
	local has_lsp = next(vim.lsp.get_clients({ bufnr = 0 })) ~= nil
	if has_lsp then
		vim.lsp.buf.format({ async = true })
	else
		vim.cmd("normal! gg=G")
	end
end, { desc = "Format buffer" })
vim.keymap.set("v", "\\f", "=", { desc = "Format selection" })

-- YAML 2-space indent
vim.api.nvim_create_autocmd("FileType", {
	pattern = { "yaml", "yml" },
	callback = function()
		vim.opt_local.tabstop = 2
		vim.opt_local.shiftwidth = 2
		vim.opt_local.expandtab = true
	end,
})

-- Bootstrap lazy.nvim
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.uv.fs_stat(lazypath) then
	vim.fn.system({
		"git", "clone", "--filter=blob:none",
		"https://github.com/folke/lazy.nvim.git",
		"--branch=stable", lazypath,
	})
	if vim.v.shell_error ~= 0 then
		vim.notify("Failed to clone lazy.nvim", vim.log.levels.ERROR)
		return
	end
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup("plugins")

-- Colorscheme (after plugins load)
vim.cmd.colorscheme("habamax")
