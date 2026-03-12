local M = {}

local config = require("dmoj.config")

--- Setup the plugin with user options.
---@param opts? table
function M.setup(opts)
  config.setup(opts)
  M._register_commands()
  M._register_keymaps()
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
    require("dmoj.submissions").open({
      user = args[1],
    })

  elseif subcmd == "contests" then
    local url = config.options.base_url .. "/contests/"
    vim.fn.jobstart({ config.options.open_cmd, url }, { detach = true })

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

  else
    vim.notify("[dmoj] Unknown command: " .. subcmd .. ". Available: menu, list, open, submit, submissions, contests, login, logout, whoami, desc, result, browser", vim.log.levels.ERROR)
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
end

return M
