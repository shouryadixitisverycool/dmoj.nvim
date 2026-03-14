local M = {}

local config = require("dmoj.config")
local http = require("dmoj.http")
local auth = require("dmoj.auth")
local ui = require("dmoj.ui")

--- Language key -> compile/run command templates.
--- `compile` is nil for interpreted languages.
--- `{src}` = source file path, `{bin}` = output binary path, `{input}` = input file path
---@type table<string, { compile?: string[], run: string[] }>
local lang_commands = {
  C      = { compile = { "gcc", "-o", "{bin}", "{src}", "-lm" },            run = { "{bin}" } },
  CPP03  = { compile = { "g++", "-std=c++03", "-o", "{bin}", "{src}" },     run = { "{bin}" } },
  CPP11  = { compile = { "g++", "-std=c++11", "-o", "{bin}", "{src}" },     run = { "{bin}" } },
  CPP14  = { compile = { "g++", "-std=c++14", "-o", "{bin}", "{src}" },     run = { "{bin}" } },
  CPP17  = { compile = { "g++", "-std=c++17", "-o", "{bin}", "{src}" },     run = { "{bin}" } },
  CPP20  = { compile = { "g++", "-std=c++20", "-o", "{bin}", "{src}" },     run = { "{bin}" } },
  CPP23  = { compile = { "g++", "-std=c++23", "-o", "{bin}", "{src}" },     run = { "{bin}" } },
  PY2    = { run = { "python2", "{src}" } },
  PY3    = { run = { "python3", "{src}" } },
  PYPY   = { run = { "pypy", "{src}" } },
  PYPY3  = { run = { "pypy3", "{src}" } },
  JAVA   = { compile = { "javac", "{src}" },                                run = { "java", "-cp", "{dir}", "{class}" } },
  JAVA8  = { compile = { "javac", "{src}" },                                run = { "java", "-cp", "{dir}", "{class}" } },
  JAVA11 = { compile = { "javac", "{src}" },                                run = { "java", "-cp", "{dir}", "{class}" } },
  JAVA17 = { compile = { "javac", "{src}" },                                run = { "java", "-cp", "{dir}", "{class}" } },
  JAVA21 = { compile = { "javac", "{src}" },                                run = { "java", "-cp", "{dir}", "{class}" } },
  RUST   = { compile = { "rustc", "-o", "{bin}", "{src}" },                 run = { "{bin}" } },
  GO     = { run = { "go", "run", "{src}" } },
  RUBY   = { run = { "ruby", "{src}" } },
  LUA    = { run = { "lua", "{src}" } },
  PERL   = { run = { "perl", "{src}" } },
  PHP    = { run = { "php", "{src}" } },
  KOTLIN = { compile = { "kotlinc", "{src}", "-include-runtime", "-d", "{jar}" }, run = { "java", "-jar", "{jar}" } },
  SWIFT  = { compile = { "swiftc", "-o", "{bin}", "{src}" },                run = { "{bin}" } },
  HASK   = { compile = { "ghc", "-o", "{bin}", "{src}" },                   run = { "{bin}" } },
  MONO   = { compile = { "mcs", "-out:{bin}.exe", "{src}" },                run = { "mono", "{bin}.exe" } },
  DART   = { run = { "dart", "run", "{src}" } },
  SCALA  = { compile = { "scalac", "{src}" },                               run = { "scala", "-cp", "{dir}", "{class}" } },
}

--- Resolve the correct compile/run commands for a language key.
---@param lang_key string
---@return table|nil commands { compile?: string[], run: string[] }
local function resolve_commands(lang_key)
  local key = lang_key:upper()
  -- Warn if python2 is used on macOS 12.3+ where it was removed
  if key == "PY2" and vim.fn.has("mac") == 1 then
    vim.notify(
      "[dmoj] Warning: python2 was removed in macOS 12.3 (Monterey). " ..
      "The local runner may fail. Consider using PY3 instead.",
      vim.log.levels.WARN
    )
  end
  if lang_commands[key] then
    return lang_commands[key]
  end
  -- Try prefix match (longest first)
  local prefixes = {}
  for prefix, _ in pairs(lang_commands) do
    table.insert(prefixes, prefix)
  end
  table.sort(prefixes, function(a, b) return #a > #b end)
  for _, prefix in ipairs(prefixes) do
    if key:sub(1, #prefix) == prefix then
      return lang_commands[prefix]
    end
  end
  return nil
end

--- Substitute template variables in a command list.
---@param cmd string[] template command
---@param vars table<string, string> variable substitutions
---@return string[] resolved command
local function subst_cmd(cmd, vars)
  local out = {}
  for _, arg in ipairs(cmd) do
    local s = arg
    for k, v in pairs(vars) do
      s = s:gsub("{" .. k .. "}", v)
    end
    table.insert(out, s)
  end
  return out
end

--- Decode common HTML entities in sample content.
---@param s string
---@return string
local function decode_sample(s)
  s = s:gsub("<[^>]+>", "")
  s = s:gsub("&lt;", "<")
  s = s:gsub("&gt;", ">")
  s = s:gsub("&amp;", "&")
  s = s:gsub("&quot;", '"')
  s = s:gsub("&#39;", "'")
  s = s:gsub("&nbsp;", " ")
  s = s:gsub("&#(%d+);", function(n)
    local num = tonumber(n)
    if num and num < 128 then return string.char(num) end
    return ""
  end)
  return vim.trim(s)
end

--- Extract sample test cases from problem description HTML.
--- Returns a list of { input: string, output: string } tables.
---@param html string raw HTML of the problem description
---@return table[] test_cases
function M.extract_samples(html)
  local cases = {}
  local inputs = {}
  local outputs = {}

  -- Strategy 1: Match <hN>heading</hN> immediately followed by <pre> block.
  -- Use [^<]* instead of .- for heading content to prevent Lua's non-greedy
  -- pattern from expanding across multiple heading tags when an earlier heading
  -- (e.g. <h4>Input</h4>) is not directly followed by <pre>.
  for _, heading, pre_content in html:gmatch("<h(%d)[^>]*>([^<]*)</h%1>%s*<pre[^>]*>(.-)</pre>") do
    local clean_heading = heading:lower()
    local content = decode_sample(pre_content)

    if clean_heading:match("input") and not clean_heading:match("output") then
      table.insert(inputs, content)
    elseif clean_heading:match("output") then
      table.insert(outputs, content)
    end
  end

  -- Strategy 1b: headings that contain inline tags (e.g. <h4><strong>Sample Input</strong></h4>)
  -- Use .- but constrain it to NOT span across heading boundaries by checking
  -- that the captured content does not contain another <hN opening tag.
  if #inputs == 0 and #outputs == 0 then
    for _, heading, pre_content in html:gmatch("<h(%d)[^>]*>(.-)</h%1>%s*<pre[^>]*>(.-)</pre>") do
      -- Skip if heading content spans across multiple headings
      if not heading:match("<h%d") then
        local clean_heading = heading:gsub("<[^>]+>", ""):lower()
        local content = decode_sample(pre_content)

        if clean_heading:match("input") and not clean_heading:match("output") then
          table.insert(inputs, content)
        elseif clean_heading:match("output") then
          table.insert(outputs, content)
        end
      end
    end
  end

  -- Strategy 2: heading then intermediate content (no other heading) then <pre>
  if #inputs == 0 then
    for _, heading, between, pre_content in html:gmatch("<h(%d)[^>]*>([^<]*)</h%1>(.-)(<pre[^>]*>.-</pre>)") do
      if not between:match("<h%d") then
        local clean_heading = heading:lower()
        local content = decode_sample(pre_content:match("<pre[^>]*>(.-)</pre>") or "")

        if clean_heading:match("input") and not clean_heading:match("output") then
          if not vim.tbl_contains(inputs, content) then
            table.insert(inputs, content)
          end
        elseif clean_heading:match("output") then
          if not vim.tbl_contains(outputs, content) then
            table.insert(outputs, content)
          end
        end
      end
    end
  end

  -- Strategy 3: Look for <div class="sample-..."> containers
  if #inputs == 0 and #outputs == 0 then
    for sample_block in html:gmatch('<div[^>]*class="[^"]*sample[^"]*"[^>]*>(.-)</div>') do
      local inp = sample_block:match("<pre[^>]*>(.-)</pre>")
      if inp then
        table.insert(inputs, decode_sample(inp))
      end
    end
  end

  -- Strategy 4: Last resort — collect all <pre> blocks, pair odd=input even=output
  if #inputs == 0 and #outputs == 0 then
    local all_pres = {}
    for pre_content in html:gmatch("<pre[^>]*>(.-)</pre>") do
      local content = decode_sample(pre_content)
      if content ~= "" then
        table.insert(all_pres, content)
      end
    end
    for i = 1, #all_pres - 1, 2 do
      table.insert(inputs, all_pres[i])
      table.insert(outputs, all_pres[i + 1])
    end
  end

  -- Pair inputs with outputs
  local n = math.max(#inputs, #outputs)
  for i = 1, n do
    table.insert(cases, {
      input = inputs[i] or "",
      output = outputs[i] or "",
    })
  end

  return cases
end

--- Compile source code (if needed for the language).
--- Calls callback(true, nil) on success, callback(false, error_output) on failure.
---@param src_path string path to source file
---@param lang_key string language key
---@param callback fun(ok: boolean, err: string|nil)
function M.compile(src_path, lang_key, callback)
  local cmds = resolve_commands(lang_key)
  if not cmds then
    callback(false, "Unsupported language: " .. lang_key)
    return
  end

  if not cmds.compile then
    -- Interpreted language, no compilation needed
    callback(true, nil)
    return
  end

  local dir = vim.fn.fnamemodify(src_path, ":h")
  local basename = vim.fn.fnamemodify(src_path, ":t:r")
  local bin_path = dir .. "/" .. basename
  local jar_path = dir .. "/" .. basename .. ".jar"
  local class_name = basename:gsub("^%l", string.upper) -- crude class name guess

  local vars = {
    src = src_path,
    bin = bin_path,
    dir = dir,
    jar = jar_path,
    class = class_name,
  }

  local cmd = subst_cmd(cmds.compile, vars)

  local stderr_chunks = {}
  vim.fn.jobstart(cmd, {
    on_stderr = function(_, data)
      if data then
        for _, line in ipairs(data) do
          if line ~= "" then
            table.insert(stderr_chunks, line)
          end
        end
      end
    end,
    on_exit = function(_, code)
      vim.schedule(function()
        if code == 0 then
          callback(true, nil)
        else
          callback(false, table.concat(stderr_chunks, "\n"))
        end
      end)
    end,
  })
end

--- Run compiled/interpreted code with the given input.
--- Calls callback(exit_code, stdout, stderr, timed_out).
---@param src_path string path to source file
---@param lang_key string language key
---@param input string stdin input
---@param timeout_ms number timeout in milliseconds
---@param callback fun(exit_code: number, stdout: string, stderr: string, timed_out: boolean)
function M.run_with_input(src_path, lang_key, input, timeout_ms, callback)
  local cmds = resolve_commands(lang_key)
  if not cmds then
    callback(-1, "", "Unsupported language: " .. lang_key, false)
    return
  end

  local dir = vim.fn.fnamemodify(src_path, ":h")
  local basename = vim.fn.fnamemodify(src_path, ":t:r")
  local bin_path = dir .. "/" .. basename
  local jar_path = dir .. "/" .. basename .. ".jar"
  local class_name = basename:gsub("^%l", string.upper)

  local vars = {
    src = src_path,
    bin = bin_path,
    dir = dir,
    jar = jar_path,
    class = class_name,
  }

  local cmd = subst_cmd(cmds.run, vars)

  -- Write input to a temp file
  local input_file = vim.fn.tempname()
  local f = io.open(input_file, "w")
  if f then
    f:write(input .. "\n")
    f:close()
  end

  local stdout_chunks = {}
  local stderr_chunks = {}
  local timed_out = false
  local timer = vim.uv.new_timer()
  local job_id

  job_id = vim.fn.jobstart(cmd, {
    stdin = "pipe",
    on_stdout = function(_, data)
      if data then
        for _, line in ipairs(data) do
          table.insert(stdout_chunks, line)
        end
      end
    end,
    on_stderr = function(_, data)
      if data then
        for _, line in ipairs(data) do
          if line ~= "" then
            table.insert(stderr_chunks, line)
          end
        end
      end
    end,
    on_exit = function(_, code)
      if timer and not timer:is_closing() then
        timer:stop()
        timer:close()
      end
      vim.schedule(function()
        -- Clean up temp file
        os.remove(input_file)
        -- Join stdout, removing trailing empty string from jobstart
        local stdout = table.concat(stdout_chunks, "\n")
        -- Remove trailing newline added by jobstart
        stdout = stdout:gsub("\n$", "")
        local stderr = table.concat(stderr_chunks, "\n")
        callback(timed_out and -1 or code, stdout, stderr, timed_out)
      end)
    end,
  })

  if job_id <= 0 then
    if timer and not timer:is_closing() then
      timer:stop()
      timer:close()
    end
    os.remove(input_file)
    callback(-1, "", "Failed to start process", false)
    return
  end

  -- Send input via stdin
  vim.fn.chansend(job_id, input .. "\n")
  vim.fn.chanclose(job_id, "stdin")

  -- Set timeout
  timer:start(timeout_ms, 0, function()
    timed_out = true
    pcall(vim.fn.jobstop, job_id)
  end)
end

--- Compare actual output with expected output.
--- Returns true if they match (ignoring trailing whitespace per line).
---@param actual string
---@param expected string
---@return boolean
function M.compare_output(actual, expected)
  local function normalize(s)
    local lines = {}
    for line in (s .. "\n"):gmatch("([^\n]*)\n") do
      table.insert(lines, vim.trim(line))
    end
    -- Remove trailing empty lines
    while #lines > 0 and lines[#lines] == "" do
      table.remove(lines)
    end
    return lines
  end

  local a = normalize(actual)
  local e = normalize(expected)

  if #a ~= #e then return false end
  for i = 1, #a do
    if a[i] ~= e[i] then return false end
  end
  return true
end

--- Full label for local run verdict.
---@param verdict string
---@return string
local function verdict_label(verdict)
  local labels = {
    AC = "Accepted",
    WA = "Wrong Answer",
    RE = "Runtime Error",
    TLE = "Time Limit Exceeded",
    CE = "Compile Error",
  }
  return labels[verdict] or verdict
end

-- ──────────────────────────────────────────────────────────────
-- Per-case tabbed result UI (modelled on leetcode.nvim)
-- ──────────────────────────────────────────────────────────────

--- Namespace for all runner highlights.
local ns_runner = vim.api.nvim_create_namespace("dmoj_runner")

--- Define custom highlight groups (idempotent).
local function setup_highlights()
  local function hl_fg(name)
    local h = vim.api.nvim_get_hl(0, { name = name, link = false })
    return h.fg
  end
  local function hl_bg(name)
    local h = vim.api.nvim_get_hl(0, { name = name, link = false })
    return h.bg
  end

  local ok_fg = hl_fg("DiagnosticOk")
  local err_fg = hl_fg("DiagnosticError")
  local warn_fg = hl_fg("DiagnosticWarn")
  local normal_bg = hl_bg("Normal") or 0
  local dark_bg = hl_bg("NormalFloat") or normal_bg
  local comment_fg = hl_fg("Comment")
  local conceal_fg = hl_fg("Conceal") or comment_fg

  -- Tab highlights (unfocused = colored text, focused = inverted pill)
  vim.api.nvim_set_hl(0, "DmojCaseOk",       { fg = ok_fg,  bg = dark_bg, bold = true })
  vim.api.nvim_set_hl(0, "DmojCaseErr",      { fg = err_fg, bg = dark_bg, bold = true })
  vim.api.nvim_set_hl(0, "DmojCaseWarn",     { fg = warn_fg, bg = dark_bg, bold = true })
  vim.api.nvim_set_hl(0, "DmojCaseFocusOk",  { bg = ok_fg,  fg = dark_bg, bold = true })
  vim.api.nvim_set_hl(0, "DmojCaseFocusErr", { bg = err_fg, fg = dark_bg, bold = true })
  vim.api.nvim_set_hl(0, "DmojCaseFocusWarn",{ bg = warn_fg, fg = dark_bg, bold = true })

  -- Section labels, indent bar, alt text
  vim.api.nvim_set_hl(0, "DmojResultNormal", { fg = conceal_fg })
  vim.api.nvim_set_hl(0, "DmojResultIndent", { fg = comment_fg })
end

--- Return the tab highlight group for a case.
---@param verdict string "AC", "WA", "RE", "TLE"
---@param focused boolean whether this tab is currently selected
---@return string hl_group
local function case_tab_hl(verdict, focused)
  local kind
  if verdict == "AC" then
    kind = "Ok"
  elseif verdict == "WA" then
    kind = "Err"
  else
    kind = "Warn"
  end
  if focused then
    return "DmojCaseFocus" .. kind
  end
  return "DmojCase" .. kind
end

--- Module-level state for the active result window.
---@class DmojRunnerState
---@field results table[]
---@field focused_idx number
---@field bufnr number
---@field win number
---@field compile_error? string
M._state = nil

--- Render the result buffer contents for the current state.
--- Clears the buffer and redraws header, tab bar, and focused case.
local function render_results()
  local st = M._state
  if not st then return end
  if not vim.api.nvim_buf_is_valid(st.bufnr) then return end

  -- Make buffer modifiable for writing
  vim.bo[st.bufnr].modifiable = true

  local lines = {}   -- text lines
  local hls = {}     -- { row, hl_group, col_start, col_end }

  local indent_prefix = "  │ "

  -- Helper: add a line and return its 0-based row index
  local function add(text)
    table.insert(lines, text)
    return #lines - 1
  end

  -- Helper: add a highlighted line
  local function add_hl(text, hl, col_s, col_e)
    local row = add(text)
    table.insert(hls, { row, hl, col_s or 0, col_e or -1 })
    return row
  end

  -- ── Compile error mode ──
  if st.compile_error then
    add("")
    add_hl("  Compile Error", "DiagnosticError")
    add("")
    for line in vim.gsplit(vim.trim(st.compile_error), "\n") do
      add("    " .. line)
    end
    add("")

    vim.api.nvim_buf_set_lines(st.bufnr, 0, -1, false, lines)
    for _, h in ipairs(hls) do
      pcall(vim.api.nvim_buf_add_highlight, st.bufnr, ns_runner, h[2], h[1], h[3], h[4])
    end
    vim.bo[st.bufnr].modifiable = false
    return
  end

  local results = st.results
  local total = #results
  local passed = 0
  for _, r in ipairs(results) do
    if r.verdict == "AC" then passed = passed + 1 end
  end
  local all_passed = (passed == total)

  -- ── Header line ──
  add("")
  local header_text = all_passed and "  Accepted" or "  " .. verdict_label(results[st.focused_idx].verdict)
  header_text = header_text .. string.format("    %d/%d testcases passed", passed, total)
  add_hl(header_text, all_passed and "DiagnosticOk" or "DiagnosticError")

  -- ── Tab bar ──
  add("") -- spacing
  local tab_row = add("")  -- placeholder, will be replaced
  local tab_text = " "
  local tab_hls = {}  -- { col_start, col_end, hl_group }

  for i, r in ipairs(results) do
    local label = (" Case (%d) "):format(i)
    local hl = case_tab_hl(r.verdict, i == st.focused_idx)
    local col_start = #tab_text
    tab_text = tab_text .. label
    local col_end = #tab_text
    table.insert(tab_hls, { col_start, col_end, hl })
    if i ~= total then
      tab_text = tab_text .. " "
    end
  end
  lines[tab_row + 1] = tab_text  -- +1 because lines is 1-indexed
  for _, th in ipairs(tab_hls) do
    table.insert(hls, { tab_row, th[3], th[1], th[2] })
  end

  -- ── Per-case content ──
  local r = results[st.focused_idx]

  -- Case verdict sub-header
  add("")
  local verdict_text = "  " .. verdict_label(r.verdict)
  if r.time_ms then
    verdict_text = verdict_text .. string.format("  (%.0f ms)", r.time_ms)
  end
  local verdict_hl_group
  if r.verdict == "AC" then verdict_hl_group = "DiagnosticOk"
  elseif r.verdict == "WA" then verdict_hl_group = "DiagnosticError"
  else verdict_hl_group = "DiagnosticWarn"
  end
  add_hl(verdict_text, verdict_hl_group)

  -- Input section
  add("")
  add_hl("  Input", "DmojResultNormal")
  for line in vim.gsplit(r.input, "\n") do
    local row = add("  " .. indent_prefix .. line)
    table.insert(hls, { row, "DmojResultIndent", 0, #("  " .. indent_prefix) })
  end

  -- Output section (actual)
  add("")
  add_hl("  Output", "DmojResultNormal")
  for line in vim.gsplit(r.actual, "\n") do
    local row = add("  " .. indent_prefix .. line)
    table.insert(hls, { row, "DmojResultIndent", 0, #("  " .. indent_prefix) })
    -- Highlight actual output red if wrong
    if r.verdict ~= "AC" then
      table.insert(hls, { row, "DiagnosticError", #("  " .. indent_prefix), -1 })
    end
  end

  -- Expected section
  add("")
  add_hl("  Expected", "DmojResultNormal")
  for line in vim.gsplit(r.expected, "\n") do
    local row = add("  " .. indent_prefix .. line)
    table.insert(hls, { row, "DmojResultIndent", 0, #("  " .. indent_prefix) })
  end

  -- Stderr section (if any)
  if r.stderr and vim.trim(r.stderr) ~= "" then
    add("")
    add_hl("  Stderr", "DiagnosticWarn")
    for line in vim.gsplit(vim.trim(r.stderr), "\n") do
      local row = add("  " .. indent_prefix .. line)
      table.insert(hls, { row, "DmojResultIndent", 0, #("  " .. indent_prefix) })
      table.insert(hls, { row, "DiagnosticWarn", #("  " .. indent_prefix), -1 })
    end
  end

  add("")

  -- ── Write to buffer ──
  vim.api.nvim_buf_set_lines(st.bufnr, 0, -1, false, lines)
  vim.api.nvim_buf_clear_namespace(st.bufnr, ns_runner, 0, -1)
  for _, h in ipairs(hls) do
    pcall(vim.api.nvim_buf_add_highlight, st.bufnr, ns_runner, h[2], h[1], h[3], h[4])
  end

  vim.bo[st.bufnr].modifiable = false

  -- Resize window height to fit content (capped)
  if st.win and vim.api.nvim_win_is_valid(st.win) then
    local max_h = math.floor(vim.o.lines * 0.75)
    local new_h = math.min(#lines + 2, max_h)
    vim.api.nvim_win_set_height(st.win, new_h)
  end
end

--- Switch to a different test case tab.
---@param idx number 1-based case index
local function switch_case(idx)
  local st = M._state
  if not st then return end
  if not st.results[idx] or idx == st.focused_idx then return end
  st.focused_idx = idx
  render_results()
  -- Move cursor to top
  if st.win and vim.api.nvim_win_is_valid(st.win) then
    pcall(vim.api.nvim_win_set_cursor, st.win, { 1, 0 })
  end
end

--- Set up keybindings for the result buffer.
---@param bufnr number
---@param num_cases number
local function setup_keymaps(bufnr, num_cases)
  -- Number keys 1-9 to jump to case
  for i = 1, math.min(num_cases, 9) do
    vim.keymap.set("n", tostring(i), function()
      switch_case(i)
    end, { buffer = bufnr, nowait = true })
  end

  -- H/L to navigate between cases (wrapping)
  vim.keymap.set("n", "H", function()
    local st = M._state
    if not st then return end
    local new_idx = st.focused_idx - 1
    if new_idx < 1 then new_idx = #st.results end
    switch_case(new_idx)
  end, { buffer = bufnr, nowait = true })

  vim.keymap.set("n", "L", function()
    local st = M._state
    if not st then return end
    local new_idx = st.focused_idx + 1
    if new_idx > #st.results then new_idx = 1 end
    switch_case(new_idx)
  end, { buffer = bufnr, nowait = true })
end

--- Show the local test results in a floating window with per-case tabs.
--- Layout inspired by leetcode.nvim's console result panel.
---@param results table[] list of { case_num, verdict, input, expected, actual, stderr, time_ms }
---@param compile_error? string compile error output if any
function M.show_results(results, compile_error)
  setup_highlights()

  local popup_width = math.max(60, math.floor(vim.o.columns * 0.6))

  -- Determine overall verdict for border/title
  local is_ce = compile_error and vim.trim(compile_error) ~= ""
  local all_passed = true
  if not is_ce then
    for _, r in ipairs(results) do
      if r.verdict ~= "AC" then all_passed = false; break end
    end
  end

  local title_str
  if is_ce then
    title_str = "✗ Compile Error"
  elseif all_passed then
    title_str = "✓ Local Test Results"
  else
    title_str = "✗ Local Test Results"
  end

  -- Find first failing case to focus initially (or case 1 if all pass)
  local initial_idx = 1
  if not is_ce then
    for i, r in ipairs(results) do
      if r.verdict ~= "AC" then
        initial_idx = i
        break
      end
    end
  end

  -- Create buffer and window
  local bufnr = ui.create_buf("dmoj://run-results", { "" }, {})
  local popup_height = math.min(20, math.floor(vim.o.lines * 0.75))
  local win = ui.open_float(bufnr, {
    title = title_str,
    width = popup_width,
    height = popup_height,
  })

  -- Border color
  local border_hl = is_ce and "DiagnosticError"
    or (all_passed and "DiagnosticOk" or "DiagnosticError")
  if vim.api.nvim_win_is_valid(win) then
    vim.wo[win].winhighlight = "Normal:NormalFloat,FloatBorder:" .. border_hl .. ",FloatTitle:" .. border_hl
    vim.wo[win].cursorline = false
  end

  -- Store state
  M._state = {
    results = results,
    focused_idx = initial_idx,
    bufnr = bufnr,
    win = win,
    compile_error = is_ce and compile_error or nil,
  }

  -- Set up keymaps (only for non-CE)
  if not is_ce and #results > 0 then
    setup_keymaps(bufnr, #results)
  end

  -- Initial render
  render_results()

  -- Clean up state when window closes
  vim.api.nvim_create_autocmd("WinClosed", {
    pattern = tostring(win),
    once = true,
    callback = function()
      M._state = nil
    end,
  })
end

--- Main entry point: compile and run code against sample test cases.
--- Called by :Dmoj run
---@param opts? { problem_code?: string, lang?: string }
function M.run(opts)
  opts = opts or {}
  local bufnr = vim.api.nvim_get_current_buf()
  local problem_code = opts.problem_code or vim.b[bufnr].dmoj_problem_code
  local lang = opts.lang or vim.b[bufnr].dmoj_language or config.options.lang

  if not problem_code then
    ui.notify("No problem context. Open a problem first with :Dmoj open <code>", vim.log.levels.WARN)
    return
  end

  if not lang then
    ui.notify("No language set. Configure config.options.lang", vim.log.levels.WARN)
    return
  end

  local cmds = resolve_commands(lang)
  if not cmds then
    ui.notify("Unsupported language for local run: " .. lang, vim.log.levels.ERROR)
    return
  end

  -- Get the source file path from the current buffer
  local src_path = vim.api.nvim_buf_get_name(bufnr)
  if src_path == "" or vim.bo[bufnr].buftype ~= "" then
    ui.notify("Current buffer is not a file. Open your solution file first.", vim.log.levels.WARN)
    return
  end

  -- Save the buffer first
  if vim.bo[bufnr].modified then
    vim.cmd("write")
  end

  local cancel = ui.loading("Fetching sample test cases...")

  -- Fetch the problem page to extract samples
  local headers = auth.auth_headers() or {}
  local url = config.options.base_url .. "/problem/" .. problem_code

  http.get(url, { headers = headers, follow_redirects = true, timeout = 30 }, function(resp)
    cancel()

    if resp.status ~= 200 then
      ui.notify("Failed to fetch problem page: HTTP " .. resp.status, vim.log.levels.ERROR)
      return
    end

    -- Extract description HTML (same logic as description.lua)
    -- DMOJ wraps content in <div class="content-description"><html><body>...</body></html></div>
    local desc_html
    local desc_div = resp.body:match('<div[^>]*class="[^"]*content%-description[^"]*"[^>]*>(.*)')
    if desc_div then
      desc_html = desc_div:match("<body>(.-)</body>")
      if not desc_html then
        local depth = 1
        local pos = 1
        while depth > 0 and pos <= #desc_div do
          local open_s, open_e = desc_div:find("<div[^>]*>", pos)
          local close_s, close_e = desc_div:find("</div>", pos)
          if not close_s then break end
          if open_s and open_s < close_s then
            depth = depth + 1
            pos = open_e + 1
          else
            depth = depth - 1
            if depth == 0 then
              desc_html = desc_div:sub(1, close_s - 1)
            else
              pos = close_e + 1
            end
          end
        end
      end
    end
    if not desc_html then
      desc_html = resp.body:match('<div[^>]*id="problem%-markdown[^"]*"[^>]*>(.-)</div>')
    end
    if not desc_html then
      desc_html = resp.body:match('<div[^>]*class="problem%-content[^"]*"[^>]*>(.-)<div[^>]*class="problem%-info')
    end
    if not desc_html then
      desc_html = resp.body:match('<div[^>]*id="content%-body"[^>]*>(.-)<div[^>]*id="comment')
    end

    if not desc_html then
      ui.notify("Could not extract problem description for sample test cases.", vim.log.levels.ERROR)
      return
    end

    local samples = M.extract_samples(desc_html)
    if #samples == 0 then
      ui.notify("No sample test cases found in the problem description.", vim.log.levels.WARN)
      return
    end

    -- Step 1: Compile (if needed)
    local compile_cancel = ui.loading("Compiling...")
    M.compile(src_path, lang, function(compile_ok, compile_err)
      compile_cancel()

      if not compile_ok then
        M.show_results({}, compile_err)
        return
      end

      -- Step 2: Run against each sample
      local results = {}
      local completed = 0
      local run_cancel = ui.loading("Running test cases...")

      local timeout_ms = 10000 -- 10 second timeout per test case

      for i, sample in ipairs(samples) do
        M.run_with_input(src_path, lang, sample.input, timeout_ms, function(exit_code, stdout, stderr, timed_out)
          local verdict
          if timed_out then
            verdict = "TLE"
          elseif exit_code ~= 0 then
            verdict = "RE"
          elseif M.compare_output(stdout, sample.output) then
            verdict = "AC"
          else
            verdict = "WA"
          end

          results[i] = {
            case_num = i,
            verdict = verdict,
            input = sample.input,
            expected = sample.output,
            actual = stdout,
            stderr = stderr,
            time_ms = nil, -- TODO: measure elapsed time
          }

          completed = completed + 1
          if completed == #samples then
            run_cancel()

            -- Sort results by case number
            table.sort(results, function(a, b) return a.case_num < b.case_num end)

            -- Show results
            M.show_results(results)
          end
        end)
      end
    end)
  end)
end

return M
