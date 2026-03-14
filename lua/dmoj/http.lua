local M = {}

local config = require("dmoj.config")

--- Wrapper around curl via vim.system / vim.fn.system.
--- Uses plenary.curl if available, otherwise falls back to vim.system.

---@class dmoj.HttpResponse
---@field status number
---@field body string
---@field headers table<string, string>

--- URL-encode a string (percent-encode all non-unreserved characters).
---@param s string
---@return string
local function url_encode(s)
  return s:gsub("([^%w%-%.%_%~])", function(c)
    return string.format("%%%02X", c:byte())
  end)
end

--- Write content to a temp file and return its path, or nil on failure.
---@param content string
---@return string|nil path
local function write_temp(content)
  local path = vim.fn.tempname()
  local f = io.open(path, "w")
  if not f then return nil end
  -- Restrict permissions immediately before writing sensitive data
  vim.fn.setfperm(path, "rw-------")
  f:write(content)
  f:close()
  return path
end

---@param method string
---@param url string
---@param opts? { headers?: table<string,string>, body?: string, form?: table<string,string>, follow_redirects?: boolean, timeout?: number }
---@param callback fun(response: dmoj.HttpResponse)
function M.request(method, url, opts, callback)
  opts = opts or {}
  local args = { "curl", "-s", "-w", "\n__DMOJ_STATUS__%{http_code}", "-X", method }

  -- Temp files to clean up after the request
  local temp_files = {}

  -- Headers: write to a temp file and use --header @file to keep them off ps aux
  if opts.headers then
    local lines = {}
    for k, v in pairs(opts.headers) do
      table.insert(lines, k .. ": " .. v)
    end
    local header_content = table.concat(lines, "\n") .. "\n"
    local hpath = write_temp(header_content)
    if hpath then
      table.insert(temp_files, hpath)
      table.insert(args, "--header")
      table.insert(args, "@" .. hpath)
    else
      -- Fallback: pass headers inline (less secure but functional)
      for k, v in pairs(opts.headers) do
        table.insert(args, "-H")
        table.insert(args, k .. ": " .. v)
      end
    end
  end

  -- Follow redirects: by default do NOT follow so we can capture Location
  if opts.follow_redirects then
    table.insert(args, "-L")
  end

  -- Include response headers in output
  table.insert(args, "-D")
  table.insert(args, "-")

  -- Form body: build url-encoded string, write to temp file, use --data @file
  if opts.form then
    local parts = {}
    for k, v in pairs(opts.form) do
      table.insert(parts, url_encode(k) .. "=" .. url_encode(v))
    end
    local form_body = table.concat(parts, "&")
    local fpath = write_temp(form_body)
    if fpath then
      table.insert(temp_files, fpath)
      table.insert(args, "--data")
      table.insert(args, "@" .. fpath)
      table.insert(args, "-H")
      table.insert(args, "Content-Type: application/x-www-form-urlencoded")
    else
      -- Fallback: pass form data inline
      for k, v in pairs(opts.form) do
        table.insert(args, "--data-urlencode")
        table.insert(args, k .. "=" .. v)
      end
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
    -- Clean up temp files immediately after curl exits
    for _, p in ipairs(temp_files) do
      os.remove(p)
    end

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
