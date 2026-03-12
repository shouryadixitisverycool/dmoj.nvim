local M = {}

local config = require("dmoj.config")
local ui = require("dmoj.ui")
local auth = require("dmoj.auth")

local LOGO = {
  "",
  "     /$$$$$$$  /$$      /$$  /$$$$$$     /$$$$$$",
  "    | $$__  $$| $$$    /$$$ /$$__  $$   |_  $$_/",
  "    | $$  \\ $$| $$$$  /$$$$| $$  \\ $$     | $$  ",
  "    | $$  | $$| $$ $$/$$ $$| $$  | $$     | $$  ",
  "    | $$  | $$| $$  $$$| $$| $$  | $$     | $$  ",
  "    | $$  | $$| $$\\  $ | $$| $$  | $$ /$$ | $$  ",
  "    | $$$$$$$/| $$ \\/  | $$|  $$$$$$/| $$$$$$/  ",
  "    |_______/ |__/     |__/ \\______/  \\______/   ",
  "",
}

--- Cached username so we only need to fetch once per session.
---@type string|nil|false
local cached_username = nil -- nil = not fetched, false = fetch failed, string = username

--- Fetch username asynchronously and redraw footer when ready.
---@param bufnr number
local function fetch_and_show_username(bufnr)
  if cached_username ~= nil then return end -- already fetched or attempted

  local cookie = auth.get_cookie()
  if not cookie then
    cached_username = false
    return
  end

  auth.whoami(function(username)
    if username then
      cached_username = username
    else
      cached_username = false
    end
    -- Redraw the dashboard if it's still visible
    if vim.api.nvim_buf_is_valid(bufnr) then
      local wins = vim.fn.win_findbuf(bufnr)
      if #wins > 0 then
        M.redraw(bufnr)
      end
    end
  end)
end

--- Build the dashboard lines and metadata.
--- Returns lines array and a table mapping line indices to item keys.
---@param width number
---@return string[] lines, table<number, string> key_map, number[] button_rows
local function build_dashboard(width)
  local lines = {}
  local key_map = {}    -- row -> keymap char
  local button_rows = {} -- list of row numbers that are buttons

  -- Width for the menu block (matches leetcode.nvim's 50-char button width)
  local MENU_WIDTH = 50

  local function center(s)
    local display_w = vim.fn.strdisplaywidth(s)
    local pad = math.max(0, math.floor((width - display_w) / 2))
    return string.rep(" ", pad) .. s
  end

  -- Top padding
  local top_pad = math.max(2, math.floor((vim.o.lines - 30) / 3))
  for _ = 1, top_pad do
    table.insert(lines, "")
  end

  -- Logo
  for _, line in ipairs(LOGO) do
    table.insert(lines, center(line))
  end

  table.insert(lines, "")
  table.insert(lines, center(config.options.base_url))
  table.insert(lines, "")

  -- Menu items (leetcode.nvim style)
  -- Format: " icon  Label                                    shortcut"
  -- Icon on left, shortcut key right-aligned to MENU_WIDTH
  local cookie = auth.get_cookie()

  local items = {
    { key = "p", icon = "", label = "Problems" },
    { key = "s", icon = "󰄪", label = "Submissions" },
    { key = "c", icon = "", label = "Contests" },
    { key = "o", icon = "", label = "Open in Browser" },
    { key = "i", icon = "󰆘", label = "Cookie" },
    { key = "q", icon = "󰩈", label = "Exit" },
  }

  table.insert(lines, center("Menu"))
  table.insert(lines, "")

  for _, item in ipairs(items) do
    local left = " " .. item.icon .. " " .. item.label .. " >"
    local left_w = vim.fn.strdisplaywidth(left)
    local sc = item.key
    local sc_w = vim.fn.strdisplaywidth(sc)
    local pad_count = math.max(1, MENU_WIDTH - left_w - sc_w)
    local entry = left .. string.rep(" ", pad_count) .. sc

    table.insert(lines, center(entry))
    local row = #lines
    key_map[row] = item.key
    table.insert(button_rows, row)
    table.insert(lines, "")
  end

  table.insert(lines, "")

  -- Footer: "Signed in as: username" (like leetcode.nvim)
  if cookie and cached_username and cached_username ~= false then
    table.insert(lines, center("Signed in as: " .. cached_username))
  elseif cookie then
    table.insert(lines, center("Signed in as: ..."))
  else
    table.insert(lines, center("Not signed in"))
  end

  table.insert(lines, "")
  table.insert(lines, center("dmoj.nvim"))

  return lines, key_map, button_rows
end

--- Apply highlights to dashboard buffer.
---@param bufnr number
---@param button_rows number[]
local function apply_highlights(bufnr, button_rows)
  local ns = vim.api.nvim_create_namespace("dmoj_dashboard")
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  local buf_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  -- Track which rows are buttons
  local is_button = {}
  for _, r in ipairs(button_rows) do
    is_button[r] = true
  end

  for i, line in ipairs(buf_lines) do
    local row = i - 1

    -- Logo lines (contain $)
    if line:find("%$") then
      vim.api.nvim_buf_add_highlight(bufnr, ns, "Keyword", row, 0, -1)

    -- URL line
    elseif line:find("https?://") and not line:find("Signed in") then
      vim.api.nvim_buf_add_highlight(bufnr, ns, "Comment", row, 0, -1)

    -- Button rows: icon in SpecialChar, shortcut in DiagnosticInfo
    elseif is_button[i] then
      -- Find the icon (first non-space char cluster)
      local content_start = line:find("%S")
      if content_start then
        -- Icon: first multibyte char cluster (nerd font icon, ~3 bytes)
        vim.api.nvim_buf_add_highlight(bufnr, ns, "Special", row, content_start - 1, content_start + 3)
        
        -- Find the > arrow
        local arrow_pos = line:find(">")
        if arrow_pos then
          vim.api.nvim_buf_add_highlight(bufnr, ns, "Comment", row, arrow_pos - 1, arrow_pos)
        end

        -- Shortcut key: last non-space char
        local trimmed = vim.trim(line)
        local sc = trimmed:sub(-1)
        local sc_byte_pos = #line - #line:match("%s*$") - 1
        if sc_byte_pos >= 0 then
          vim.api.nvim_buf_add_highlight(bufnr, ns, "DiagnosticInfo", row, sc_byte_pos, sc_byte_pos + #sc)
        end
      end

    -- "Signed in as:" line
    elseif line:find("Signed in as:") then
      local as_start = line:find("Signed in as:")
      if as_start then
        vim.api.nvim_buf_add_highlight(bufnr, ns, "Comment", row, 0, as_start + 12)
        vim.api.nvim_buf_add_highlight(bufnr, ns, "Normal", row, as_start + 13, -1)
      end

    -- "Not signed in" line
    elseif line:find("Not signed in") then
      vim.api.nvim_buf_add_highlight(bufnr, ns, "Comment", row, 0, -1)

    -- dmoj.nvim footer
    elseif line:find("dmoj%.nvim") then
      vim.api.nvim_buf_add_highlight(bufnr, ns, "Comment", row, 0, -1)
    end
  end
end

--- Redraw the dashboard content in an existing buffer.
---@param bufnr number
function M.redraw(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then return end

  local wins = vim.fn.win_findbuf(bufnr)
  local width = vim.o.columns
  if #wins > 0 and vim.api.nvim_win_is_valid(wins[1]) then
    width = vim.api.nvim_win_get_width(wins[1])
  end

  local lines, _, button_rows = build_dashboard(width)

  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].modifiable = false

  apply_highlights(bufnr, button_rows)
end

--- Open the DMOJ dashboard.
function M.open()
  local width = vim.o.columns
  local lines, _, button_rows = build_dashboard(width)

  -- Delete existing dashboard buffer if any
  local existing = vim.fn.bufnr("dmoj://dashboard")
  if existing ~= -1 and vim.api.nvim_buf_is_valid(existing) then
    pcall(vim.api.nvim_buf_delete, existing, { force = true })
  end

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].bufhidden = "wipe"
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].modifiable = false
  vim.bo[bufnr].filetype = "dmoj"
  vim.bo[bufnr].buflisted = false
  pcall(vim.api.nvim_buf_set_name, bufnr, "dmoj://dashboard")

  -- Fill current window
  vim.api.nvim_set_current_buf(bufnr)

  -- Window options (like leetcode.nvim)
  local win = vim.api.nvim_get_current_win()
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].foldcolumn = "0"
  vim.wo[win].cursorline = false
  vim.wo[win].cursorcolumn = false
  vim.wo[win].colorcolumn = ""
  vim.wo[win].statuscolumn = ""
  vim.wo[win].list = false
  vim.wo[win].spell = false
  vim.wo[win].wrap = false

  apply_highlights(bufnr, button_rows)

  -- Fetch username for footer (will redraw when ready)
  fetch_and_show_username(bufnr)

  -- Keymaps
  local kopts = { buffer = bufnr, nowait = true, silent = true }

  -- [p] Problems
  vim.keymap.set("n", "p", function()
    require("dmoj.problems").open()
  end, kopts)

  -- [c] Contests - open contests page in browser
  vim.keymap.set("n", "c", function()
    local url = config.options.base_url .. "/contests/"
    vim.fn.jobstart({ config.options.open_cmd, url }, { detach = true })
  end, kopts)

  -- [s] Submissions
  vim.keymap.set("n", "s", function()
    require("dmoj.submissions").open()
  end, kopts)

  -- [i] Cookie / Log In
  vim.keymap.set("n", "i", function()
    require("dmoj.auth").login()
  end, kopts)

  -- [o] Open in Browser
  vim.keymap.set("n", "o", function()
    vim.fn.jobstart({ config.options.open_cmd, config.options.base_url }, { detach = true })
  end, kopts)

  -- [q] Quit
  vim.keymap.set("n", "q", function()
    vim.cmd("quit")
  end, kopts)

  -- Enter -> Problems
  vim.keymap.set("n", "<CR>", function()
    require("dmoj.problems").open()
  end, kopts)
end

return M
