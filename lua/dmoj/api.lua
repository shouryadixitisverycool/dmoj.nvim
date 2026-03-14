local M = {}

local config = require("dmoj.config")
local http = require("dmoj.http")
local auth = require("dmoj.auth")

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
  s = s:gsub("\xc2\xa0", " ")
  s = s:gsub("&#(%d+);", function(n)
    local num = tonumber(n)
    if num and num < 128 then return string.char(num) end
    return ""
  end)
  return s
end

--- Fetch paginated problem list by scraping the /problems/ web page.
---@param opts? { page?: number, search?: string }
---@param callback fun(data: table|nil, err: string|nil)
function M.problems(opts, callback)
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
        -- Points column: DMOJ uses class="p" (some instances) or class="points"
        -- Content may include suffix like "100p" or just "100"
        local points_str = row:match('<td[^>]*class="p"[^>]*>([^<]*)</td>')
          or row:match('<td[^>]*class="[^"]*points[^"]*"[^>]*>([^<]*)</td>')
          or "0"
        local points = tonumber(points_str:match("([%d%.]+)")) or 0
        -- Extract solve status from <td solved="1|0|-1"> (DMOJ template)
        -- solved="1" = accepted (green check), solved="0" = attempted (yellow/red minus),
        -- solved="-1" or absent = not attempted
        local solved_attr = row:match('<td%s+solved="([^"]*)"')
        local status = "none" -- not attempted
        if solved_attr == "1" then
          status = "ac"
        elseif solved_attr == "0" then
          status = "attempted"
        end
        table.insert(objects, {
          code = vim.trim(code),
          name = decode_entities(vim.trim(name)),
          group = vim.trim(group),
          points = points,
          status = status,
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

--- Fetch a single problem's metadata by scraping the problem page.
---@param code string problem code e.g. "ccc14s4"
---@param callback fun(data: table|nil, err: string|nil)
function M.problem(code, callback)
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
    name = decode_entities(vim.trim(name))

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

return M
