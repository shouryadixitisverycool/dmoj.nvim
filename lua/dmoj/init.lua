local M = {}

local config = require("dmoj.config")

--- Setup the plugin with user options.
---@param opts? table
function M.setup(opts)
  config.setup(opts)
  M._register_commands()
  M._register_keymaps()
  M._register_arg_handler()
end

--- Check if Neovim was launched with the configured arg (e.g. `nvim dmoj.nvim`).
--- If so, take over the session and show the dashboard on VimEnter.
function M._register_arg_handler()
  local arg = config.options.arg
  if not arg or arg == "" then return end

  vim.api.nvim_create_autocmd("VimEnter", {
    group = vim.api.nvim_create_augroup("dmoj_arg_handler", { clear = true }),
    pattern = "*",
    nested = true,
    callback = function()
      -- Must have exactly 1 CLI argument matching the configured arg
      if vim.fn.argc(-1) ~= 1 then return end
      if vim.fn.argv(0, -1) ~= arg then return end

      -- The buffer must be empty (no real file loaded)
      local buf = vim.api.nvim_get_current_buf()
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      if #lines > 1 or (#lines == 1 and lines[1] ~= "") then return end

      -- Take over: show the dashboard in the current buffer
      require("dmoj.dashboard").open()
    end,
  })
end

--- Register all :Dmoj commands.
function M._register_commands()
  vim.api.nvim_create_user_command("Dmoj", function(cmd)
    local args = vim.split(vim.trim(cmd.args), "%s+", { trimempty = true })
    local subcmd = args[1] or "menu"
    table.remove(args, 1)

    M._dispatch(subcmd, args)
  end, {
    nargs = "*",
    complete = function(_, line, _)
      local subcmds = {
        "menu", "list", "open", "submit", "login", "logout",
        "desc", "result", "browser", "refresh", "submissions", "contests", "whoami",
        "run", "test",
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
end

--- Dispatch a subcommand.
---@param subcmd string
---@param args string[]
function M._dispatch(subcmd, args)
  if subcmd == "menu" or subcmd == "dashboard" or subcmd == "home" then
    require("dmoj.dashboard").open()

  elseif subcmd == "list" then
    require("dmoj.problems").open()

  elseif subcmd == "refresh" then
    require("dmoj.problems").clear_cache()
    vim.notify("[dmoj] Problem cache cleared.", vim.log.levels.INFO)

  elseif subcmd == "open" then
    local code = args[1]
    if not code then
      vim.ui.input({ prompt = "Problem code: " }, function(input)
        if input and vim.trim(input) ~= "" then
          require("dmoj.problems").open_problem(vim.trim(input))
        end
      end)
    else
      require("dmoj.problems").open_problem(code)
    end

  elseif subcmd == "submit" then
    require("dmoj.submit").submit({
      problem_code = args[1],
      lang = args[2],
    })

  elseif subcmd == "submissions" then
    local bufnr = vim.api.nvim_get_current_buf()
    local code = args[1] or vim.b[bufnr].dmoj_problem_code
    require("dmoj.submissions").open({
      problem_code = code,
    })

  elseif subcmd == "contests" then
    require("dmoj.contests").open()

  elseif subcmd == "login" then
    require("dmoj.auth").login()

  elseif subcmd == "logout" then
    require("dmoj.auth").delete_cookie()

  elseif subcmd == "whoami" then
    require("dmoj.auth").whoami(function(username)
      if username then
        vim.notify("[dmoj] Logged in as: " .. username, vim.log.levels.INFO)
      else
        vim.notify("[dmoj] Not logged in", vim.log.levels.WARN)
      end
    end)

  elseif subcmd == "desc" then
    local bufnr = vim.api.nvim_get_current_buf()
    local code = args[1] or vim.b[bufnr].dmoj_problem_code
    if not code then
      vim.notify("[dmoj] No problem context. Use :Dmoj desc <code>", vim.log.levels.WARN)
      return
    end
    local api = require("dmoj.api")
    local description = require("dmoj.description")
    api.problem(code, function(meta, err)
      if err then
        vim.notify("[dmoj] " .. err, vim.log.levels.ERROR)
        return
      end
      description.show(code, meta)
    end)

  elseif subcmd == "result" then
    local id = tonumber(args[1])
    if not id then
      vim.ui.input({ prompt = "Submission ID: " }, function(input)
        local sid = tonumber(input)
        if sid then
          require("dmoj.submit").poll_result(sid)
        end
      end)
    else
      require("dmoj.submit").poll_result(id)
    end

  elseif subcmd == "browser" then
    local bufnr = vim.api.nvim_get_current_buf()
    local code = args[1] or vim.b[bufnr].dmoj_problem_code
    if code then
      local url = config.options.base_url .. "/problem/" .. code
      vim.fn.jobstart({ config.options.open_cmd, url }, { detach = true })
    else
      vim.fn.jobstart({ config.options.open_cmd, config.options.base_url }, { detach = true })
    end

  elseif subcmd == "run" or subcmd == "test" then
    require("dmoj.runner").run({
      problem_code = args[1],
      lang = args[2],
    })

  else
    vim.notify("[dmoj] Unknown command: " .. subcmd .. ". Available: menu, list, open, submit, run, submissions, contests, login, logout, whoami, desc, result, browser", vim.log.levels.ERROR)
  end
end

--- Register default keymaps.
function M._register_keymaps()
  local km = config.options.keymaps
  if not km then return end

  if km.list then
    vim.keymap.set("n", km.list, function()
      require("dmoj.problems").open()
    end, { desc = "DMOJ: Problem list" })
  end

  if km.submit then
    vim.keymap.set("n", km.submit, function()
      require("dmoj.submit").submit()
    end, { desc = "DMOJ: Submit current buffer" })
  end

  if km.desc then
    vim.keymap.set("n", km.desc, function()
      M._dispatch("desc", {})
    end, { desc = "DMOJ: Show problem description" })
  end

  if km.open_browser then
    vim.keymap.set("n", km.open_browser, function()
      M._dispatch("browser", {})
    end, { desc = "DMOJ: Open in browser" })
  end

  if km.test then
    vim.keymap.set("n", km.test, function()
      M._dispatch("run", {})
    end, { desc = "DMOJ: Run against sample test cases" })
  end
end

return M
