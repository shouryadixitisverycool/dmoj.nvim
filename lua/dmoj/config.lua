local M = {}

---@class dmoj.Config
---@field base_url string
---@field lang string
---@field storage_dir string
---@field keymaps table<string, string>
---@field open_cmd string
---@field api_token? string

---@type dmoj.Config
M.defaults = {
  base_url = "https://dmoj.ca",
  lang = "CPP17",
  api_token = nil, -- Optional: DMOJ API token for authenticated API requests
  storage_dir = vim.fn.stdpath("data") .. "/dmoj",
  keymaps = {
    submit = "<leader>ds",
    test = "<leader>dt",
    list = "<leader>dl",
    desc = "<leader>dd",
    open_browser = "<leader>do",
  },
  open_cmd = "xdg-open", -- macOS: "open", Windows: "start"
}

---@type dmoj.Config
M.options = {}

---@param opts? table
function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", {}, M.defaults, opts or {})
  vim.fn.mkdir(M.options.storage_dir, "p")
end

return M
