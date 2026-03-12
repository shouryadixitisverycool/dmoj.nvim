local M = {}

local config = require("dmoj.config")

--- Wrapper around curl via vim.system / vim.fn.system.
--- Uses plenary.curl if available, otherwise falls back to vim.system.

---@class dmoj.HttpResponse
---@field status number
---@field body string
---@field headers table<string, string>

---@param method string
---@param url string
---@param opts? { headers?: table<string,string>, body?: string, form?: table<string,string>, follow_redirects?: boolean, timeout?: number }
---@param callback fun(response: dmoj.HttpResponse)
function M.request(method, url, opts, callback)
  opts = opts or {}
  local args = { "curl", "-s", "-w", "\n__DMOJ_STATUS__%{http_code}", "-X", method }

  -- Headers
  if opts.headers then
    for k, v in pairs(opts.headers) do
      table.insert(args, "-H")
      table.insert(args, k .. ": " .. v)
    end
  end

  -- Follow redirects: by default do NOT follow so we can capture Location
  if opts.follow_redirects then
    table.insert(args, "-L")
  end

  -- Include response headers in output
  table.insert(args, "-D")
  table.insert(args, "-")

  -- Form body (application/x-www-form-urlencoded)
  if opts.form then
    for k, v in pairs(opts.form) do
      table.insert(args, "--data-urlencode")
      table.insert(args, k .. "=" .. v)
    end
  end

  -- Raw body
  if opts.body then
    table.insert(args, "-d")
    table.insert(args, opts.body)
  end

  -- Timeout
  if opts.timeout then
    table.insert(args, "--max-time")
    table.insert(args, tostring(opts.timeout))
  end

  table.insert(args, url)

  vim.system(args, { text = true }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        callback({
          status = 0,
          body = result.stderr or "curl failed",
          headers = {},
        })
        return
      end

      local output = result.stdout or ""

      -- Extract HTTP status from our sentinel
      local status_code = 0
      local body = output
      local status_match = output:match("__DMOJ_STATUS__(%d+)%s*$")
      if status_match then
        status_code = tonumber(status_match) or 0
        body = output:gsub("__DMOJ_STATUS__%d+%s*$", "")
      end

      -- Split headers from body (separated by \r\n\r\n)
      local headers_raw, response_body = "", body
      local sep = body:find("\r\n\r\n")
      if sep then
        headers_raw = body:sub(1, sep - 1)
        response_body = body:sub(sep + 4)
        -- Handle multiple header blocks (100 Continue, redirects)
        while true do
          local next_sep = response_body:find("\r\n\r\n")
          local starts_with_http = response_body:match("^HTTP/")
          if next_sep and starts_with_http then
            headers_raw = response_body:sub(1, next_sep - 1)
            response_body = response_body:sub(next_sep + 4)
          else
            break
          end
        end
      end

      -- Parse headers into table
      local headers = {}
      for line in headers_raw:gmatch("[^\r\n]+") do
        local key, value = line:match("^(.-):%s*(.+)$")
        if key then
          headers[key:lower()] = value
        end
      end

      callback({
        status = status_code,
        body = response_body,
        headers = headers,
      })
    end)
  end)
end

---@param url string
---@param opts? table
---@param callback fun(response: dmoj.HttpResponse)
function M.get(url, opts, callback)
  M.request("GET", url, opts, callback)
end

---@param url string
---@param opts? table
---@param callback fun(response: dmoj.HttpResponse)
function M.post(url, opts, callback)
  M.request("POST", url, opts, callback)
end

return M
