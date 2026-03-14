local M = {}

local config = require("dmoj.config")
local http = require("dmoj.http")

local cookie_file = nil

---@return string
local function get_cookie_path()
  if not cookie_file then
    cookie_file = config.options.storage_dir .. "/cookie.txt"
  end
  return cookie_file
end

--- Read stored cookie string from disk.
---@return string|nil
function M.get_cookie()
  local path = get_cookie_path()
  local f = io.open(path, "r")
  if not f then
    return nil
  end
  local cookie = f:read("*a")
  f:close()
  cookie = vim.trim(cookie)
  if cookie == "" then
    return nil
  end
  return cookie
end

--- Persist cookie string to disk.
---@param cookie string
function M.save_cookie(cookie)
  local path = get_cookie_path()
  -- Create (or truncate) with restricted permissions BEFORE writing,
  -- eliminating the TOCTOU race where io.open would create a world-readable file.
  vim.fn.writefile({}, path)
  vim.fn.setfperm(path, "rw-------")
  local f = io.open(path, "w")
  if not f then
    vim.notify("[dmoj] Failed to write cookie file: " .. path, vim.log.levels.ERROR)
    return
  end
  f:write(cookie)
  f:close()
end

--- Delete stored cookie.
function M.delete_cookie()
  local path = get_cookie_path()
  os.remove(path)
  vim.notify("[dmoj] Cookie deleted. You are logged out.", vim.log.levels.INFO)
end

--- Prompt user to paste their cookie string.
--- They should copy `csrftoken=...; sessionid=...` from their browser.
function M.login()
  vim.ui.input({
    prompt = "Paste your DMOJ cookie (csrftoken=...; sessionid=...): ",
  }, function(input)
    if not input or vim.trim(input) == "" then
      vim.notify("[dmoj] Login cancelled.", vim.log.levels.WARN)
      return
    end
    local cookie = vim.trim(input)
    -- Validate by scraping the homepage for the logged-in username
    M.save_cookie(cookie)
    vim.notify("[dmoj] Cookie saved. Verifying...", vim.log.levels.INFO)
    M.whoami(function(username)
      if username then
        vim.notify("[dmoj] Logged in as: " .. username, vim.log.levels.INFO)
      else
        vim.notify("[dmoj] Could not verify login (cookie saved anyway). Check :Dmoj whoami after a moment.", vim.log.levels.WARN)
      end
    end)
  end)
end

--- Get the CSRF token from the stored cookie string.
---@return string|nil
function M.get_csrf_token()
  local cookie = M.get_cookie()
  if not cookie then
    return nil
  end
  local token = cookie:match("csrftoken=([^;%s]+)")
  return token
end

--- Build a User-Agent string reflecting the actual OS.
---@return string
local function build_ua()
  if vim.fn.has("mac") == 1 then
    return "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
  else
    return "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
  end
end

local UA = build_ua()

--- Build common headers for authenticated requests.
---@return table<string,string>|nil headers, or nil if not logged in
function M.auth_headers()
  local cookie = M.get_cookie()
  if not cookie then
    return nil
  end
  local csrf = M.get_csrf_token()
  local headers = {
    ["Cookie"] = cookie,
    ["Referer"] = config.options.base_url .. "/",
    ["User-Agent"] = UA,
  }
  if csrf then
    headers["X-CSRFToken"] = csrf
  end
  return headers
end

--- Check who we are logged in as.
--- DMOJ navbar renders: Hello, <display_name>. inside a <span>
--- We also check request.user.username from the inline JS block.
---@param callback fun(username: string|nil)
function M.whoami(callback)
  local headers = M.auth_headers()
  if not headers then
    callback(nil)
    return
  end

  http.get(config.options.base_url .. "/", { headers = headers, follow_redirects = true }, function(resp)
    if resp.status ~= 200 then
      callback(nil)
      return
    end

    -- Primary: JS block contains: name: '<username>'
    local username = resp.body:match("name:%s*'([^']+)'")

    -- Fallback: Hello, <display_name>. in the navbar span
    if not username then
      local greeting = resp.body:match("Hello,%s*(.-)%.")
      if greeting then
        -- strip any HTML tags from display name
        username = greeting:gsub("<[^>]+>", "")
        username = vim.trim(username)
        if username == "" then username = nil end
      end
    end

    -- Fallback: /accounts/logout/ only appears when logged in
    if not username and resp.body:find("/accounts/logout/", 1, true) then
      username = "unknown"
    end

    callback(username)
  end)
end

return M
