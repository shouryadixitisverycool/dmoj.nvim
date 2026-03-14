local M = {}

---@class dmoj.Config
---@field base_url string
---@field lang string
---@field storage_dir string
---@field keymaps table<string, string>
---@field open_cmd string
---@field arg string CLI argument to trigger direct-launch (e.g. "nvim dmoj.nvim")

--- Detect the correct "open URL" command for the current OS.
---@return string
local function detect_open_cmd()
  if vim.fn.has("mac") == 1 then
    return "open"
  else
    -- Linux (and other Unix-likes)
    return "xdg-open"
  end
end

---@type dmoj.Config
M.defaults = {
  base_url = "https://dmoj.ca",
  lang = "CPP17",
  storage_dir = vim.fn.stdpath("data") .. "/dmoj",
  keymaps = {
    submit = "<leader>ds",
    test = "<leader>dt",
    list = "<leader>dl",
    desc = "<leader>dd",
    open_browser = "<leader>do",
  },
  open_cmd = detect_open_cmd(),
  arg = "dmoj.nvim",     -- launch arg: `nvim dmoj.nvim` opens the dashboard
}

---@type dmoj.Config
M.options = {}

---@param opts? table
function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", {}, M.defaults, opts or {})
  vim.fn.mkdir(M.options.storage_dir, "p")
end

return M
