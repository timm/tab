-- netrw -------------------------------------------------------------
vim.g.netrw_banner = 0
vim.g.netrw_liststyle = 3
vim.g.netrw_browse_split = 4
vim.g.netrw_winsize = 15

-- ui / editing ------------------------------------------------------
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.cursorline = true
vim.opt.mouse = "a"
vim.opt.clipboard = "unnamedplus"

vim.opt.ignorecase = true
vim.opt.smartcase = true

vim.opt.expandtab = true
vim.opt.tabstop = 2
vim.opt.shiftwidth = 2

vim.opt.splitright = true
vim.opt.splitbelow = true


vim.g.netrw_banner = 0

-- undo --------------------------------------------------------------
vim.opt.undofile = true
vim.opt.undodir = vim.fn.expand("~/.vim/undo")

-- statusline --------------------------------------------------------
vim.opt.statusline =
  "%#StatusLine# ▶ %f %m%r%=%y ❖ %l:%c ❖ %p%% "

vim.opt.laststatus = 2

-- keymaps -----------------------------------------------------------
vim.keymap.set("n", "Q", ":quitall<CR>", { noremap = true, silent = true })

-- Toggle spelling with <Leader>s (usually \s)
vim.keymap.set("n", "<leader>s", ":set spell!<CR>", { silent = true })

-- colors ------------------------------------------------------------
pcall(vim.cmd.colorscheme, "lunaperche")  -- a miss must not stop us

-- yuescript: syntax + indent + ftdetect for .yue --------------------
-- `vi` runs nvim --clean, which drops user dirs from 'packpath';
-- restore just the one vim.pack installs into.
vim.opt.packpath:prepend(vim.fn.stdpath("data") .. "/site")
vim.pack.add { "https://github.com/pigpigyyy/yuescript-vim" }

-- yuescript: compile-on-save diagnostics (`yue -b` checks, writes
-- nothing).  Errors come back as "Failed to compile: <file>" then
-- "<line>: <msg>"; land them in the quickfix list.
vim.api.nvim_create_autocmd("BufWritePost", {
  pattern = "*.yue",
  callback = function(ev)
    local out = vim.fn.system { "yue", "-b", ev.file }
    local qf = {}
    if vim.v.shell_error ~= 0 then
      for l, msg in out:gmatch("\n(%d+):%s*([^\n]+)") do
        qf[#qf + 1] = { filename = ev.file, lnum = tonumber(l),
                        text = msg }
      end
    end
    vim.fn.setqflist(qf, "r")
    if #qf > 0 then vim.cmd("copen | wincmd p")
    else vim.cmd("cclose") end
  end,
})

-- lisp indent: vim built-in + extra forms via lispwords -----------
vim.api.nvim_create_autocmd("FileType", {
  pattern = "lisp",
  callback = function()
    vim.bo.lisp = true
    vim.bo.lispwords =
      vim.bo.lispwords .. ",defmethods,defeg,let+"
  end,
})

