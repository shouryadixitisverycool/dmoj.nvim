local M = {}

local config = require("dmoj.config")
local http = require("dmoj.http")
local auth = require("dmoj.auth")

---@return string
local function api_base()
  return config.options.base_url .. "/api/v2"
end

--- Generic API v2 GET request (uses API token if set, otherwise cookie).
---@param endpoint string e.g. "/problems"
---@param params? table<string,string> query params
---@param callback fun(data: table|nil, err: string|nil)
function M.get(endpoint, params, callback)
  local url = api_base() .. endpoint
  if params and next(params) then
    local parts = {}
    for k, v in pairs(params) do
      table.insert(parts, k .. "=" .. vim.uri_encode(tostring(v)))
    end
    url = url .. "?" .. table.concat(parts, "&")
  end

  local headers = auth.auth_headers() or {}
  headers["Accept"] = "application/json"

  -- Also support API token auth
  local api_token = config.options.api_token
  if api_token then
    headers["Authorization"] = "Bearer " .. api_token
  end

  http.get(url, { headers = headers, follow_redirects = true, timeout = 30 }, function(resp)
    if resp.status ~= 200 then
      callback(nil, string.format("API error: HTTP %d", resp.status))
      return
    end

    local ok, decoded = pcall(vim.json.decode, resp.body)
    if not ok then
      callback(nil, "Failed to parse JSON response")
      return
    end

    if decoded.error then
      callback(nil, decoded.error.message or "Unknown API error")
      return
    end

    callback(decoded.data, nil)
  end)
end

--- Scrape problem list from the /problems/ web page.
--- Used as fallback when the API returns 0 results (org-private instances).
---@param opts? { search?: string }
---@param callback fun(data: table|nil, err: string|nil)
local function scrape_problems(opts, callback)
  opts = opts or {}
  local headers = auth.auth_headers() or {}
  local page = opts.page or 1
  local url = config.options.base_url .. "/problems/"
  local query_parts = {}
  if page > 1 then
    table.insert(query_parts, "page=" .. tostring(page))
  end
  if opts.search then
    table.insert(query_parts, "search=" .. vim.uri_encode(opts.search))
  end
  if #query_parts > 0 then
    url = url .. "?" .. table.concat(query_parts, "&")
  end

  http.get(url, { headers = headers, follow_redirects = true, timeout = 30 }, function(resp)
    if resp.status ~= 200 then
      callback(nil, "Failed to fetch problems page: HTTP " .. resp.status)
      return
    end

    local objects = {}
    local body = resp.body

    -- Split table into rows and parse each one individually.
    -- This avoids the last-row problem of using <tr as a terminator.
    for row in body:gmatch('<tr[^>]*>(.-)</tr>') do
      local code, name = row:match(
        '<td[^>]*class="[^"]*problem[^"]*"[^>]*>%s*<a href="/problem/([^"]+)">([^<]+)</a>'
      )
      if code then
        local group = row:match('<td[^>]*class="[^"]*category[^"]*"[^>]*>([^<]*)</td>') or ""
        local points = tonumber(row:match('<td[^>]*class="[^"]*points[^"]*"[^>]*>([%d%.]+)</td>')) or 0
        table.insert(objects, {
          code = vim.trim(code),
          name = vim.trim(name),
          group = vim.trim(group),
          points = points,
          types = {},
          partial = false,
          is_public = false,
          is_organization_private = true,
        })
      end
    end

    -- If the above pattern misses rows (layout variation), try simpler pass
    if #objects == 0 then
      local seen = {}
      for code, name in body:gmatch('<a href="/problem/([a-zA-Z0-9_%-]+)">([^<]+)</a>') do
        if not seen[code] then
          seen[code] = true
          table.insert(objects, {
            code = vim.trim(code),
            name = vim.trim(name),
            group = "",
            points = 0,
            types = {},
          })
        end
      end
    end

    -- Detect pagination: look for "next page" link or page numbers
    local has_more = false
    local total_pages = page
    -- Pattern: <a href="?page=N">N</a> or <a href="/problems/?page=N">
    -- Also check for a "next" link: <a href="...page=N...">›</a> or >></a> or Next</a>
    local max_page = page
    for p in body:gmatch('[?&]page=(%d+)') do
      local pn = tonumber(p)
      if pn and pn > max_page then
        max_page = pn
      end
    end
    if max_page > page then
      has_more = true
      total_pages = max_page
    end

    callback({
      objects = objects,
      current_object_count = #objects,
      total_objects = #objects,
      total_pages = total_pages,
      page_index = page,
      has_more = has_more,
    }, nil)
  end)
end

--- Fetch paginated problem list.
--- Tries API v2 first; falls back to scraping /problems/ if API returns 0 results.
---@param opts? { page?: number, search?: string, group?: string, type?: string }
---@param callback fun(data: table|nil, err: string|nil)
function M.problems(opts, callback)
  opts = opts or {}
  local params = {}
  if opts.page then params.page = opts.page end
  if opts.search then params.search = opts.search end
  if opts.group then params.group = opts.group end
  if opts.type then params.type = opts.type end

  M.get("/problems", params, function(data, err)
    -- Fall back to scraping if API returns empty (org-private instance)
    if err or (data and data.objects and #data.objects == 0) then
      scrape_problems(opts, callback)
    else
      callback(data, err)
    end
  end)
end

--- Scrape a single problem's metadata from the web page.
---@param code string
---@param callback fun(data: table|nil, err: string|nil)
local function scrape_problem(code, callback)
  local headers = auth.auth_headers() or {}
  local url = config.options.base_url .. "/problem/" .. code

  http.get(url, { headers = headers, follow_redirects = true, timeout = 30 }, function(resp)
    if resp.status ~= 200 then
      callback(nil, "Failed to fetch problem page: HTTP " .. resp.status)
      return
    end

    local body = resp.body
    local name = body:match('<h2[^>]*>%s*(.-)%s*</h2>') or code
    name = name:gsub("<[^>]+>", "")
    name = vim.trim(name)

    local time_limit = tonumber(body:match('[Tt]ime [Ll]imit:%s*([%d%.]+)')) or 2.0
    local memory_limit = tonumber(body:match('[Mm]emory [Ll]imit:%s*(%d+)')) or 262144
    local points = tonumber(body:match('[Pp]oints:%s*([%d%.]+)')) or 0
    local group = body:match('[Gg]roup:%s*([^\n<]+)') or ""

    -- Extract allowed languages from the problem info
    local languages = {}
    local lang_block = body:match('[Aa]llowed [Ll]anguages(.-)</div>')
    if lang_block then
      for lang in lang_block:gmatch('>([^<,]+)<') do
        local l = vim.trim(lang)
        if l ~= "" then table.insert(languages, l) end
      end
    end

    callback({
      code = code,
      name = name,
      time_limit = time_limit,
      memory_limit = memory_limit,
      points = points,
      group = vim.trim(group),
      types = {},
      authors = {},
      languages = languages,
    }, nil)
  end)
end

--- Fetch a single problem's metadata.
--- Tries API v2 first; falls back to scraping the problem page.
---@param code string problem code e.g. "ccc14s4"
---@param callback fun(data: table|nil, err: string|nil)
function M.problem(code, callback)
  M.get("/problem/" .. code, nil, function(data, err)
    if data and data.object then
      callback(data.object, nil)
    else
      -- API failed (404 on org-private instances), fall back to scraping
      scrape_problem(code, callback)
    end
  end)
end

--- Fetch submission detail.
---@param id number submission id
---@param callback fun(data: table|nil, err: string|nil)
function M.submission(id, callback)
  M.get("/submission/" .. tostring(id), nil, function(data, err)
    if data and data.object then
      callback(data.object, nil)
    else
      callback(nil, err or "Submission not found")
    end
  end)
end

--- Fetch available languages.
---@param callback fun(data: table|nil, err: string|nil)
function M.languages(callback)
  M.get("/languages", nil, callback)
end

--- Fetch user submissions for a specific problem.
---@param problem_code string
---@param username string
---@param callback fun(data: table|nil, err: string|nil)
function M.user_submissions(problem_code, username, callback)
  M.get("/submissions", { problem = problem_code, user = username }, callback)
end

return M
