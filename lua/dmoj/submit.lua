local M = {}

local config = require("dmoj.config")
local http = require("dmoj.http")
local auth = require("dmoj.auth")
local ui = require("dmoj.ui")

--- Derive the correct verdict from test cases and points.
--- Centralizes logic that was previously duplicated across scrape/poll/show.
--- Handles both flat case lists and mixed lists containing batch groups.
---@param cases table[] list of test case objects (type="case") or batch groups (type="batch")
---@param case_points number points earned
---@param case_total number total possible points
---@param current_result string current result string
---@return string result the derived verdict
local function derive_result(cases, case_points, case_total, current_result)
  local result = current_result or "??"
  if cases and #cases > 0 then
    -- Flatten: collect all individual case statuses, including from batch groups
    local flat_cases = {}
    for _, c in ipairs(cases) do
      if c.type == "batch" and c.cases then
        for _, bc in ipairs(c.cases) do
          table.insert(flat_cases, bc)
        end
      elseif c.status then
        table.insert(flat_cases, c)
      end
    end

    if #flat_cases > 0 then
      local counts = {}
      local all_ac = true

      for _, c in ipairs(flat_cases) do
        if c.status ~= "AC" then
          all_ac = false
        end
        counts[c.status] = (counts[c.status] or 0) + 1
      end
    
    if all_ac then
      result = "AC"
    else
      -- Priority for tie-breakers (lower index = higher priority)
      local priority = { IE=1, CE=2, IR=3, RTE=4, MLE=5, TLE=6, OLE=7, WA=8, AC=99 }
      
      local best_status = nil
      local best_count = -1
      
      for status, count in pairs(counts) do
        if status ~= "AC" then
          if count > best_count then
            best_status = status
            best_count = count
          elseif count == best_count then
            local p1 = priority[status] or 50
            local p2 = priority[best_status] or 50
            if p1 < p2 then
              best_status = status
            end
          end
        end
      end
      
      if best_status then
        result = best_status
      end
    end
    end
  end

  local pts = case_points or 0
  local tot = case_total or 0
  if tot > 0 and pts >= tot and result ~= "AC" then
    result = "AC"
  elseif tot > 0 and pts == 0 and result == "AC" then
    result = "WA"
  end
  return result
end

--- Language key -> DMOJ language ID cache, keyed by problem code.
---@type table<string, table<string, number>>
local lang_id_cache = {}

M._result_bufs = {}


--- Fetch language IDs from the submit page HTML.
---@param problem_code string
---@param callback fun(lang_map: table<string, number>|nil, err: string|nil)
local function fetch_language_ids(problem_code, callback)
  if lang_id_cache[problem_code] then
    callback(lang_id_cache[problem_code], nil)
    return
  end

  local headers = auth.auth_headers()
  if not headers then
    callback(nil, "Not logged in")
    return
  end

  local url = config.options.base_url .. "/problem/" .. problem_code .. "/submit"
  http.get(url, { headers = headers, follow_redirects = true, timeout = 30 }, function(resp)
    if resp.status ~= 200 then
      callback(nil, "Failed to load submit page: HTTP " .. resp.status)
      return
    end

    local map = {}
    for id_str, name in resp.body:gmatch('<option%s+value="(%d+)"[^>]*>([^<]+)</option>') do
      local id = tonumber(id_str)
      if id then
        map[vim.trim(name)] = id
      end
    end

    for id_str, key in resp.body:gmatch('<option%s+value="(%d+)"[^>]*data%-ace="([^"]*)"') do
      local id = tonumber(id_str)
      if id then
        map["ace:" .. key] = id
      end
    end

    for val, _, data_name in resp.body:gmatch('<option%s+value="(%d+)"%s+data%-id="(%d+)"%s+data%-name="([^"]*)"') do
      local id = tonumber(val)
      if id and data_name then
        map[data_name] = id
      end
    end

    if not next(map) then
      callback(nil, "Could not parse language options from submit page")
      return
    end

    lang_id_cache[problem_code] = map
    callback(map, nil)
  end)
end

--- Resolve a DMOJ language key to the integer form ID.
---@param lang_key string
---@param lang_map table<string, number>
---@return number|nil
local function resolve_lang_id(lang_key, lang_map)
  if lang_map[lang_key] then
    return lang_map[lang_key]
  end

  local key_to_names = {
    CPP03 = { "C++ 03", "C++03" },
    CPP11 = { "C++ 11", "C++11" },
    CPP14 = { "C++ 14", "C++14" },
    CPP17 = { "C++ 17", "C++17" },
    CPP20 = { "C++ 20", "C++20" },
    CPP23 = { "C++ 23", "C++23" },
    C = { "C", "C 99", "C99" },
    C11 = { "C 11", "C11" },
    JAVA = { "Java", "Java 8", "Java8" },
    JAVA8 = { "Java 8", "Java8" },
    JAVA11 = { "Java 11", "Java11" },
    JAVA17 = { "Java 17", "Java17" },
    JAVA21 = { "Java 21", "Java21" },
    PY2 = { "Python 2", "Python2" },
    PY3 = { "Python 3", "Python3" },
    PYPY = { "PyPy", "PyPy 2" },
    PYPY3 = { "PyPy 3", "PyPy3" },
    RUBY = { "Ruby" },
    RUST = { "Rust" },
    GO = { "Go" },
    KOTLIN = { "Kotlin" },
    SWIFT = { "Swift" },
    HASK = { "Haskell" },
    LUA = { "Lua" },
    PERL = { "Perl" },
    PHP = { "PHP" },
    PAS = { "Pascal" },
    SCALA = { "Scala" },
    DART = { "Dart" },
    OCAML = { "OCaml" },
    NASM = { "NASM", "x86 Assembly" },
    TEXT = { "Text" },
    MONO = { "Mono C#", "C#" },
  }

  local names = key_to_names[lang_key]
  if names then
    for _, name in ipairs(names) do
      if lang_map[name] then
        return lang_map[name]
      end
    end
  end

  local lower_key = lang_key:lower()
  for name, id in pairs(lang_map) do
    if name:lower():find(lower_key, 1, true) then
      return id
    end
  end

  return nil
end

--- Submit the current buffer to DMOJ.
---@param opts? { problem_code?: string, lang?: string }
function M.submit(opts)
  opts = opts or {}
  local bufnr = vim.api.nvim_get_current_buf()
  local problem_code = opts.problem_code or vim.b[bufnr].dmoj_problem_code
  local lang = opts.lang or vim.b[bufnr].dmoj_language or config.options.lang

  if not problem_code then
    vim.ui.input({ prompt = "Problem code to submit to: " }, function(input)
      if input and vim.trim(input) ~= "" then
        M.submit({ problem_code = vim.trim(input), lang = lang })
      end
    end)
    return
  end

  local headers = auth.auth_headers()
  if not headers then
    ui.notify("Not logged in. Run :Dmoj login first.", vim.log.levels.ERROR)
    return
  end

  -- Read source from current buffer
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local source = table.concat(lines, "\n")

  if vim.trim(source) == "" then
    ui.notify("Buffer is empty, nothing to submit.", vim.log.levels.WARN)
    return
  end

  if #source > 65536 then
    ui.notify("Source code exceeds 65536 character limit.", vim.log.levels.ERROR)
    return
  end

  local cancel = ui.loading("Preparing submission for " .. problem_code .. "...")

  fetch_language_ids(problem_code, function(lang_map, err)
    if err then
      cancel()
      ui.notify(err, vim.log.levels.ERROR)
      return
    end

    if not lang then
      cancel()
      ui.notify("No language specified. Set vim.g.dmoj_language or config.options.lang", vim.log.levels.ERROR)
      return
    end

    local lang_id = resolve_lang_id(lang, lang_map)
    if not lang_id then
      cancel()
      local available = {}
      for name, _ in pairs(lang_map) do
        if not name:find("^ace:") then
          table.insert(available, name)
        end
      end
      table.sort(available)
      ui.notify(
        "Could not resolve language '" .. lang .. "'. Available: " .. table.concat(available, ", "),
        vim.log.levels.ERROR
      )
      return
    end

    cancel()
    local cancel2 = ui.loading("Submitting " .. problem_code .. " (" .. lang .. ")...")

    local csrf = auth.get_csrf_token()
    if not csrf then
      cancel2()
      ui.notify("No CSRF token found in cookie.", vim.log.levels.ERROR)
      return
    end

    local submit_url = config.options.base_url .. "/problem/" .. problem_code .. "/submit"
    headers["Referer"] = submit_url
    headers["Content-Type"] = "application/x-www-form-urlencoded"

    http.post(submit_url, {
      headers = headers,
      form = {
        csrfmiddlewaretoken = csrf,
        language = tostring(lang_id),
        source = source,
        judge = "",
      },
      timeout = 30,
    }, function(resp)
      cancel2()

      --- Helper: try to extract a submission ID from a string (URL, body, etc.)
      local function extract_submission_id(s)
        if not s or s == "" then return nil end
        -- Try common patterns
        return s:match("/submission/(%d+)")
          or s:match("/submissions/(%d+)")
          or s:match("submission_id=(%d+)")
          or s:match("submission/(%d+)")
      end

      if resp.status == 302 or resp.status == 301 then
        local location = resp.headers["location"] or ""
        local submission_id = extract_submission_id(location)

        if submission_id then
          M.poll_result(tonumber(submission_id))
        else
          -- Also check the response body (some servers include it in 302 body)
          submission_id = extract_submission_id(resp.body)
          if submission_id then
            M.poll_result(tonumber(submission_id))
          elseif location ~= "" then
            -- Follow the redirect to find the submission ID
            M._follow_redirect_for_id(location, problem_code, headers)
          else
            -- Last resort: scrape recent submissions for this problem
            M._find_latest_submission(problem_code, headers)
          end
        end
      elseif resp.status == 200 then
        -- Check if 200 is actually a redirect page (some setups return 200 with redirect)
        local meta_redirect = resp.body:match('url=/submission/(%d+)')
        if meta_redirect then
          M.poll_result(tonumber(meta_redirect))
          return
        end

        -- Check if the body contains a submission ID link
        local body_sub_id = extract_submission_id(resp.body)
        if body_sub_id then
          M.poll_result(tonumber(body_sub_id))
          return
        end

        local error_msg = resp.body:match('<ul class="errorlist">(.-)</ul>')
        if error_msg then
          error_msg = error_msg:gsub("<[^>]+>", ""):gsub("%s+", " ")
          ui.notify("Submission error: " .. vim.trim(error_msg), vim.log.levels.ERROR)
        else
          ui.notify("Submission failed (form re-rendered). Check your code/language.", vim.log.levels.ERROR)
        end
      elseif resp.status == 429 then
        ui.notify("Rate limited. Wait before submitting again.", vim.log.levels.WARN)
      else
        ui.notify("Submission failed: HTTP " .. resp.status, vim.log.levels.ERROR)
      end
    end)
  end)
end

--- Follow a redirect URL to extract the submission ID from the destination page.
---@param location string redirect URL (may be relative)
---@param problem_code string
---@param req_headers table
function M._follow_redirect_for_id(location, problem_code, req_headers)
  -- Resolve relative URLs
  local url = location
  if not url:match("^https?://") then
    url = config.options.base_url .. (url:sub(1, 1) == "/" and "" or "/") .. url
  end

  http.get(url, { headers = req_headers, follow_redirects = true, timeout = 30 }, function(resp)
    if resp.status ~= 200 then
      -- Fall back to scraping recent submissions
      M._find_latest_submission(problem_code, req_headers)
      return
    end

    -- Try to find submission ID in the response body
    local submission_id = resp.body:match("/submission/(%d+)")
      or resp.body:match("submission%-id[^>]*>%s*(%d+)")
      or resp.body:match('data%-id="(%d+)"')
    if submission_id then
      M.poll_result(tonumber(submission_id))
    else
      M._find_latest_submission(problem_code, req_headers)
    end
  end)
end

--- Scrape the user's recent submissions to find the latest one for this problem.
---@param problem_code string
---@param req_headers table
function M._find_latest_submission(problem_code, req_headers)
  local url = config.options.base_url .. "/problem/" .. problem_code .. "/submissions/"

  http.get(url, { headers = req_headers, follow_redirects = true, timeout = 30 }, function(resp)
    if resp.status ~= 200 then
      ui.notify("Submitted, but could not find submission ID. Check your submissions page.", vim.log.levels.WARN)
      return
    end

    -- Find the most recent submission ID (first one in the page, largest number)
    local max_id = nil
    for id_str in resp.body:gmatch("/submission/(%d+)") do
      local id = tonumber(id_str)
      if id and (not max_id or id > max_id) then
        max_id = id
      end
    end

    if max_id then
      M.poll_result(max_id)
    else
      -- Try the general submissions page
      local gen_url = config.options.base_url .. "/submissions/"
      http.get(gen_url, { headers = req_headers, follow_redirects = true, timeout = 30 }, function(resp2)
        if resp2.status == 200 then
          local gen_max_id = nil
          -- Look for submissions for our specific problem
          for id_str in resp2.body:gmatch("/submission/(%d+)") do
            local id = tonumber(id_str)
            if id and (not gen_max_id or id > gen_max_id) then
              gen_max_id = id
            end
          end
          if gen_max_id then
            M.poll_result(gen_max_id)
            return
          end
        end
        ui.notify("Submitted, but could not find submission ID. Check your submissions page.", vim.log.levels.WARN)
      end)
    end
  end)
end

--- Normalize whitespace in scraped text: convert non-breaking spaces (UTF-8
--- \xc2\xa0 from Django's avoid_wrapping) and HTML entities to regular spaces.
---@param s string
---@return string
local function normalize_ws(s)
  s = s:gsub("\xc2\xa0", " ")   -- UTF-8 non-breaking space
  s = s:gsub("&nbsp;", " ")
  s = s:gsub("&amp;", "&")
  s = s:gsub("&lt;", "<")
  s = s:gsub("&gt;", ">")
  s = s:gsub("&mdash;", "—")
  s = s:gsub("&ndash;", "–")
  s = s:gsub("&times;", "×")
  return s
end

--- Parse a memory string like "1.58 MB" or "256 KB" into KB.
--- Handles B, KB, MB, GB, TB units.
---@param mem_str string e.g. "1.58" or "256"
---@param unit_str string e.g. "MB", "KB", "B"
---@return number memory_in_kb
local function parse_memory_kb(mem_str, unit_str)
  local m = tonumber(mem_str) or 0
  local u = unit_str:upper()
  if u == "B" then return m / 1024
  elseif u == "KB" then return m
  elseif u == "MB" then return m * 1024
  elseif u == "GB" then return m * 1024 * 1024
  elseif u == "TB" then return m * 1024 * 1024 * 1024
  end
  -- Single-char fallback: "K" -> KB, "M" -> MB, etc.
  if u:sub(1, 1) == "K" then return m
  elseif u:sub(1, 1) == "M" then return m * 1024
  elseif u:sub(1, 1) == "G" then return m * 1024 * 1024
  end
  return m
end

--- Parse a time string that may be a normal float or ">" prefixed (TLE)
--- or "---" (overall TLE). Returns the numeric value or 0.
---@param time_str string e.g. "0.085", ">2.000", "---"
---@return number
local function parse_time(time_str)
  if not time_str or time_str == "---" or time_str == "" then return 0 end
  -- Strip leading ">" for TLE cases (template: [>Xs,])
  local stripped = time_str:gsub("^>", "")
  return tonumber(stripped) or 0
end

--- Parse resource bracket like "[0.007s, 1.20 MB]" or "[>2.000s, 256 KB]"
--- from tag-stripped text. Returns time, memory_kb or nil.
---@param text string the text fragment to parse
---@return number|nil time
---@return number|nil memory_kb
local function parse_resources_bracket(text)
  -- After tag stripping, the bracket looks like:
  --   [0.007s,1.20 MB]  or  [>2.000s,256 KB]  or  [---,1.58 MB]
  -- With possible spaces collapsed or present.
  local time_str, mem_str, unit =
    text:match("%[%s*(>?[%d%.%-]+)s?,%s*([%d%.]+)%s*(%a+)%s*%]")
  if not time_str then
    -- Try without trailing "s" on time (in case "---," has no "s")
    time_str, mem_str, unit =
      text:match("%[%s*(%-%-%-),?%s*([%d%.]+)%s*(%a+)%s*%]")
  end
  if time_str then
    return parse_time(time_str), parse_memory_kb(mem_str, unit)
  end
  return nil, nil
end

--- Scrape test case details from the submission page HTML.
--- Returns a list of case/batch tables, or empty table if none found.
---@param body string raw HTML body (NOT tag-stripped)
---@return table[] cases
local function scrape_test_cases(body)
  local cases = {}

  -- Normalize the HTML: convert entities and non-breaking spaces
  local html = normalize_ws(body)

  -- Strategy 1: Parse the submissions-status-table rows.
  -- Each test case row contains cells like:
  --   <td><b>Test case #1:</b></td>
  --   <td><span class="case-AC">AC</span></td>
  --   <td>[<span>0.007s,</span></td>
  --   <td>1.20 MB]</td>
  --   <td>(10/10)</td>      -- only for non-batched cases
  --
  -- For batched cases, the heading is "Case #N:" and there's no points column.
  -- Batches are preceded by: <b>Batch #N</b>(X/Y points)

  -- Detect batches: <b>Batch #N</b> ... (X/Y points)
  -- We'll track batch boundaries by scanning for batch headers in the HTML.
  local batch_positions = {}
  for batch_start, batch_id, batch_rest in
    html:gmatch("()Batch #(%d+)</b>(.-)<%s*table")
  do
    local bp, bt = batch_rest:match("(%d+)/(%d+)%s*points?")
    table.insert(batch_positions, {
      pos = batch_start,
      id = tonumber(batch_id) or 0,
      points = tonumber(bp) or 0,
      total = tonumber(bt) or 0,
    })
  end

  -- Now parse each table row (case row)
  -- We look for <tr> blocks containing case info, tracking position in HTML
  for row_start, row_html in html:gmatch("()<tr[^>]*class=\"case%-row[^\"]*\"[^>]*>(.-)</tr>") do
    -- Extract the cells by stripping tags from each <td>
    local cells = {}
    for td_content in row_html:gmatch("<td[^>]*>(.-)</td>") do
      -- Strip HTML tags but preserve text
      local cell_text = td_content:gsub("<[^>]+>", "")
      table.insert(cells, vim.trim(cell_text))
    end

    if #cells >= 2 then
      -- Cell 1: "Test case #1:" or "Case #1:" or "Pretest #1:"
      local case_id = cells[1]:match("#(%d+)")
      local is_batched = cells[1]:match("^Case #") ~= nil

      -- Cell 2: verdict like "AC", "WA", "TLE", etc. May have feedback: "WA (wrong output)"
      local status_text = cells[2]
      -- The status may contain an em-dash for SC (short-circuited)
      if status_text == "—" or status_text == "–" then
        status_text = "SC"
      end
      local status = status_text:match("^(%u+)") or status_text
      local feedback = status_text:match("%((.-)%)") or ""

      -- Cells 3-4: resource bracket parts "[0.007s," and "1.20 MB]"
      local time_val = 0
      local mem_val = 0
      if #cells >= 4 then
        -- Reconstruct the bracket from cells 3 and 4
        local bracket = cells[3] .. " " .. cells[4]
        local t, m = parse_resources_bracket(bracket)
        if t then time_val = t end
        if m then mem_val = m end
      end

      -- Cell 5 (optional): points "(10/10)" — only for non-batched cases
      local pts = 0
      local tot = 0
      if not is_batched and #cells >= 5 then
        local p, t = cells[5]:match("(%d+)/(%d+)")
        pts = tonumber(p) or 0
        tot = tonumber(t) or 0
      end

      local case_entry = {
        type = "case",
        case_id = tonumber(case_id) or 0,
        status = vim.trim(status):upper(),
        extra = vim.trim(feedback),
        time = time_val,
        memory = mem_val,
        points = pts,
        total = tot,
        _html_pos = row_start,  -- track position for batch assignment
      }

      -- Check if this case belongs to a batch
      if is_batched then
        case_entry._batched = true
      end

      table.insert(cases, case_entry)
    end
  end

  -- Strategy 2: If Strategy 1 found nothing, try tag-stripped text parsing.
  -- This is a fallback for non-standard DMOJ instances or custom templates.
  if #cases == 0 then
    local plain = normalize_ws(html:gsub("<[^>]+>", " "))
    -- Collapse multiple spaces
    plain = plain:gsub("%s+", " ")

    -- Pattern: "Test case #1: AC [0.007s, 1.20 MB] (10/10)"
    -- Or:      "Case #1: WA [>2.000s, 256 KB]"
    -- Or:      "Test case #1: SC"  (short-circuited, no bracket)
    for label, case_id, status_chunk in
      plain:gmatch("(Test case%s+#(%d+):%s*(.-))")
    do
      -- Limit the chunk to avoid spanning across cases
      -- Find the next "Test case" or "Case #" or "Batch #" or "Resources:" or end
      local chunk_end = status_chunk:find("Test case%s+#")
        or status_chunk:find("Case%s+#")
        or status_chunk:find("Batch%s+#")
        or status_chunk:find("Resources:")
        or status_chunk:find("Final score:")
        or #status_chunk + 1
      local chunk = status_chunk:sub(1, chunk_end - 1)

      local status = chunk:match("^(%u+)") or chunk:match("^(—)") or "?"
      if status == "—" or status == "–" then status = "SC" end
      local feedback = chunk:match("%(([^%d][^%)]*%)") or ""

      local time_val, mem_val = parse_resources_bracket(chunk)

      local pts, tot = 0, 0
      -- Match points like (10/10) but not the resource bracket's content
      local pts_str, tot_str = chunk:match("%]%s*%((%d+)/(%d+)%)")
      if pts_str then
        pts = tonumber(pts_str) or 0
        tot = tonumber(tot_str) or 0
      end

      table.insert(cases, {
        type = "case",
        case_id = tonumber(case_id) or 0,
        status = vim.trim(status):upper(),
        extra = vim.trim(feedback),
        time = time_val or 0,
        memory = mem_val or 0,
        points = pts,
        total = tot,
      })
    end

    -- Also try "Case #N:" (batched) pattern
    for case_id, status_chunk in
      plain:gmatch("Case%s+#(%d+):%s*(.-)%s*Case%s+#")
    do
      local status = status_chunk:match("^(%u+)") or "?"
      local time_val, mem_val = parse_resources_bracket(status_chunk)
      table.insert(cases, {
        type = "case",
        case_id = tonumber(case_id) or 0,
        status = vim.trim(status):upper(),
        extra = "",
        time = time_val or 0,
        memory = mem_val or 0,
        points = 0,
        total = 0,
        _batched = true,
      })
    end
    -- Last batched case (no following "Case #")
    local last_batched_id, last_batched_chunk =
      plain:match("Case%s+#(%d+):%s*(.-)%s*[BR]")
    if last_batched_id and not plain:find("Test case%s+#" .. last_batched_id) then
      local status = last_batched_chunk:match("^(%u+)") or "?"
      local time_val, mem_val = parse_resources_bracket(last_batched_chunk)
      table.insert(cases, {
        type = "case",
        case_id = tonumber(last_batched_id) or 0,
        status = vim.trim(status):upper(),
        extra = "",
        time = time_val or 0,
        memory = mem_val or 0,
        points = 0,
        total = 0,
        _batched = true,
      })
    end
  end

  -- Strategy 3: Last resort — just find "#N: VERDICT" patterns
  if #cases == 0 then
    local plain = normalize_ws(html:gsub("<[^>]+>", " "))
    plain = plain:gsub("%s+", " ")
    for case_id, status_raw in plain:gmatch("#(%d+):%s*(%u+)") do
      table.insert(cases, {
        type = "case",
        case_id = tonumber(case_id) or 0,
        status = vim.trim(status_raw):upper(),
        extra = "",
        time = 0, memory = 0, points = 0, total = 0,
      })
    end
  end

  -- Group batched cases if batch info was detected
  if #batch_positions > 0 and #cases > 0 then
    local batched_cases = {}
    local unbatched_cases = {}
    for _, c in ipairs(cases) do
      if c._batched then
        table.insert(batched_cases, c)
        c._batched = nil  -- clean up internal flag
      else
        table.insert(unbatched_cases, c)
      end
    end

    if #batched_cases > 0 then
      -- Build final list: unbatched cases + batch groups
      cases = {}
      for _, c in ipairs(unbatched_cases) do
        c._html_pos = nil
        table.insert(cases, c)
      end

      -- Create batch group containers
      local batch_case_groups = {}
      for _, bp in ipairs(batch_positions) do
        batch_case_groups[bp.id] = {
          type = "batch",
          batch_id = bp.id,
          points = bp.points,
          total = bp.total,
          cases = {},
        }
      end

      -- Assign each batched case to the batch whose HTML position is
      -- closest before it (the most recent batch header above the case row).
      for _, c in ipairs(batched_cases) do
        local best_batch_id = nil
        local best_pos = -1
        local case_pos = c._html_pos or 0
        c._html_pos = nil  -- clean up internal field
        for _, bp in ipairs(batch_positions) do
          if bp.pos <= case_pos and bp.pos > best_pos then
            best_pos = bp.pos
            best_batch_id = bp.id
          end
        end
        if best_batch_id and batch_case_groups[best_batch_id] then
          table.insert(batch_case_groups[best_batch_id].cases, c)
        end
      end

      -- Add batch groups to cases list
      for _, bp in ipairs(batch_positions) do
        if batch_case_groups[bp.id] and #batch_case_groups[bp.id].cases > 0 then
          table.insert(cases, batch_case_groups[bp.id])
        end
      end
    end
  else
    -- No batches: clean up _html_pos from all cases
    for _, c in ipairs(cases) do
      c._html_pos = nil
    end
  end

  return cases
end

--- Extract resources (time, memory) from tag-stripped, normalized text.
--- Handles "Resources: 0.085s, 1.58 MB", "Resources: ---,1.58 MB" (TLE), etc.
---@param plain string normalized tag-stripped text
---@return number time_val
---@return number mem_kb
local function extract_resources(plain)
  -- Pattern 1: normal — "Resources: 0.085s, 1.58 MB"
  local res_time, res_mem, res_unit =
    plain:match("Resources:%s*(>?[%d%.]+)s[,;]%s*([%d%.]+)%s*(%a+)")
  if res_time then
    return parse_time(res_time), parse_memory_kb(res_mem, res_unit)
  end
  -- Pattern 2: TLE — "Resources: ---, 1.58 MB" or "Resources:---,1.58 MB"
  res_mem, res_unit = plain:match("Resources:%s*%-%-%-,?%s*([%d%.]+)%s*(%a+)")
  if res_mem then
    return 0, parse_memory_kb(res_mem, res_unit)
  end
  return 0, 0
end

--- Extract score from tag-stripped, normalized text.
--- Handles "Final score: 50/100 (50.0/100.0 points)" and variants.
---@param plain string
---@return number points
---@return number total
local function extract_score(plain)
  -- "Final score: 50/100" or "Final pretest score: 50/100"
  local score_got, score_total = plain:match("Final.-score:%s*([%d%.]+)/([%d%.]+)")
  if score_got then
    return tonumber(score_got) or 0, tonumber(score_total) or 0
  end
  -- "(50.0/100.0 points)"
  local pts, tot = plain:match("%(([%d%.]+)/([%d%.]+)%s+points?%)")
  if pts then
    return tonumber(pts) or 0, tonumber(tot) or 0
  end
  return 0, 0
end

--- Scrape additional submission details (resources, score, test cases) from HTML.
---@param submission_id number
---@param data table existing submission data to augment
---@param callback fun(data: table)
local function scrape_submission_details(submission_id, data, callback)
  local headers = auth.auth_headers() or {}
  local url = config.options.base_url .. "/submission/" .. tostring(submission_id)

  http.get(url, { headers = headers, follow_redirects = true, timeout = 30 }, function(resp)
    if resp.status ~= 200 then
      callback(data)
      return
    end

    local body = resp.body

    -- Scrape test cases from raw HTML (scrape_test_cases handles its own tag stripping)
    local cases = scrape_test_cases(body)
    if #cases > 0 then
      data.cases = cases
    end

    -- For resources/score, use tag-stripped normalized text
    local plain = normalize_ws(body:gsub("<[^>]+>", " "))

    -- Extract resources
    local time_val, mem_val = extract_resources(plain)
    if time_val > 0 then data.time = time_val end
    if mem_val > 0 then data.memory = mem_val end

    -- Extract score
    local points, total = extract_score(plain)
    if total > 0 then
      data.case_points = points
      data.case_total = total
    end

    -- Extract problem name
    local problem = plain:match('Submission of%s+(.-)%s+by')
    if problem then
      data.problem = vim.trim(problem)
    end

    -- Derive the correct result from test cases and points
    data.result = derive_result(cases, data.case_points, data.case_total, data.result)

    callback(data)
  end)
end

--- Poll a submission's result until it's done judging.
--- Scrapes the submission page for status, test cases, and resources.
---@param submission_id number
---@param attempt? number
function M.poll_result(submission_id, attempt)
  M.poll_result_scrape(submission_id, attempt or 1)
end

--- Poll submission result by scraping the HTML submission page.
---@param submission_id number
---@param attempt number
function M.poll_result_scrape(submission_id, attempt)
  if attempt > 120 then
    ui.notify("Timed out waiting for submission " .. submission_id, vim.log.levels.WARN)
    return
  end

  local headers = auth.auth_headers() or {}
  local url = config.options.base_url .. "/submission/" .. tostring(submission_id)

  http.get(url, { headers = headers, follow_redirects = true, timeout = 10 }, function(resp)
    if resp.status ~= 200 then
      if attempt < 10 then
        vim.defer_fn(function()
          M.poll_result_scrape(submission_id, attempt + 1)
        end, 1000)
      else
        ui.notify("Failed to fetch submission page: HTTP " .. resp.status, vim.log.levels.ERROR)
      end
      return
    end

    local body = resp.body

    -- Check if still judging: look for spinner icon or specific status messages
    -- from the template. Avoid false positives from page chrome/navigation.
    local is_processing = body:find('fa%-spinner fa%-pulse') ~= nil
    if not is_processing then
      -- Also check for the specific <h4> messages the template emits
      is_processing = body:find("We are waiting for a suitable judge") ~= nil
        or body:find("Your submission is being processed") ~= nil
    end

    -- Extract result from various patterns
    -- First try the explicit submission result classes used by the DMOJ status page header
    local result = nil
    result = body:match('<span[^>]*class="[^"]*sub%-result[^"]*"[^>]*>%s*([^<]+)%s*</span>')
    if not result then
      result = body:match('<span[^>]*class="[^"]*submission%-result[^"]*"[^>]*>%s*([^<]+)%s*</span>')
    end
    -- Fallback: look for the status in the submission info section (avoid matching
    -- individual test case verdict classes like "case-AC" which would give false positives)
    if not result then
      -- Search for ">VERDICT<" but NOT inside case-VERDICT classes
      for _, verdict in ipairs({"IE", "CE", "IR", "RTE", "MLE", "TLE", "OLE", "WA", "AC"}) do
        -- Look for the verdict in a submission status context, not case-level
        local pat = 'status%-tag[^>]*>%s*' .. verdict .. '%s*<'
        if body:find(pat) or body:find('class="[^"]*result%-' .. verdict:lower() .. '[^"]*"') then
          result = verdict
          break
        end
      end
    end

    if result then
      result = vim.trim(result)
    end

    -- Normalize and tag-strip for resources/score extraction
    local plain = normalize_ws(body:gsub("<[^>]+>", " "))

    -- Extract resource info using shared helper
    local time_val, mem_val = extract_resources(plain)

    -- Extract points using shared helper
    local points, total = extract_score(plain)

    local problem = plain:match('Submission of%s+(.-)%s+by') or "?"

    local ce = body:match('Compilation Error.-<pre[^>]*>(.-)</pre>')
    local compile_error = nil
    if ce then
      -- Strip any internal HTML tags (like <span>)
      ce = ce:gsub("<[^>]+>", "")
      compile_error = normalize_ws(ce)
    end

    -- Scrape test cases from raw HTML
    local cases = scrape_test_cases(body)

    -- Derive running score from individual case points when the page-level
    -- "Final score:" line hasn't appeared yet (still judging).
    if points == 0 and total == 0 and cases and #cases > 0 then
      local running_pts = 0
      local running_tot = 0
      for _, c in ipairs(cases) do
        if c.type == "batch" then
          -- batch header has points/total
          running_pts = running_pts + (c.points or 0)
          running_tot = running_tot + (c.total or 0)
        elseif c.type == "case" and not c._batched then
          -- non-batched individual case
          running_pts = running_pts + (c.points or 0)
          running_tot = running_tot + (c.total or 0)
        end
      end
      if running_tot > 0 then
        points = running_pts
        total = running_tot
      end
    end

    -- Derive running resources (max time, sum of max memory) from individual
    -- cases when the page-level "Resources:" line hasn't appeared yet.
    if time_val == 0 and mem_val == 0 and cases and #cases > 0 then
      local max_time = 0
      local max_mem = 0
      for _, c in ipairs(cases) do
        if c.type == "case" then
          if (c.time or 0) > max_time then max_time = c.time end
          if (c.memory or 0) > max_mem then max_mem = c.memory end
        elseif c.type == "batch" and c.cases then
          for _, bc in ipairs(c.cases) do
            if (bc.time or 0) > max_time then max_time = bc.time end
            if (bc.memory or 0) > max_mem then max_mem = bc.memory end
          end
        end
      end
      if max_time > 0 or max_mem > 0 then
        time_val = max_time
        mem_val = max_mem
      end
    end

    -- Build a result data table compatible with show_result
    local data = {
      id = submission_id,
      result = result or "Judging...",
      status = "D",
      case_points = points,
      case_total = total,
      time = time_val,
      memory = mem_val,
      problem = vim.trim(problem),
      language = "?",
      cases = cases,
      compile_error = compile_error,
      _scraped = true,
    }

    if is_processing then
      M.show_result(data, true)
      vim.defer_fn(function()
        M.poll_result_scrape(submission_id, attempt + 1)
      end, 500)
      return
    end

    -- Derive correct result now that we have all the data
    data.result = derive_result(cases, points, total, data.result)

    -- If we still don't have a scraped result from the page, check whether
    -- derive_result was able to determine it from the cases. If so, show
    -- immediately — don't retry and add unnecessary delay.
    if not result or result == "" then
      if data.result ~= "??" then
        -- derive_result gave us a definitive answer from case data; show it.
      elseif attempt < 15 then
        vim.defer_fn(function()
          M.poll_result_scrape(submission_id, attempt + 1)
        end, 1000)
        return
      else
        data.result = "??"
      end
    end

    M.show_result(data)
  end)
end

--- Determine the highlight group for a verdict string.
---@param verdict string
---@return string hl_group
local function verdict_hl(verdict)
  if verdict == "AC" then return "DiagnosticOk"
  elseif verdict == "WA" then return "DiagnosticError"
  end
  return "DiagnosticWarn"
end

--- Map verdict to a full description.
---@param verdict string
---@return string
local function verdict_label(verdict)
  local labels = {
    AC = "Accepted",
    WA = "Wrong Answer",
    TLE = "Time Limit Exceeded",
    MLE = "Memory Limit Exceeded",
    RTE = "Runtime Error",
    CE = "Compile Error",
    IE = "Internal Error",
    OLE = "Output Limit Exceeded",
    IR = "Invalid Return",
  }
  return labels[verdict] or verdict
end

--- Display submission result in a floating window (leetcode.nvim-style).
---@param data table submission detail
---@param is_processing boolean|nil
function M.show_result(data, is_processing)
  local result = data.result or "??"
  local points = data.case_points or 0
  local total = data.case_total or 0

  -- Compile error override
  if data.compile_error and vim.trim(data.compile_error) ~= "" then
    result = "CE"
  else
    -- Derive correct result from points if the scraped result seems wrong
    result = derive_result(data.cases, points, total, result)
  end
  data.result = result

  local is_accepted = (result == "AC")
  -- Flatten cases (expand batch groups) for counting
  local flat_cases = {}
  if data.cases then
    for _, c in ipairs(data.cases) do
      if c.type == "batch" and c.cases then
        for _, bc in ipairs(c.cases) do
          table.insert(flat_cases, bc)
        end
      elseif c.status then
        table.insert(flat_cases, c)
      end
    end
  end
  local num_cases = #flat_cases
  local passed = 0
  for _, c in ipairs(flat_cases) do
    if c.status == "AC" then passed = passed + 1 end
  end

  -- Calculate popup width (like leetcode.nvim: 70-80% of screen)
  local popup_width = math.max(60, math.floor(vim.o.columns * 0.6))
  local inner_width = popup_width - 4  -- account for padding
  local sep = string.rep("─", inner_width)

  local lines = {}
  local hl_lines = {} -- {row, hl_group, col_start, col_end}

  -- Header: verdict title line (like leetcode.nvim)
  table.insert(lines, "")
  local title_line
  if is_accepted then
    title_line = "  " .. verdict_label(result)
  else
    title_line = "  " .. verdict_label(result)
  end
  if num_cases > 0 then
    title_line = title_line .. string.format("  |  %d/%d testcases passed", passed, num_cases)
  end
  local title_row = #lines
  table.insert(lines, title_line)
  table.insert(hl_lines, { title_row, verdict_hl(result), 0, -1 })
  table.insert(lines, "")

  -- Compile Error output
  if result == "CE" and data.compile_error and vim.trim(data.compile_error) ~= "" then
    table.insert(lines, "  Compilation Error")
    table.insert(hl_lines, { #lines - 1, "DiagnosticError", 0, -1 })
    table.insert(lines, "")
    for line in vim.gsplit(vim.trim(data.compile_error), "\n") do
      table.insert(lines, "    " .. line)
    end
  else
    -- Score line
    local score_line = string.format("  Score: %.0f/%.0f", points, total)
    if total > 0 then
      score_line = score_line .. string.format("  (%.0f%%)", (points / total) * 100)
    end
    local score_row = #lines
    table.insert(lines, score_line)
    if points >= total and total > 0 then
      table.insert(hl_lines, { score_row, "DiagnosticOk", 0, -1 })
    elseif points > 0 then
      table.insert(hl_lines, { score_row, "DiagnosticWarn", 0, -1 })
    elseif total > 0 then
      table.insert(hl_lines, { score_row, "DiagnosticError", 0, -1 })
    end

    table.insert(lines, "")

    -- Resources
    local time_display = data.time or 0
    local mem_display = data.memory or 0
    local mem_str
    if mem_display >= 1024 then
      mem_str = string.format("%.2f MB", mem_display / 1024)
    else
      mem_str = string.format("%.0f KB", mem_display)
    end
    table.insert(lines, string.format("  Resources: %.3fs, %s", time_display, mem_str))
    if data.problem and data.problem ~= "?" then
      table.insert(lines, "  Problem:   " .. data.problem)
    end
    if data.language and data.language ~= "?" then
      table.insert(lines, "  Language:  " .. data.language)
    end

    table.insert(lines, "")
    table.insert(lines, "  " .. sep)
    table.insert(lines, "")

    -- Execution Results header
    table.insert(lines, "  Execution Results")
    local exec_row = #lines - 1
    table.insert(hl_lines, { exec_row, "@markup.heading", 0, -1 })
    table.insert(lines, "")

    -- Visual summary bar (like DMOJ's checkmarks/crosses row)
    if num_cases > 0 then
      local icon_parts = {}
      for _, c in ipairs(flat_cases) do
        local icon_char = c.status == "AC" and "✓" or "✗"
        table.insert(icon_parts, icon_char)
      end
      local icon_line = "  " .. table.concat(icon_parts, " ")
      local icon_row = #lines
      table.insert(lines, icon_line)
      -- Highlight each icon individually
      local col = 2
      for _, c in ipairs(flat_cases) do
        local hl = verdict_hl(c.status)
        local icon_char = c.status == "AC" and "✓" or "✗"
        local byte_len = #icon_char
        table.insert(hl_lines, { icon_row, hl, col, col + byte_len })
        col = col + byte_len + 1 -- +1 for the space separator
      end
      table.insert(lines, "")
    end

    -- Per-case results
    if num_cases > 0 then
      for _, c in ipairs(data.cases) do
        if c.type == "case" then
          local status_str = c.status or "?"
          if c.extra and c.extra ~= "" then
            status_str = status_str .. " " .. c.extra
          end
          local detail_parts = {}
          if c.time and c.time > 0 then
            table.insert(detail_parts, string.format("%.3fs", c.time))
          end
          if c.memory and c.memory > 0 then
            if c.memory >= 1024 then
              table.insert(detail_parts, string.format("%.2f MB", c.memory / 1024))
            else
              table.insert(detail_parts, string.format("%.0f KB", c.memory))
            end
          end
          local detail_str = ""
          if #detail_parts > 0 then
            detail_str = " [" .. table.concat(detail_parts, ",") .. "]"
          end
          local pts_str = ""
          if c.total and c.total > 0 then
            pts_str = string.format(" (%.0f/%.0f)", c.points or 0, c.total)
          end

          local case_label = string.format("  Test case #%-3d", c.case_id or 0)
          local case_line = case_label .. "  " .. status_str .. detail_str .. pts_str
          local case_row = #lines
          table.insert(lines, case_line)
          -- Highlight the status portion
          local status_start = #case_label + 2
          local status_end = status_start + #(c.status or "?")
          table.insert(hl_lines, { case_row, verdict_hl(c.status), status_start, status_end })
        elseif c.type == "batch" then
          local batch_row = #lines
          table.insert(lines, string.format(
            "  Batch %-3s  [%.1f/%.1f]",
            tostring(c.batch_id or "?"),
            c.points or 0,
            c.total or 0
          ))
          table.insert(hl_lines, { batch_row, "@markup.heading", 0, -1 })
          if c.cases then
            for _, bc in ipairs(c.cases) do
              local bc_status = bc.status or "?"
              local bc_detail_parts = {}
              if bc.time and bc.time > 0 then
                table.insert(bc_detail_parts, string.format("%.3fs", bc.time))
              end
              if bc.memory and bc.memory > 0 then
                if bc.memory >= 1024 then
                  table.insert(bc_detail_parts, string.format("%.2f MB", bc.memory / 1024))
                else
                  table.insert(bc_detail_parts, string.format("%.0f KB", bc.memory))
                end
              end
              local bc_detail = ""
              if #bc_detail_parts > 0 then
                bc_detail = " [" .. table.concat(bc_detail_parts, ",") .. "]"
              end
              local bc_label = string.format("    Case %-4s", tostring(bc.case_id or "?"))
              local bc_line = bc_label .. "  " .. bc_status .. bc_detail
              local bc_row = #lines
              table.insert(lines, bc_line)
              local bc_s = #bc_label + 2
              table.insert(hl_lines, { bc_row, verdict_hl(bc_status), bc_s, bc_s + #bc_status })
            end
          end
        end
      end
    else
      table.insert(lines, "  (No case details available)")
      if data._scraped then
        table.insert(lines, "  Open in browser for full details.")
      end
    end
  end

  table.insert(lines, "")
  table.insert(lines, "  " .. sep)
  table.insert(lines, "  [q] Close  [o] Open in browser")
  table.insert(lines, "")

  local bufnr = ui.create_buf("dmoj://submission/" .. tostring(data.id), lines, { filetype = "dmoj" })

  -- Apply highlights
  local ns = vim.api.nvim_create_namespace("dmoj_submission")
  for _, hl in ipairs(hl_lines) do
    pcall(vim.api.nvim_buf_add_highlight, bufnr, ns, hl[2], hl[1], hl[3], hl[4])
  end
  -- Highlight separators
  local buf_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  for i, line in ipairs(buf_lines) do
    if line:match("^%s*[═]+%s*$") or line:match("^%s*[─]+%s*$") then
      vim.api.nvim_buf_add_highlight(bufnr, ns, "FloatBorder", i - 1, 0, -1)
    end
  end

  -- Popup size: larger like leetcode.nvim (60% width, up to 75% height)
  local popup_height = math.min(#lines + 2, math.floor(vim.o.lines * 0.75))

  -- Color the border based on result (like leetcode.nvim)
  local border_hl = "DiagnosticError"
  if is_accepted then border_hl = "DiagnosticOk" end
  if result == "CE" then border_hl = "DiagnosticError" end
  local title_str = is_accepted
    and (" ✓ " .. verdict_label(result) .. " ")
    or (" ✗ " .. verdict_label(result) .. " ")
  if is_processing then
    title_str = " ⏳ Judging... " .. result .. " "
  end

  local win = ui.open_float(bufnr, {
    title = title_str,
    width = popup_width,
    height = popup_height,
  })

  -- Set border highlight to match result
  if vim.api.nvim_win_is_valid(win) then
    vim.wo[win].winhighlight = "Normal:NormalFloat,FloatBorder:" .. border_hl .. ",FloatTitle:" .. border_hl
  end

  -- Open in browser
  vim.keymap.set("n", "o", function()
    local sub_url = config.options.base_url .. "/submission/" .. tostring(data.id)
    vim.fn.jobstart({ config.options.open_cmd, sub_url }, { detach = true })
  end, { buffer = bufnr, nowait = true, silent = true })
end

return M
