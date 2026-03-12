-- dmoj.nvim plugin loader
-- This file is sourced automatically by Neovim when the plugin is installed.

if vim.g.loaded_dmoj then
  return
end
vim.g.loaded_dmoj = 1

-- Minimal bootstrap: register the :Dmoj command immediately so it's available
-- even before setup() is called. Full initialization happens in setup().
vim.api.nvim_create_user_command("Dmoj", function(cmd)
  -- Lazy-init: if setup hasn't been called, call it with defaults
  local conf = require("dmoj.config")
  if not conf.options.base_url then
    require("dmoj").setup({})
  end
  -- Dispatch directly to avoid infinite loop (setup() re-registers this command)
  local args = vim.split(vim.trim(cmd.args), "%s+", { trimempty = true })
  local subcmd = args[1] or "list"
  table.remove(args, 1)
  require("dmoj")._dispatch(subcmd, args)
end, {
  nargs = "*",
  complete = function(_, line, _)
    local subcmds = {
      "menu", "list", "open", "submit", "login", "logout",
      "desc", "result", "browser", "refresh", "submissions", "contests", "whoami",
    }
    local parts = vim.split(vim.trim(line), "%s+", { trimempty = true })
    if #parts <= 2 then
      local prefix = (parts[2] or ""):lower()
      return vim.tbl_filter(function(s)
        return s:find(prefix, 1, true) == 1
      end, subcmds)
    end
    return {}
  end,
  desc = "DMOJ Online Judge integration",
})
