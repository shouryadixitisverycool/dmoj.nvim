local M = {}

local config = require("dmoj.config")
local http = require("dmoj.http")
local auth = require("dmoj.auth")
local api = require("dmoj.api")
local ui = require("dmoj.ui")

--- Derive the correct verdict from test cases and points.
--- Centralizes logic that was previously duplicated across scrape/poll/show.
---@param cases table[] list of test case objects with .status field
---@param case_points number points earned
---@param case_total number total possible points
---@param current_result string current result string (e.g. from API)
---@return string result the derived verdict
local function derive_result(cases, case_points, case_total, current_result)
  local result = current_result or "??"
  if cases and #cases > 0 then
    local all_ac = true
    local has_tle, has_mle, has_rte, has_wa = false, false, false, false
    for _, c in ipairs(cases) do
      if c.status ~= "AC" then
        all_ac = false
        if c.status == "TLE" then has_tle = true
        elseif c.status == "MLE" then has_mle = true
        elseif c.status == "RTE" then has_rte = true
        elseif c.status == "WA" then has_wa = true
        end
      end
    end
    if all_ac then result = "AC"
    elseif has_tle then result = "TLE"
    elseif has_mle then result = "MLE"
    elseif has_rte then result = "RTE"
    elseif has_wa then result = "WA"
    end
  end
  -- Override from points when result contradicts score
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
          ui.notify("Submitted! Polling for results...", vim.log.levels.INFO)
          M.poll_result(tonumber(submission_id))
        else
          -- Also check the response body (some servers include it in 302 body)
          submission_id = extract_submission_id(resp.body)
          if submission_id then
            ui.notify("Submitted! Polling for results...", vim.log.levels.INFO)
            M.poll_result(tonumber(submission_id))
          elseif location ~= "" then
            -- Follow the redirect to find the submission ID
            ui.notify("Submitted! Looking up submission...", vim.log.levels.INFO)
            M._follow_redirect_for_id(location, problem_code, headers)
          else
            -- Last resort: scrape recent submissions for this problem
            ui.notify("Submitted! Looking up submission...", vim.log.levels.INFO)
            M._find_latest_submission(problem_code, headers)
          end
        end
      elseif resp.status == 200 then
        -- Check if 200 is actually a redirect page (some setups return 200 with redirect)
        local meta_redirect = resp.body:match('url=/submission/(%d+)')
        if meta_redirect then
          ui.notify("Submitted! Polling for results...", vim.log.levels.INFO)
          M.poll_result(tonumber(meta_redirect))
          return
        end

        -- Check if the body contains a submission ID link
        local body_sub_id = extract_submission_id(resp.body)
        if body_sub_id then
          ui.notify("Submitted! Polling for results...", vim.log.levels.INFO)
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
      ui.notify("Polling for results...", vim.log.levels.INFO)
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
      ui.notify("Found submission #" .. max_id .. ". Polling for results...", vim.log.levels.INFO)
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
            ui.notify("Found submission #" .. gen_max_id .. ". Polling for results...", vim.log.levels.INFO)
            M.poll_result(gen_max_id)
            return
          end
        end
        ui.notify("Submitted, but could not find submission ID. Check your submissions page.", vim.log.levels.WARN)
      end)
    end
  end)
end

--- Scrape test case details from the submission page HTML.
--- Returns a list of case tables, or empty table if none found.
---@param body string HTML body
---@return table[] cases
local function scrape_test_cases(plain)
  -- Convert HTML entities just in case (e.g., &nbsp;)
  plain = plain:gsub("&nbsp;", " "):gsub("p", " ")

  local cases = {}

  for case_id, status_raw, time_s, mem, unit, pts, total in
    plain:gmatch('#(%d+):%s*(.-)%s*%[%s*([%d%.]+)%s*s,%s*([%d%.]+)%s*(%wB)%s*%]%s*%(([%d%.]+)/([%d%.]+)%)')
  do
    local status = status_raw:match("^%s*(%S+)") or status_raw
    local extra = status_raw:match("^%s*%S+%s+(.*)$") or ""
    table.insert(cases, {
      type = "case",
      case_id = tonumber(case_id) or 0,
      status = vim.trim(status):upper(),
      extra = vim.trim(extra),
      time = tonumber(time_s) or 0,
      memory = unit:upper() == "MB" and ((tonumber(mem) or 0) * 1024) or (tonumber(mem) or 0),
      points = tonumber(pts) or 0,
      total = tonumber(total) or 0,
    })
  end

  if #cases == 0 then
    -- fallback for cases with no resources (like CE, IR)
    for case_id, status_raw in plain:gmatch('#(%d+):%s*([A-Za-z]+)') do
      table.insert(cases, {
        type = "case",
        case_id = tonumber(case_id) or 0,
        status = vim.trim(status_raw):upper(),
        extra = "",
        time = 0, memory = 0, points = 0, total = 0
      })
    end
  end

  return cases
end

--- Scrape additional submission details (resources, score, test cases) from HTML.
--- Used to supplement API data which may lack test case details.
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

    local plain = body:gsub("<[^>]+>", "")

    -- Scrape test cases
    local cases = scrape_test_cases(plain)
    if #cases > 0 then
      data.cases = cases
    end

    -- Try to get better resource info from the page
    -- "Resources: 0.234s, 2.03 MB"
    local res_time, res_mem, res_unit = plain:match("Resources:%s*([%d%.]+)s,%s*([%d%.]+)%s*(%wB)")
    if res_time then
      data.time = tonumber(res_time) or data.time
      local m = tonumber(res_mem) or 0
      if res_unit and res_unit:upper() == "MB" then m = m * 1024 end
      data.memory = m > 0 and m or data.memory
    end

    -- "Final score: 100/100 (100.0/100 points)"
    local score_got, score_total = plain:match("Final score:%s*([%d%.]+)/([%d%.]+)")
    if score_got and score_total then
      data.case_points = tonumber(score_got) or data.case_points
      data.case_total = tonumber(score_total) or data.case_total
    end
    -- Also try the "(X.X/Y points)" format
    if not score_got then
      local pts, tot = plain:match("%(([%d%.]+)/([%d%.]+) points?%)")
      if pts then
        data.case_points = tonumber(pts) or data.case_points
        data.case_total = tonumber(tot) or data.case_total
      end
    end

    -- Extract problem name
    local problem = plain:match('Submission of%s*(.-)%s*by')
    if problem then
      data.problem = vim.trim(problem)
    end

    -- Derive the correct result from test cases and points
    data.result = derive_result(cases, data.case_points, data.case_total, data.result)

    callback(data)
  end)
end

--- Poll a submission's result until it's done judging.
--- Tries API v2 first, falls back to scraping the submission page.
---@param submission_id number
---@param attempt? number
function M.poll_result(submission_id, attempt)
  attempt = attempt or 1
  if attempt > 60 then
    ui.notify("Timed out waiting for submission " .. submission_id, vim.log.levels.WARN)
    return
  end

  -- Try API first, then fall back to scraping
  api.submission(submission_id, function(data, err)
    if err then
      -- On first few attempts, the submission might not be registered yet
      if attempt < 3 then
        vim.defer_fn(function()
          M.poll_result(submission_id, attempt + 1)
        end, 2000)
        return
      end

      -- API failed after retries, try scraping the submission page
      M.poll_result_scrape(submission_id, attempt)
      return
    end

    local status = data.status or ""

    -- status "D" means done, "P" means processing, "G" means grading
    if status == "D" then
      -- Always scrape the submission page for test case details,
      -- since the API often doesn't include per-case breakdown
      scrape_submission_details(submission_id, data, function(augmented)
        M.show_result(augmented)
      end)
    else
      vim.defer_fn(function()
        M.poll_result(submission_id, attempt + 1)
      end, 1500)
    end
  end)
end

--- Poll submission result by scraping the HTML submission page.
---@param submission_id number
---@param attempt number
function M.poll_result_scrape(submission_id, attempt)
  if attempt > 60 then
    ui.notify("Timed out waiting for submission " .. submission_id, vim.log.levels.WARN)
    return
  end

  local headers = auth.auth_headers() or {}
  local url = config.options.base_url .. "/submission/" .. tostring(submission_id)

  http.get(url, { headers = headers, follow_redirects = true, timeout = 30 }, function(resp)
    if resp.status ~= 200 then
      if attempt < 10 then
        vim.defer_fn(function()
          M.poll_result_scrape(submission_id, attempt + 1)
        end, 2000)
      else
        ui.notify("Failed to fetch submission page: HTTP " .. resp.status, vim.log.levels.ERROR)
      end
      return
    end

    local body = resp.body

    -- Check if still judging
    local is_processing = body:find("Grading") or body:find("Processing") or body:find("Queued")

    -- Extract result from various patterns
    local result = nil
    result = body:match('<span[^>]*class="[^"]*sub%-result[^"]*"[^>]*>%s*([^<]+)%s*</span>')
    if not result then
      result = body:match('<span[^>]*class="[^"]*submission%-result[^"]*"[^>]*>%s*([^<]+)%s*</span>')
    end
    if not result then
      for _, verdict in ipairs({"AC", "WA", "TLE", "MLE", "RTE", "CE", "IR", "OLE", "IE"}) do
        if body:find('class="[^"]*' .. verdict:lower() .. '[^"]*"') or
           body:find(">" .. verdict .. "<") then
          result = verdict
          break
        end
      end
    end

    if result then
      result = vim.trim(result)
    end

    -- If no result yet and appears to be processing, retry
    if (not result or result == "") and is_processing then
      vim.defer_fn(function()
        M.poll_result_scrape(submission_id, attempt + 1)
      end, 2000)
      return
    end

    -- If we still don't have a result after many attempts, show what we have
    if not result or result == "" then
      if attempt < 15 then
        vim.defer_fn(function()
          M.poll_result_scrape(submission_id, attempt + 1)
        end, 2000)
        return
      end
      result = "??"
    end

    local plain = body:gsub("<[^>]+>", "")

    -- Extract resource info
    local time_val = 0
    local mem_val = 0
    local res_time, res_mem, res_unit = plain:match("Resources:%s*([%d%.]+)s,%s*([%d%.]+)%s*(%wB)")
    if res_time then
      time_val = tonumber(res_time) or 0
      local m = tonumber(res_mem) or 0
      if res_unit and res_unit:upper() == "MB" then m = m * 1024 end
      mem_val = m
    else
      time_val = tonumber(plain:match("([%d%.]+)%s*s")) or 0
      mem_val = tonumber(plain:match("([%d%.]+)%s*KB")) or 0
    end

    -- Extract points
    local points = 0
    local total = 0
    local score_got, score_total = plain:match("Final score:%s*([%d%.]+)/([%d%.]+)")
    if score_got then
      points = tonumber(score_got) or 0
      total = tonumber(score_total) or 0
    else
      local pts, tot = plain:match("%(([%d%.]+)/([%d%.]+) points?%)")
      if pts then
        points = tonumber(pts) or 0
        total = tonumber(tot) or 0
      else
        points = tonumber(plain:match("([%d%.]+)%s*/[%d%.]+%s*points?")) or 0
        total = tonumber(plain:match("[%d%.]+%s*/(%s*[%d%.]+)%s*points?")) or 0
      end
    end

    local problem = plain:match('Submission of%s*(.-)%s*by') or "?"

    -- Scrape test cases
    local cases = scrape_test_cases(plain)

    -- Build a result data table compatible with show_result
    local data = {
      id = submission_id,
      result = result,
      status = "D",
      case_points = points,
      case_total = total,
      time = time_val,
      memory = mem_val,
      problem = vim.trim(problem),
      language = "?",
      cases = cases,
      _scraped = true,
    }

    -- Derive correct result from test cases and points
    data.result = derive_result(cases, points, total, data.result)

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
function M.show_result(data)
  local result = data.result or "??"
  local points = data.case_points or 0
  local total = data.case_total or 0

  -- Derive correct result from points if the API result seems wrong
  result = derive_result(data.cases, points, total, result)
  data.result = result

  local is_accepted = (result == "AC")
  local num_cases = data.cases and #data.cases or 0
  local passed = 0
  if num_cases > 0 then
    for _, c in ipairs(data.cases) do
      if c.status == "AC" then passed = passed + 1 end
    end
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
    local icons = "  "
    for _, c in ipairs(data.cases) do
      if c.status == "AC" then
        icons = icons .. "✓ "
      else
        icons = icons .. "✗ "
      end
    end
    local icon_row = #lines
    table.insert(lines, icons)
    -- Highlight each icon individually
    local col = 2
    for _, c in ipairs(data.cases) do
      local hl = verdict_hl(c.status)
      -- Each icon is a multi-byte char + space (icon is typically 3 bytes in UTF-8)
      local icon_char = c.status == "AC" and "✓" or "✗"
      local byte_len = #icon_char
      table.insert(hl_lines, { icon_row, hl, col, col + byte_len })
      col = col + byte_len + 1 -- +1 for the space
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
            local bc_label = string.format("    Case %-4s", tostring(bc.case_id or "?"))
            local bc_line = bc_label .. "  " .. bc_status
            if bc.time and bc.time > 0 then
              bc_line = bc_line .. string.format("  %.3fs", bc.time)
            end
            if bc.total and bc.total > 0 then
              bc_line = bc_line .. string.format("  (%.0f/%.0f)", bc.points or 0, bc.total)
            end
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

  table.insert(lines, "")
  table.insert(lines, "  " .. sep)
  table.insert(lines, "  [q] Close  [o] Open in browser")
  table.insert(lines, "")

  -- Notify with result summary
  local msg = string.format(
    "Submission #%d: %s  [%.0f/%.0f pts]",
    data.id or 0, result, points, total
  )
  if num_cases > 0 then
    msg = msg .. string.format("  %d/%d passed", passed, num_cases)
  end
  local level = vim.log.levels.INFO
  if is_accepted then level = vim.log.levels.INFO
  else level = vim.log.levels.WARN
  end
  ui.notify(msg, level)

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
  local border_hl = is_accepted and "DiagnosticOk" or "DiagnosticError"
  local title_str = is_accepted
    and (" ✓ " .. verdict_label(result) .. " ")
    or (" ✗ " .. verdict_label(result) .. " ")

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
