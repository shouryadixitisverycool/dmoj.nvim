local M = {}

--- Create a scratch buffer with the given name and content.
---@param name string buffer name
---@param lines string[] lines to set
---@param opts? { filetype?: string, width?: number, height?: number, split?: string, modifiable?: boolean }
---@return number bufnr
function M.create_buf(name, lines, opts)
  opts = opts or {}
  -- Delete any existing buffer with this name to avoid conflicts
  local existing = vim.fn.bufnr(name)
  if existing ~= -1 and vim.api.nvim_buf_is_valid(existing) then
    pcall(vim.api.nvim_buf_delete, existing, { force = true })
  end
  local bufnr = vim.api.nvim_create_buf(false, true)
  pcall(vim.api.nvim_buf_set_name, bufnr, name)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].bufhidden = "wipe"
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].modifiable = opts.modifiable or false
  if opts.filetype then
    vim.bo[bufnr].filetype = opts.filetype
  end
  return bufnr
end

--- Open a buffer in a vertical split on the left (for descriptions).
---@param bufnr number
---@param opts? { width?: number }
function M.open_split_left(bufnr, opts)
  opts = opts or {}
  local width = opts.width or math.floor(vim.o.columns * 0.4)
  vim.cmd("topleft vsplit")
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, bufnr)
  vim.api.nvim_win_set_width(win, width)
  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].foldcolumn = "0"
end

--- Open a floating window centered on screen.
---@param bufnr number
---@param opts? { width?: number, height?: number, title?: string }
---@return number win_id
function M.open_float(bufnr, opts)
  opts = opts or {}
  local width = opts.width or math.floor(vim.o.columns * 0.8)
  local height = opts.height or math.floor(vim.o.lines * 0.8)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  local win_opts = {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
  }
  if opts.title then
    win_opts.title = " " .. opts.title .. " "
    win_opts.title_pos = "center"
  end

  local win = vim.api.nvim_open_win(bufnr, true, win_opts)
  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true
  vim.wo[win].cursorline = true

  -- Close on q or <Esc>
  vim.keymap.set("n", "q", function()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end, { buffer = bufnr, nowait = true })
  vim.keymap.set("n", "<Esc>", function()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end, { buffer = bufnr, nowait = true })

  return win
end

--- Simple notification helper.
---@param msg string
---@param level? number vim.log.levels.*
function M.notify(msg, level)
  vim.notify("[dmoj] " .. msg, level or vim.log.levels.INFO)
end

--- Display a loading spinner message that can be cleared.
---@param msg string
---@return fun() cancel function to clear the message
function M.loading(msg)
  local frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
  local idx = 1
  local timer = vim.uv.new_timer()
  local cancelled = false

  timer:start(0, 100, vim.schedule_wrap(function()
    if cancelled then return end
    vim.api.nvim_echo({ { frames[idx] .. " " .. msg, "Comment" } }, false, {})
    idx = (idx % #frames) + 1
  end))

  return function()
    cancelled = true
    if timer and not timer:is_closing() then
      timer:stop()
      timer:close()
    end
    vim.api.nvim_echo({ { "" } }, false, {})
  end
end

return M
