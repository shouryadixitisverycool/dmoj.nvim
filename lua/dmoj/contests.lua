local M = {}

local config = require("dmoj.config")
local http = require("dmoj.http")
local auth = require("dmoj.auth")
local ui = require("dmoj.ui")

--- Decode common HTML entities in scraped text.
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

--- Strip HTML tags from a string.
---@param s string
---@return string
local function strip_tags(s)
  return s:gsub("<[^>]+>", "")
end

--- Detect the contest key the user is currently participating in.
--- Looks for the `<div id="contest-info">` block on the page.
---@param body string raw HTML
---@return string|nil contest_key
local function detect_current_contest(body)
  -- <div id="contest-info" ...>
  --   <a href=".../contest/CODE" ...>
  local block = body:match('<div id="contest%-info"[^>]*>(.-)</div>')
  if not block then return nil end
  local key = block:match('/contest/([^/"]+)')
  return key
end

--- Parse contest rows from the contests list page HTML.
--- Returns a list of contest entries grouped by section (active/upcoming/past).
---@param body string raw HTML
---@return table[] contests list of { key, title, section, time_info, users }
local function parse_contests(body)
  local contests = {}

  -- Identify sections and their content by splitting on <h4> tags.
  -- Sections: "Active contests", "Upcoming contests", "Past contests"
  local sections = {
    { pattern = "<h4>Active contests</h4>", label = "active" },
    { pattern = '<h4 id="past%-contests">Past contests</h4>', label = "past" },
    { pattern = "<h4>Upcoming contests</h4>", label = "upcoming" },
  }

  for _, sec in ipairs(sections) do
    local sec_start = body:find(sec.pattern)
    if sec_start then
      -- Find the table after this section header
      local table_start = body:find('<table class="contest%-list', sec_start)
      if table_start then
        -- Find the end of the table
        local table_end = body:find("</table>", table_start)
        if table_end then
          local table_block = body:sub(table_start, table_end + 7)

          -- Parse each <tr> row in the table body
          for row_block in table_block:gmatch("<tr>(.-)</tr>") do
            -- Skip header rows (contain <th>)
            if row_block:find("<th") then goto continue end

            -- Contest link: <a href=".../contest/CODE" class="contest-list-title">TITLE</a>
            local key = row_block:match('/contest/([^/"]+)')
            local title = row_block:match('class="contest%-list%-title"[^>]*>([^<]+)</a>')

            if key and title then
              title = decode_entities(vim.trim(title))

              -- Time remaining: <span data-secs="..." class="time-remaining">DISPLAY</span>
              local time_remaining = row_block:match('class="time%-remaining"[^>]*>([^<]+)</span>')
              time_remaining = time_remaining and vim.trim(time_remaining) or ""

              -- Time info: "Ends in ..." or start date
              local time_label = row_block:match('<span class="time">(.-)</span>')
              if time_label then
                time_label = strip_tags(time_label)
                time_label = decode_entities(vim.trim(time_label))
              else
                time_label = ""
              end

              -- Duration and start date from <div class="time time-left">
              local time_left_div = row_block:match('<div class="time time%-left">(.-)</div>')
              local duration_info = ""
              if time_left_div then
                duration_info = strip_tags(time_left_div)
                duration_info = decode_entities(vim.trim(duration_info))
                -- Collapse internal whitespace
                duration_info = duration_info:gsub("%s+", " ")
              end

              -- Users count: second <td> in the row
              local tds = {}
              for td_content in row_block:gmatch("<td>(.-)</td>") do
                table.insert(tds, td_content)
              end
              local users = ""
              if #tds >= 2 then
                users = strip_tags(tds[2])
                users = vim.trim(users)
              end

              table.insert(contests, {
                key = key,
                title = title,
                section = sec.label,
                time_label = time_label,
                time_remaining = time_remaining,
                duration_info = duration_info,
                users = users,
              })
            end

            ::continue::
          end
        end
      end
    end
  end

  return contests
end

--- Cached contest list to avoid re-fetching when re-opening picker.
---@type table[]|nil
local contests_cache = nil

--- Invalidate the cached contest list.
function M.clear_cache()
  contests_cache = nil
end

--- Update just the current_key in the cache without re-fetching.
---@param key string|nil the contest key that is now current, or nil if left
function M._update_current_key(key)
  if contests_cache then
    contests_cache.current_key = key
  end
end

--- Fetch contest list (with caching) then call callback.
---@param callback fun(contests: table[], current_key: string|nil)
local function fetch_contests(callback)
  if contests_cache then
    -- Re-detect current contest even from cache (need the body)
    -- Actually, just return cached data — current_key is also cached
    callback(contests_cache.contests, contests_cache.current_key)
    return
  end

  local headers = auth.auth_headers()
  if not headers then
    ui.notify("Not logged in. Run :Dmoj login first.", vim.log.levels.ERROR)
    return
  end

  local cancel = ui.loading("Fetching contests...")

  http.get(config.options.base_url .. "/contests/", {
    headers = headers,
    follow_redirects = true,
    timeout = 30,
  }, function(resp)
    cancel()

    if resp.status ~= 200 then
      ui.notify("Failed to fetch contests: HTTP " .. resp.status, vim.log.levels.ERROR)
      return
    end

    local body = resp.body
    local contests = parse_contests(body)
    local current_key = detect_current_contest(body)

    contests_cache = {
      contests = contests,
      current_key = current_key,
    }

    callback(contests, current_key)
  end)
end

--- Open the contest list using Telescope or fallback float.
function M.open()
  local has_telescope, _ = pcall(require, "telescope")
  if has_telescope then
    M._open_telescope()
  else
    M._open_fallback()
  end
end

--- Get display icon and highlight for a contest based on section and current status.
---@param contest table
---@param current_key string|nil
---@return string icon, string hl_group
local function contest_icon(contest, current_key)
  if current_key and contest.key == current_key then
    return "★", "DiagnosticOk"
  end
  if contest.section == "active" then
    return "●", "DiagnosticOk"
  elseif contest.section == "upcoming" then
    return "◷", "DiagnosticWarn"
  else
    return "○", "Comment"
  end
end

--- Telescope-based contest picker.
function M._open_telescope()
  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")
  local entry_display = require("telescope.pickers.entry_display")

  fetch_contests(function(contests, current_key)
    if #contests == 0 then
      ui.notify("No contests found.", vim.log.levels.WARN)
      return
    end

    local displayer = entry_display.create({
      separator = " ",
      items = {
        { width = 2 },   -- status icon
        { width = 40 },  -- title
        { width = 25 },  -- time info
        { width = 6 },   -- users
      },
    })

    local function make_display(entry)
      local c = entry.contest
      local icon, icon_hl = contest_icon(c, current_key)

      -- Build time info string
      local time_str = c.time_label
      if time_str == "" then
        time_str = c.duration_info
      end

      return displayer({
        { icon, icon_hl },
        { c.title },
        { time_str, "TelescopeResultsComment" },
        { c.users, "TelescopeResultsNumber" },
      })
    end

    pickers.new({}, {
      prompt_title = "DMOJ Contests",
      results_title = string.format("%d contests", #contests),
      finder = finders.new_table({
        results = contests,
        entry_maker = function(contest)
          local search_text = string.format(
            "%s %s %s %s",
            contest.title,
            contest.key,
            contest.section,
            contest.time_label
          )
          return {
            value = contest.key,
            display = make_display,
            ordinal = search_text,
            contest = contest,
          }
        end,
      }),
      sorter = conf.generic_sorter({}),
      attach_mappings = function(prompt_bufnr, map)
        -- Enter: open contest detail view
        actions.select_default:replace(function()
          local entry = action_state.get_selected_entry()
          actions.close(prompt_bufnr)
          if entry then
            M.show_contest(entry.value)
          end
        end)

        -- Ctrl-o / o: open in browser
        map("i", "<C-o>", function()
          local entry = action_state.get_selected_entry()
          if entry then
            local url = config.options.base_url .. "/contest/" .. entry.value
            vim.fn.jobstart({ config.options.open_cmd, url }, { detach = true })
          end
        end)
        map("n", "o", function()
          local entry = action_state.get_selected_entry()
          if entry then
            local url = config.options.base_url .. "/contest/" .. entry.value
            vim.fn.jobstart({ config.options.open_cmd, url }, { detach = true })
          end
        end)

        -- Ctrl-r: refresh cache
        map("i", "<C-r>", function()
          actions.close(prompt_bufnr)
          M.clear_cache()
          M._open_telescope()
        end)

        return true
      end,
    }):find()
  end)
end

--- Fallback floating window picker (no Telescope dependency).
function M._open_fallback()
  fetch_contests(function(contests, current_key)
    if #contests == 0 then
      ui.notify("No contests found.", vim.log.levels.WARN)
      return
    end

    local lines = {}
    local hl_data = {} -- {row, hl_group, col_start, col_end}

    table.insert(lines, string.format(" DMOJ Contests  (%d total)", #contests))
    table.insert(lines, string.rep("─", 80))
    table.insert(lines, string.format("     %-40s  %-25s  %s", "CONTEST", "TIME", "USERS"))
    local hdr_row = #lines - 1
    table.insert(hl_data, { hdr_row, "Comment", 0, -1 })
    table.insert(lines, string.rep("─", 80))

    for i, c in ipairs(contests) do
      local icon, _ = contest_icon(c, current_key)
      local time_str = c.time_label
      if time_str == "" then
        time_str = c.duration_info
      end
      lines[i + 4] = string.format(
        "%s %-40s  %-25s  %s",
        icon, c.title:sub(1, 40), time_str:sub(1, 25), c.users
      )
    end

    table.insert(lines, "")
    table.insert(lines, string.rep("─", 80))
    table.insert(lines, " [Enter] Open  [o] Browser  [q] Close")

    local bufnr = ui.create_buf("dmoj://contests", lines, { filetype = "dmoj" })

    -- Apply section-based highlights
    local ns = vim.api.nvim_create_namespace("dmoj_contests")
    for _, hl in ipairs(hl_data) do
      pcall(vim.api.nvim_buf_add_highlight, bufnr, ns, hl[2], hl[1], hl[3], hl[4])
    end

    -- Highlight icon column per row
    for i, c in ipairs(contests) do
      local row = i + 3 -- 0-indexed (rows 0-3 are header)
      local _, icon_hl = contest_icon(c, current_key)
      pcall(vim.api.nvim_buf_add_highlight, bufnr, ns, icon_hl, row, 0, 2)
    end

    -- Highlight separator lines
    local buf_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    for i, line in ipairs(buf_lines) do
      if line:match("^[─]+$") then
        pcall(vim.api.nvim_buf_add_highlight, bufnr, ns, "FloatBorder", i - 1, 0, -1)
      end
    end

    local win = ui.open_float(bufnr, { title = "DMOJ Contests" })

    local kopts = { buffer = bufnr, nowait = true, silent = true }

    vim.keymap.set("n", "<CR>", function()
      local row = vim.api.nvim_win_get_cursor(0)[1]
      local idx = row - 4
      if idx >= 1 and idx <= #contests then
        local c = contests[idx]
        if vim.api.nvim_win_is_valid(win) then
          vim.api.nvim_win_close(win, true)
        end
        M.show_contest(c.key)
      end
    end, kopts)

    vim.keymap.set("n", "o", function()
      local row = vim.api.nvim_win_get_cursor(0)[1]
      local idx = row - 4
      if idx >= 1 and idx <= #contests then
        local c = contests[idx]
        local url = config.options.base_url .. "/contest/" .. c.key
        vim.fn.jobstart({ config.options.open_cmd, url }, { detach = true })
      end
    end, kopts)
  end)
end

--- Extract contest metadata from a contest detail page.
---@param body string raw HTML
---@param contest_key string
---@return table meta { title, joined, csrf_token, duration_info, time_remaining, description_html }
local function parse_contest_detail(body, contest_key)
  local meta = {
    title = "",
    joined = false,
    csrf_token = nil,
    duration_info = "",
    time_remaining = "",
    description_html = "",
  }

  -- Title: <h2>TITLE</h2> (inside the tabs div)
  meta.title = body:match('<h2>([^<]+)</h2>') or "Unknown Contest"
  meta.title = decode_entities(vim.trim(meta.title))

  -- Detect join/leave status by looking for the form action
  local leave_pattern = '/contest/' .. contest_key .. '/leave'
  local join_pattern = '/contest/' .. contest_key .. '/join'

  if body:find(leave_pattern, 1, true) then
    meta.joined = true
  elseif body:find(join_pattern, 1, true) then
    meta.joined = false
  end

  -- Get CSRF token from cookie (same approach as submit.lua)
  meta.csrf_token = auth.get_csrf_token()

  -- Duration info: <b>17 days 06:31</b> long starting on <b>February 25, 2026, 17:28 IST</b>
  local duration_block = body:match('<b>([^<]+)</b> long starting on <b>([^<]+)</b>')
  if duration_block then
    -- Reconstruct with both captures
    local dur = body:match('<b>([^<]+)</b> long')
    local start = body:match('starting on <b>([^<]+)</b>')
    if dur and start then
      meta.duration_info = decode_entities(dur) .. " long, started " .. decode_entities(start)
    end
  end

  -- Time remaining from banner
  local banner_time = body:match('id="banner".-class="time%-remaining"[^>]*>([^<]+)</span>')
  if banner_time then
    meta.time_remaining = vim.trim(banner_time)
  end

  -- Description: <div class="content-description">...</div>
  -- Find the content-description div — it may contain nested divs
  local desc_start = body:find('<div class="content%-description">')
  if desc_start then
    -- Find the matching closing div by counting nesting
    local depth = 0
    local pos = desc_start
    local desc_end = nil
    while pos <= #body do
      local open_s, open_e = body:find("<div", pos, true)
      local close_s, close_e = body:find("</div>", pos, true)

      if not open_s and not close_s then break end

      -- Which comes first?
      if open_s and (not close_s or open_s < close_s) then
        depth = depth + 1
        pos = open_e + 1
      elseif close_s then
        depth = depth - 1
        if depth == 0 then
          desc_end = close_s - 1
          break
        end
        pos = close_e + 1
      end
    end

    if desc_end then
      -- Extract inner HTML (skip the opening tag itself)
      local inner_start = body:find(">", desc_start) + 1
      meta.description_html = body:sub(inner_start, desc_end)
    end
  end

  return meta
end

--- Show a contest detail view in a full-window buffer.
---@param contest_key string
function M.show_contest(contest_key)
  local headers = auth.auth_headers()
  if not headers then
    ui.notify("Not logged in. Run :Dmoj login first.", vim.log.levels.ERROR)
    return
  end

  local cancel = ui.loading("Loading contest " .. contest_key .. "...")

  local url = config.options.base_url .. "/contest/" .. contest_key
  http.get(url, { headers = headers, follow_redirects = true, timeout = 30 }, function(resp)
    cancel()

    if resp.status ~= 200 then
      ui.notify("Failed to fetch contest: HTTP " .. resp.status, vim.log.levels.ERROR)
      return
    end

    local meta = parse_contest_detail(resp.body, contest_key)
    M._render_contest(contest_key, meta, url)
  end)
end

--- Render the contest detail buffer in a full-window view.
---@param contest_key string
---@param meta table parsed contest metadata
---@param url string contest URL
function M._render_contest(contest_key, meta, url)
  local description = require("dmoj.description")

  -- Build display lines
  local lines = {}
  local inline_hls = {}
  local hr_rows = {}

  -- Header (mimic description.lua layout)
  -- Row 0: empty
  table.insert(lines, "")
  -- Row 1: URL
  table.insert(lines, "  " .. url)
  -- Row 2: empty
  table.insert(lines, "")
  -- Row 3: empty
  table.insert(lines, "")
  -- Row 4: title
  table.insert(lines, "  " .. meta.title)
  -- Row 5: status line
  local status_str
  if meta.joined then
    status_str = "✔ Joined"
    if meta.time_remaining ~= "" then
      status_str = status_str .. "  ·  " .. meta.time_remaining .. " remaining"
    end
  else
    status_str = "○ Not joined"
  end
  if meta.duration_info ~= "" then
    status_str = status_str .. "  ·  " .. meta.duration_info
  end
  table.insert(lines, "  " .. status_str)
  -- Row 6: empty
  table.insert(lines, "")

  local header_end = #lines -- 7 lines (0-indexed: rows 0-6)

  -- Action hints
  local action_line
  if meta.joined then
    action_line = "  [BS] Leave contest  [o] Open in browser  [q] Close"
  else
    action_line = "  [Enter] Join contest  [o] Open in browser  [q] Close"
  end
  table.insert(lines, action_line)
  table.insert(lines, "")

  -- HR separator before description
  table.insert(lines, string.rep("─", 60))
  table.insert(hr_rows, #lines - 1) -- 0-indexed
  table.insert(lines, "")

  -- Description content
  local desc_html = meta.description_html or ""
  if vim.trim(strip_tags(desc_html)) ~= "" then
    local desc_lines, desc_hls, desc_hrs = description.html_to_lines(desc_html)
    local offset = #lines
    for _, dl in ipairs(desc_lines) do
      table.insert(lines, dl)
    end
    -- Offset the inline highlights
    if desc_hls then
      for _, hl in ipairs(desc_hls) do
        table.insert(inline_hls, {
          row = hl.row + offset,
          col_start = hl.col_start,
          col_end = hl.col_end,
          hl_group = hl.hl_group,
        })
      end
    end
    -- Offset HR rows
    if desc_hrs then
      for _, hr in ipairs(desc_hrs) do
        table.insert(hr_rows, hr + offset)
      end
    end
  else
    table.insert(lines, "  (No description available)")
  end

  table.insert(lines, "")

  -- Create buffer
  local buf_name = "dmoj://contest/" .. contest_key
  local bufnr = ui.create_buf(buf_name, lines, { filetype = "dmoj" })

  -- Apply highlights
  local ns = vim.api.nvim_create_namespace("dmoj_contest_detail")
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)

  -- URL highlight (row 1)
  pcall(vim.api.nvim_buf_add_highlight, bufnr, ns, "Comment", 1, 0, -1)
  -- Title highlight (row 4)
  pcall(vim.api.nvim_buf_add_highlight, bufnr, ns, "Title", 4, 0, -1)
  -- Status highlight (row 5)
  if meta.joined then
    pcall(vim.api.nvim_buf_add_highlight, bufnr, ns, "DiagnosticOk", 5, 0, -1)
  else
    pcall(vim.api.nvim_buf_add_highlight, bufnr, ns, "DiagnosticWarn", 5, 0, -1)
  end
  -- Action line highlight
  pcall(vim.api.nvim_buf_add_highlight, bufnr, ns, "Special", header_end, 0, -1)

  -- HR rows
  for _, hr_row in ipairs(hr_rows) do
    pcall(vim.api.nvim_buf_add_highlight, bufnr, ns, "FloatBorder", hr_row, 0, -1)
  end

  -- Inline highlights from description
  for _, hl in ipairs(inline_hls) do
    pcall(vim.api.nvim_buf_add_highlight, bufnr, ns, hl.hl_group, hl.row, hl.col_start, hl.col_end)
  end

  -- Description body highlights (simple: headers, code blocks)
  local buf_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  for i = header_end + 3, #buf_lines do -- skip header + action + hr
    local row = i - 1 -- 0-indexed
    local line = buf_lines[i]
    -- 4-space indented lines are code blocks
    if line and line:match("^    ") then
      pcall(vim.api.nvim_buf_add_highlight, bufnr, ns, "String", row, 0, -1)
    end
  end

  -- Open as full-window buffer (like dashboard)
  vim.api.nvim_set_current_buf(bufnr)

  local win = vim.api.nvim_get_current_win()
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].foldcolumn = "0"
  vim.wo[win].cursorline = false
  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true

  -- Dynamic HR resizing
  local function resize_hrs()
    if not vim.api.nvim_buf_is_valid(bufnr) then return end
    local w = vim.o.columns - 4
    if w < 10 then w = 60 end
    vim.bo[bufnr].modifiable = true
    for _, hr_row in ipairs(hr_rows) do
      if hr_row < vim.api.nvim_buf_line_count(bufnr) then
        pcall(vim.api.nvim_buf_set_lines, bufnr, hr_row, hr_row + 1, false,
          { string.rep("─", w) })
      end
    end
    vim.bo[bufnr].modifiable = false
  end

  resize_hrs()

  vim.api.nvim_create_autocmd("WinResized", {
    callback = function()
      if not vim.api.nvim_buf_is_valid(bufnr) then return true end
      resize_hrs()
    end,
  })

  -- Keymaps
  local kopts = { buffer = bufnr, nowait = true, silent = true }

  -- q: close and return to dashboard
  vim.keymap.set("n", "q", function()
    if vim.api.nvim_buf_is_valid(bufnr) then
      pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
    end
    -- Re-open the dashboard so the user doesn't land on a blank screen
    require("dmoj.dashboard").open()
  end, kopts)

  -- o: open in browser
  vim.keymap.set("n", "o", function()
    vim.fn.jobstart({ config.options.open_cmd, url }, { detach = true })
  end, kopts)

  -- <CR>: join contest (only shown if not joined)
  vim.keymap.set("n", "<CR>", function()
    if meta.joined then
      ui.notify("Already joined this contest. Press Backspace to leave.", vim.log.levels.WARN)
      return
    end
    if not meta.csrf_token then
      ui.notify("Cannot join: no CSRF token in cookie. Try :Dmoj login", vim.log.levels.ERROR)
      return
    end
    M._join_contest(contest_key, meta.csrf_token)
  end, kopts)

  -- <BS>: leave contest (only shown if joined)
  vim.keymap.set("n", "<BS>", function()
    if not meta.joined then
      ui.notify("Not in this contest. Press Enter to join.", vim.log.levels.WARN)
      return
    end
    if not meta.csrf_token then
      ui.notify("Cannot leave: no CSRF token in cookie. Try :Dmoj login", vim.log.levels.ERROR)
      return
    end
    M._leave_contest(contest_key, meta.csrf_token)
  end, kopts)
end

--- Join a contest by POSTing to /contest/CODE/join.
---@param contest_key string
---@param csrf_token string
function M._join_contest(contest_key, csrf_token)
  local headers = auth.auth_headers()
  if not headers then
    ui.notify("Not logged in.", vim.log.levels.ERROR)
    return
  end

  -- Set Referer to the contest page
  headers["Referer"] = config.options.base_url .. "/contest/" .. contest_key

  local cancel = ui.loading("Joining contest...")

  local post_url = config.options.base_url .. "/contest/" .. contest_key .. "/join"
  http.post(post_url, {
    headers = headers,
    form = { csrfmiddlewaretoken = csrf_token },
    timeout = 30,
  }, function(resp)
    cancel()

    -- DMOJ responds with 302 redirect on successful join
    if resp.status == 302 or resp.status == 301 or (resp.status >= 200 and resp.status < 300) then
      ui.notify("Joined contest: " .. contest_key, vim.log.levels.INFO)
      -- Update cached current_key immediately so picker reflects state
      M._update_current_key(contest_key)
      M.show_contest(contest_key)
    else
      ui.notify("Failed to join contest: HTTP " .. resp.status, vim.log.levels.ERROR)
    end
  end)
end

--- Leave a contest by POSTing to /contest/CODE/leave.
---@param contest_key string
---@param csrf_token string
function M._leave_contest(contest_key, csrf_token)
  local headers = auth.auth_headers()
  if not headers then
    ui.notify("Not logged in.", vim.log.levels.ERROR)
    return
  end

  headers["Referer"] = config.options.base_url .. "/contest/" .. contest_key

  local cancel = ui.loading("Leaving contest...")

  local post_url = config.options.base_url .. "/contest/" .. contest_key .. "/leave"
  http.post(post_url, {
    headers = headers,
    form = { csrfmiddlewaretoken = csrf_token },
    timeout = 30,
  }, function(resp)
    cancel()

    -- DMOJ responds with 302 redirect on successful leave
    if resp.status == 302 or resp.status == 301 or (resp.status >= 200 and resp.status < 300) then
      ui.notify("Left contest: " .. contest_key, vim.log.levels.INFO)
      -- Clear current_key immediately so picker reflects state
      M._update_current_key(nil)
      M.show_contest(contest_key)
    else
      ui.notify("Failed to leave contest: HTTP " .. resp.status, vim.log.levels.ERROR)
    end
  end)
end

return M
