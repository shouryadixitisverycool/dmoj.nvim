local M = {}

local config = require("dmoj.config")
local ui = require("dmoj.ui")
local http = require("dmoj.http")
local auth = require("dmoj.auth")

--- Decode common HTML entities.
---@param s string
---@return string
local function decode_entities(s)
  s = s:gsub("&lt;", "<")
  s = s:gsub("&gt;", ">")
  s = s:gsub("&amp;", "&")
  s = s:gsub("&quot;", '"')
  s = s:gsub("&#39;", "'")
  s = s:gsub("&nbsp;", " ")
  s = s:gsub("&#(%d+);", function(n)
    local num = tonumber(n)
    if num and num < 128 then return string.char(num) end
    return ""
  end)
  return s
end

--- Scrape the submissions page and display in a floating window.
---@param opts? { user?: string }
function M.open(opts)
  opts = opts or {}
  local headers = auth.auth_headers()
  if not headers then
    ui.notify("Not logged in. Run :Dmoj login first.", vim.log.levels.ERROR)
    return
  end

  local cancel = ui.loading("Fetching submissions...")
  local url = config.options.base_url .. "/submissions/"
  if opts.user then
    url = config.options.base_url .. "/submissions/user/" .. opts.user .. "/"
  end

  http.get(url, { headers = headers, follow_redirects = true, timeout = 30 }, function(resp)
    cancel()

    if resp.status ~= 200 then
      ui.notify("Failed to fetch submissions: HTTP " .. resp.status, vim.log.levels.ERROR)
      return
    end

    local body = resp.body
    local submissions = {}

    -- Parse submission rows from the HTML table
    -- Try pattern: <td> elements within submission rows
    -- DMOJ submissions table typically has: ID, Problem, User, Result, Time, Memory, Language, Date
    for row in body:gmatch('<tr[^>]*>(.-)</tr>') do
      local sub_id = row:match('/submission/(%d+)')
      if sub_id then
        local problem_name = row:match('<a[^>]*href="/problem/[^"]*"[^>]*>([^<]+)</a>') or "?"
        local user = row:match('<a[^>]*href="/user/[^"]*"[^>]*>([^<]+)</a>') or "?"
        local result = row:match('<span[^>]*class="[^"]*sub%-result[^"]*"[^>]*>%s*([^<]+)%s*</span>')
        if not result then
          -- Try other patterns for the verdict
          for _, v in ipairs({"AC", "WA", "TLE", "MLE", "RTE", "CE", "IR", "OLE", "IE", "QU", "G", "P"}) do
            if row:find(">" .. v .. "<") then
              result = v
              break
            end
          end
        end
        result = result and vim.trim(result) or "?"

        local time_val = row:match("([%d%.]+)%s*s") or ""
        local mem_val = row:match("([%d%.]+)%s*KB") or ""

        table.insert(submissions, {
          id = sub_id,
          problem = decode_entities(vim.trim(problem_name)),
          user = decode_entities(vim.trim(user)),
          result = result,
          time = time_val,
          memory = mem_val,
        })
      end
    end

    if #submissions == 0 then
      ui.notify("No submissions found.", vim.log.levels.WARN)
      return
    end

    -- Build display
    local lines = {}
    local hl_data = {} -- {row, group, col_start, col_end}

    table.insert(lines, string.rep("═", 80))
    table.insert(lines, string.format("  Recent Submissions (%d shown)", #submissions))
    table.insert(lines, string.rep("═", 80))
    table.insert(lines, "")
    table.insert(lines, string.format(
      "  %-8s  %-6s  %-30s  %-12s  %s",
      "ID", "RESULT", "PROBLEM", "USER", "TIME"
    ))
    table.insert(lines, string.rep("─", 80))

    for _, s in ipairs(submissions) do
      local line = string.format(
        "  %-8s  %-6s  %-30s  %-12s  %s",
        s.id,
        s.result,
        s.problem:sub(1, 30),
        s.user:sub(1, 12),
        s.time ~= "" and (s.time .. "s") or ""
      )
      local row = #lines
      table.insert(lines, line)

      -- Color the result column
      local hl = "Normal"
      if s.result == "AC" then hl = "DiagnosticOk"
      elseif s.result == "WA" then hl = "DiagnosticError"
      elseif s.result == "TLE" or s.result == "MLE" or s.result == "RTE" then hl = "DiagnosticError"
      elseif s.result == "CE" or s.result == "IE" then hl = "DiagnosticError"
      end
      table.insert(hl_data, { row, hl, 10, 16 })
    end

    table.insert(lines, "")
    table.insert(lines, string.rep("─", 80))
    table.insert(lines, " [Enter] View  [o] Open in browser  [q] Close")

    local bufnr = ui.create_buf("dmoj://submissions", lines, { filetype = "dmoj" })

    -- Apply highlights
    local ns = vim.api.nvim_create_namespace("dmoj_submissions")
    for _, hl in ipairs(hl_data) do
      vim.api.nvim_buf_add_highlight(bufnr, ns, hl[2], hl[1], hl[3], hl[4])
    end
    -- Separator highlights
    local buf_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    for i, line in ipairs(buf_lines) do
      if line:match("^[═]+$") or line:match("^[─]+$") then
        vim.api.nvim_buf_add_highlight(bufnr, ns, "FloatBorder", i - 1, 0, -1)
      end
    end

    local win = ui.open_float(bufnr, {
      title = "Submissions",
      width = 84,
      height = math.min(#lines + 2, math.floor(vim.o.lines * 0.8)),
    })

    local kopts = { buffer = bufnr, nowait = true, silent = true }

    -- Enter: view submission details in browser
    vim.keymap.set("n", "<CR>", function()
      local row = vim.api.nvim_win_get_cursor(0)[1]
      local line = vim.api.nvim_buf_get_lines(bufnr, row - 1, row, false)[1] or ""
      local sid = line:match("^%s+(%d+)")
      if sid then
        local sub_url = config.options.base_url .. "/submission/" .. sid
        vim.fn.jobstart({ config.options.open_cmd, sub_url }, { detach = true })
      end
    end, kopts)

    -- o: open submissions page in browser
    vim.keymap.set("n", "o", function()
      vim.fn.jobstart({ config.options.open_cmd, url }, { detach = true })
    end, kopts)
  end)
end

return M
