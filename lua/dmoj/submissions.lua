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
  s = s:gsub("\xc2\xa0", " ") -- UTF-8 non-breaking space
  s = s:gsub("&#(%d+);", function(n)
    local num = tonumber(n)
    if num and num < 128 then return string.char(num) end
    return ""
  end)
  return s
end

--- Determine the highlight group for a verdict string.
---@param verdict string
---@return string hl_group
local function verdict_hl(verdict)
  if verdict == "AC" then return "DiagnosticOk"
  elseif verdict == "WA" then return "DiagnosticError"
  elseif verdict == "CE" then return "DiagnosticError"
  elseif verdict == "TLE" or verdict == "MLE" or verdict == "RTE" or verdict == "OLE" then
    return "DiagnosticWarn"
  end
  return "DiagnosticWarn"
end

--- Map verdict to an icon for display.
---@param verdict string
---@return string icon
local function verdict_icon(verdict)
  if verdict == "AC" then return "✔"
  elseif verdict == "CE" then return "✘"
  elseif verdict == "WA" then return "✘"
  end
  return "!"
end

--- Parse submission rows from the per-problem submissions HTML.
--- Each row is a `<div class="submission-row" id="...">` block containing:
--- - sub-result div with score and verdict/language
--- - sub-main div with user, timestamp, and view link
--- - sub-usage div with time and memory
---@param body string raw HTML body
---@return table[] submissions list of parsed submission entries
local function parse_submissions(body)
  local submissions = {}

  -- More robust: find each submission-row by ID and extract data from nearby HTML
  for sub_id, row_block in body:gmatch('<div class="submission%-row" id="(%d+)">(.-)<div class="submission%-row"') do
    local entry = M._parse_single_row(sub_id, row_block)
    if entry then
      table.insert(submissions, entry)
    end
  end

  -- Handle the last submission row (no following submission-row div)
  local all_ids = {}
  for sub_id in body:gmatch('<div class="submission%-row" id="(%d+)">') do
    table.insert(all_ids, sub_id)
  end

  local captured_ids = {}
  for _, s in ipairs(submissions) do
    captured_ids[s.id] = true
  end

  -- Parse any missing rows (typically the last one)
  for _, sub_id in ipairs(all_ids) do
    if not captured_ids[sub_id] then
      local pattern = '<div class="submission%-row" id="' .. sub_id .. '">(.-)</div>%s*</div>%s*</div>'
      local row_block = body:match(pattern)
      if row_block then
        local entry = M._parse_single_row(sub_id, row_block)
        if entry then
          table.insert(submissions, entry)
        end
      end
    end
  end

  -- Sort by ID descending (newest first)
  table.sort(submissions, function(a, b)
    return tonumber(a.id) > tonumber(b.id)
  end)

  return submissions
end

--- Parse a single submission row block into a structured entry.
---@param sub_id string submission ID
---@param block string HTML block for this row
---@return table|nil entry parsed submission, or nil on failure
function M._parse_single_row(sub_id, block)
  -- Score: <div class="score">50 / 100</div> or <div class="score">---</div>
  local score = block:match('<div class="score">(.-)</div>')
  score = score and decode_entities(vim.trim(score)) or "---"

  -- Verdict: <span ... class="status">RTE</span>
  local verdict = block:match('<span[^>]*class="status"[^>]*>([^<]+)</span>')
  verdict = verdict and vim.trim(verdict) or "?"

  -- Also get verdict from the sub-result class for coloring
  local result_class = block:match('<div class="sub%-result ([^"]+)">')
  result_class = result_class and vim.trim(result_class) or verdict

  -- Language: <span class="language">C</span>
  local language = block:match('<span class="language">([^<]+)</span>')
  language = language and vim.trim(language) or "?"

  -- Timestamp: <span data-iso="..." title="..." ...>59 minutes ago</span>
  local date_title = block:match('class="time%-with%-rel"[^>]*title="([^"]*)"')
  local date_relative = block:match('class="time%-with%-rel"[^>]*>([^<]+)</span>')
  date_title = date_title and vim.trim(date_title) or ""
  date_relative = date_relative and vim.trim(date_relative) or ""

  -- Time: <div title="0.07449877099999999s" class="time"> 0.07s </div>
  -- or: <div class="time">---</div>
  local time_exact = block:match('<div title="([%d%.]+)s" class="time">')
  local time_display = block:match('class="time"[^>]*>%s*([^<]+)%s*</div>')
  time_display = time_display and vim.trim(time_display) or "---"
  if time_display == "---" then
    time_exact = nil
  end

  -- Memory: <div class="memory">1.63&nbsp;MB</div>
  -- or: <div class="memory">---</div>
  local memory_raw = block:match('<div class="memory">(.-)</div>')
  local memory_display = memory_raw and decode_entities(vim.trim(memory_raw)) or "---"

  return {
    id = sub_id,
    score = score,
    verdict = verdict,
    result_class = result_class,
    language = language,
    date_title = date_title,
    date_relative = date_relative,
    time_exact = time_exact,
    time_display = time_display,
    memory_display = memory_display,
  }
end

--- Extract the problem title from the submissions page.
---@param body string raw HTML
---@return string title
local function extract_title(body)
  -- <h2>My submissions for <a href="...">Task Scheduler Simulation</a></h2>
  local title = body:match('<h2>My submissions for%s*<a[^>]*>([^<]+)</a>')
  if title then
    return decode_entities(vim.trim(title))
  end
  -- Fallback: any h2 with "submissions for"
  title = body:match('submissions for%s+([^<]+)')
  if title then
    return decode_entities(vim.trim(title))
  end
  return "Unknown Problem"
end

--- Open the per-problem submissions list.
--- Uses Telescope if available, otherwise falls back to a floating window.
--- If a problem is currently open (via buffer-local var), fetches submissions
--- for that problem. Otherwise prompts the user.
---@param opts? { problem_code?: string, user?: string }
function M.open(opts)
  opts = opts or {}
  local headers = auth.auth_headers()
  if not headers then
    ui.notify("Not logged in. Run :Dmoj login first.", vim.log.levels.ERROR)
    return
  end

  -- Determine problem code from opts, buffer-local var, or prompt
  local problem_code = opts.problem_code
  if not problem_code then
    local bufnr = vim.api.nvim_get_current_buf()
    problem_code = vim.b[bufnr].dmoj_problem_code
  end

  if not problem_code then
    local problems = require("dmoj.problems")
    problems.pick_problem(function(code)
      M.open({ problem_code = code, user = opts.user })
    end, "Select problem for submissions")
    return
  end

  -- Get username for the per-user submissions URL
  local user = opts.user
  if not user then
    auth.whoami(function(username)
      if not username then
        ui.notify("Could not determine username. Showing all submissions.", vim.log.levels.WARN)
        M._fetch_and_show(problem_code, nil, headers)
      else
        M._fetch_and_show(problem_code, username, headers)
      end
    end)
  else
    M._fetch_and_show(problem_code, user, headers)
  end
end

--- Fetch the submissions page and display the list.
---@param problem_code string
---@param username string|nil
---@param headers table
function M._fetch_and_show(problem_code, username, headers)
  local cancel = ui.loading("Fetching submissions for " .. problem_code .. "...")

  -- Build URL: /problem/{code}/submissions/{username}/
  local url = config.options.base_url .. "/problem/" .. problem_code .. "/submissions/"
  if username then
    url = url .. username .. "/"
  end

  http.get(url, { headers = headers, follow_redirects = true, timeout = 30 }, function(resp)
    cancel()

    if resp.status ~= 200 then
      ui.notify("Failed to fetch submissions: HTTP " .. resp.status, vim.log.levels.ERROR)
      return
    end

    local body = resp.body
    local submissions = parse_submissions(body)
    local problem_title = extract_title(body)

    if #submissions == 0 then
      ui.notify("No submissions found for " .. problem_code .. ".", vim.log.levels.WARN)
      return
    end

    local has_telescope, _ = pcall(require, "telescope")
    if has_telescope then
      M._show_telescope(submissions, problem_code, problem_title, url)
    else
      M._show_fallback(submissions, problem_code, problem_title, url)
    end
  end)
end

--- Telescope-based submission picker.
---@param submissions table[] parsed submissions
---@param problem_code string
---@param problem_title string
---@param page_url string
function M._show_telescope(submissions, problem_code, problem_title, page_url)
  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")
  local entry_display = require("telescope.pickers.entry_display")

  local displayer = entry_display.create({
    separator = " ",
    items = {
      { width = 2 },   -- verdict icon
      { width = 10 },  -- score
      { width = 4 },   -- verdict
      { width = 6 },   -- language
      { width = 8 },   -- time
      { width = 8 },   -- memory
      { remaining = true }, -- date
    },
  })

  local function make_display(entry)
    local s = entry.submission
    local icon = verdict_icon(s.verdict)
    local icon_hl = verdict_hl(s.verdict)
    local score_hl = verdict_hl(s.verdict)

    return displayer({
      { icon, icon_hl },
      { s.score, score_hl },
      { s.verdict, verdict_hl(s.verdict) },
      { s.language },
      { s.time_display, "TelescopeResultsNumber" },
      { s.memory_display, "TelescopeResultsNumber" },
      { s.date_relative, "TelescopeResultsComment" },
    })
  end

  pickers.new({}, {
    prompt_title = "Submissions for " .. problem_title,
    results_title = string.format("%d submissions", #submissions),
    finder = finders.new_table({
      results = submissions,
      entry_maker = function(sub)
        local search_text = string.format(
          "%s %s %s %s %s %s",
          sub.id,
          sub.score,
          sub.verdict,
          sub.language,
          sub.date_relative,
          sub.date_title
        )
        return {
          value = sub.id,
          display = make_display,
          ordinal = search_text,
          submission = sub,
        }
      end,
    }),
    sorter = conf.generic_sorter({}),
    attach_mappings = function(prompt_bufnr, map)
      -- Enter: view submission details
      actions.select_default:replace(function()
        local entry = action_state.get_selected_entry()
        actions.close(prompt_bufnr)
        if entry then
          local submit = require("dmoj.submit")
          submit.poll_result(tonumber(entry.value))
        end
      end)

      -- Ctrl-o / o: open in browser
      map("i", "<C-o>", function()
        local entry = action_state.get_selected_entry()
        if entry then
          local sub_url = config.options.base_url .. "/submission/" .. entry.value
          vim.fn.jobstart({ config.options.open_cmd, sub_url }, { detach = true })
        end
      end)
      map("n", "o", function()
        local entry = action_state.get_selected_entry()
        if entry then
          local sub_url = config.options.base_url .. "/submission/" .. entry.value
          vim.fn.jobstart({ config.options.open_cmd, sub_url }, { detach = true })
        end
      end)

      return true
    end,
  }):find()
end

--- Fallback floating window picker (no telescope dependency).
---@param submissions table[] parsed submissions
---@param problem_code string
---@param problem_title string
---@param page_url string
function M._show_fallback(submissions, problem_code, problem_title, page_url)
  local popup_width = math.max(80, math.floor(vim.o.columns * 0.7))
  local inner_width = popup_width - 4
  local sep = string.rep("─", inner_width)

  local lines = {}
  local hl_data = {} -- {row, hl_group, col_start, col_end}

  -- Header
  table.insert(lines, "")
  local header_line = "  My submissions for " .. problem_title
  local header_row = #lines
  table.insert(lines, header_line)
  table.insert(hl_data, { header_row, "@markup.heading", 0, -1 })
  table.insert(lines, "  " .. string.format("%d submissions", #submissions))
  table.insert(hl_data, { #lines - 1, "Comment", 0, -1 })
  table.insert(lines, "")
  table.insert(lines, "  " .. sep)

  -- Column headers
  local col_fmt = "  %s  %-10s  %-4s  %-6s  %-8s  %-8s  %s"
  local header = string.format(col_fmt, " ", "SCORE", "RSLT", "LANG", "TIME", "MEMORY", "DATE")
  local hdr_row = #lines
  table.insert(lines, header)
  table.insert(hl_data, { hdr_row, "Comment", 0, -1 })
  table.insert(lines, "  " .. sep)

  -- Track which row index each submission starts at (for Enter keymap)
  local row_to_submission = {}
  local first_data_row = #lines

  for _, s in ipairs(submissions) do
    local icon = verdict_icon(s.verdict)
    local line = string.format(col_fmt,
      icon,
      s.score,
      s.verdict,
      s.language,
      s.time_display,
      s.memory_display,
      s.date_relative
    )

    local row = #lines
    table.insert(lines, line)
    row_to_submission[row] = s

    -- Highlight the icon
    local hl = verdict_hl(s.verdict)
    table.insert(hl_data, { row, hl, 2, 2 + #icon })

    -- Highlight the score
    local score_start = 2 + #icon + 2
    table.insert(hl_data, { row, hl, score_start, score_start + #s.score })

    -- Highlight the verdict
    local verdict_col = score_start + 10 + 2
    table.insert(hl_data, { row, hl, verdict_col, verdict_col + #s.verdict })

    -- Highlight the date in dimmed color
    local date_col = line:find(s.date_relative, 1, true)
    if date_col then
      table.insert(hl_data, { row, "Comment", date_col - 1, date_col - 1 + #s.date_relative })
    end
  end

  table.insert(lines, "")
  table.insert(lines, "  " .. sep)
  table.insert(lines, "  [Enter] View details  [o] Open in browser  [q] Close")
  table.insert(lines, "")

  local bufnr = ui.create_buf("dmoj://submissions/" .. problem_code, lines, { filetype = "dmoj" })

  -- Apply highlights
  local ns = vim.api.nvim_create_namespace("dmoj_submissions")
  for _, hl in ipairs(hl_data) do
    pcall(vim.api.nvim_buf_add_highlight, bufnr, ns, hl[2], hl[1], hl[3], hl[4])
  end

  -- Highlight separator lines
  local buf_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  for i, line in ipairs(buf_lines) do
    if line:match("^%s*[─]+%s*$") then
      pcall(vim.api.nvim_buf_add_highlight, bufnr, ns, "FloatBorder", i - 1, 0, -1)
    end
  end

  local popup_height = math.min(#lines + 2, math.floor(vim.o.lines * 0.8))

  local win = ui.open_float(bufnr, {
    title = "Submissions: " .. problem_code,
    width = popup_width,
    height = popup_height,
  })

  local kopts = { buffer = bufnr, nowait = true, silent = true }

  -- Enter: view submission details
  vim.keymap.set("n", "<CR>", function()
    local row = vim.api.nvim_win_get_cursor(0)[1] - 1 -- 0-indexed
    local sub = row_to_submission[row]
    if sub then
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
      local submit = require("dmoj.submit")
      submit.poll_result(tonumber(sub.id))
    end
  end, kopts)

  -- o: open specific submission in browser
  vim.keymap.set("n", "o", function()
    local row = vim.api.nvim_win_get_cursor(0)[1] - 1 -- 0-indexed
    local sub = row_to_submission[row]
    if sub then
      local sub_url = config.options.base_url .. "/submission/" .. sub.id
      vim.fn.jobstart({ config.options.open_cmd, sub_url }, { detach = true })
    else
      vim.fn.jobstart({ config.options.open_cmd, page_url }, { detach = true })
    end
  end, kopts)

  -- Place cursor on first data row
  pcall(vim.api.nvim_win_set_cursor, win, { first_data_row + 1, 0 })
end

return M
