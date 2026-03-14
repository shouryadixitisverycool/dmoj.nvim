local M = {}

local api = require("dmoj.api")
local ui = require("dmoj.ui")
local config = require("dmoj.config")
local description = require("dmoj.description")

--- Language key -> { extension, comment prefix } mapping.
---@type table<string, { ext: string, comment: string }>
local lang_info = {
  C      = { ext = "c",     comment = "//" },
  CPP03  = { ext = "cpp",   comment = "//" },
  CPP11  = { ext = "cpp",   comment = "//" },
  CPP14  = { ext = "cpp",   comment = "//" },
  CPP17  = { ext = "cpp",   comment = "//" },
  CPP20  = { ext = "cpp",   comment = "//" },
  CPP23  = { ext = "cpp",   comment = "//" },
  JAVA   = { ext = "java",  comment = "//" },
  JAVA8  = { ext = "java",  comment = "//" },
  JAVA11 = { ext = "java",  comment = "//" },
  JAVA17 = { ext = "java",  comment = "//" },
  JAVA21 = { ext = "java",  comment = "//" },
  PY2    = { ext = "py",    comment = "#" },
  PY3    = { ext = "py",    comment = "#" },
  PYPY   = { ext = "py",    comment = "#" },
  PYPY3  = { ext = "py",    comment = "#" },
  RUBY   = { ext = "rb",    comment = "#" },
  RUST   = { ext = "rs",    comment = "//" },
  GO     = { ext = "go",    comment = "//" },
  KOTLIN = { ext = "kt",    comment = "//" },
  SWIFT  = { ext = "swift",  comment = "//" },
  HASK   = { ext = "hs",    comment = "--" },
  PERL   = { ext = "pl",    comment = "#" },
  LUA    = { ext = "lua",   comment = "--" },
  PHP    = { ext = "php",   comment = "//" },
  SCALA  = { ext = "scala", comment = "//" },
  DART   = { ext = "dart",  comment = "//" },
  OCAML  = { ext = "ml",    comment = "(*" },
  PAS    = { ext = "pas",   comment = "//" },
  NASM   = { ext = "asm",   comment = ";" },
  TEXT   = { ext = "txt",   comment = "#" },
  MONO   = { ext = "cs",    comment = "//" },
}

--- Get code boilerplate for a language.
---@param lang_key string
---@return string
local function get_boilerplate(lang_key)
  local key = lang_key:upper()

  if key == "C" or key == "C11" or key == "C99" then
    return table.concat({
      "#include <stdio.h>",
      "#include <stdlib.h>",
      "#include <string.h>",
      "",
      "int main() {",
      "    int t;",
      '    scanf("%d", &t);',
      "    while (t--) {",
      "        ",
      "    }",
      "    return 0;",
      "}",
      "",
    }, "\n")
  end

  if key:find("^CPP") then
    return table.concat({
      "#include <bits/stdc++.h>",
      "using namespace std;",
      "",
      "int main() {",
      "    ios_base::sync_with_stdio(false);",
      "    cin.tie(NULL);",
      "",
      "    int t;",
      "    cin >> t;",
      "    while (t--) {",
      "        ",
      "    }",
      "    return 0;",
      "}",
      "",
    }, "\n")
  end

  if key:find("^PY") or key:find("^PYPY") then
    return table.concat({
      "t = int(input())",
      "for _ in range(t):",
      "    ",
      "",
    }, "\n")
  end

  if key:find("^JAVA") then
    return table.concat({
      "import java.util.*;",
      "",
      "public class Solution {",
      "    public static void main(String[] args) {",
      "        Scanner sc = new Scanner(System.in);",
      "        int t = sc.nextInt();",
      "        while (t-- > 0) {",
      "            ",
      "        }",
      "    }",
      "}",
      "",
    }, "\n")
  end

  if key == "RUST" then
    return table.concat({
      "use std::io::{self, BufRead, Write, BufWriter};",
      "",
      "fn main() {",
      "    let stdin = io::stdin();",
      "    let stdout = io::stdout();",
      "    let mut out = BufWriter::new(stdout.lock());",
      "",
      "    let mut line = String::new();",
      "    stdin.lock().read_line(&mut line).unwrap();",
      "    let t: usize = line.trim().parse().unwrap();",
      "",
      "    for _ in 0..t {",
      "        ",
      "    }",
      "}",
      "",
    }, "\n")
  end

  if key == "GO" then
    return table.concat({
      'package main',
      '',
      'import (',
      '    "bufio"',
      '    "fmt"',
      '    "os"',
      ')',
      '',
      'func main() {',
      '    reader := bufio.NewReader(os.Stdin)',
      '    var t int',
      '    fmt.Fscan(reader, &t)',
      '    for ; t > 0; t-- {',
      '        ',
      '    }',
      '}',
      '',
    }, "\n")
  end

  -- Default: empty file
  return ""
end

---@param lang_key string
---@return string ext, string comment_prefix
local function info_for_lang(lang_key)
  if lang_info[lang_key] then
    return lang_info[lang_key].ext, lang_info[lang_key].comment
  end
  -- Check known prefixes in order of length (longest first)
  local prefixes = {}
  for prefix, _ in pairs(lang_info) do
    table.insert(prefixes, prefix)
  end
  table.sort(prefixes, function(a, b) return #a > #b end)
  for _, prefix in ipairs(prefixes) do
    if lang_key:sub(1, #prefix) == prefix then
      return lang_info[prefix].ext, lang_info[prefix].comment
    end
  end
  return "txt", "#"
end

--- Decode common HTML entities in scraped names.
---@param s string
---@return string
local function decode_entities(s)
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
  return s
end

--- Cached problem list to avoid re-fetching when re-opening picker.
---@type table[]|nil
local problems_cache = nil

--- Fetch problems (with caching) then call callback.
--- Automatically fetches all pages when pagination is detected.
---@param callback fun(problems: table[])
local function fetch_problems(callback)
  if problems_cache then
    callback(problems_cache)
    return
  end

  local all_objects = {}
  local cancel = ui.loading("Fetching problems...")

  local function fetch_page(page)
    cancel()
    cancel = ui.loading(string.format("Fetching problems (page %d)...", page))
    api.problems({ page = page }, function(data, err)
      if err then
        cancel()
        -- If we already have some results, use them
        if #all_objects > 0 then
          for _, p in ipairs(all_objects) do
            p.name = decode_entities(p.name or "")
            p.group = decode_entities(p.group or "")
          end
          problems_cache = all_objects
          callback(all_objects)
        else
          ui.notify(err, vim.log.levels.ERROR)
        end
        return
      end
      local objects = data and data.objects or {}
      for _, p in ipairs(objects) do
        table.insert(all_objects, p)
      end

      -- Check if there are more pages
      local has_more = data and data.has_more
      local total_pages = data and data.total_pages or 1
      if has_more and page < total_pages then
        fetch_page(page + 1)
      else
        cancel()
        -- Decode HTML entities in names
        for _, p in ipairs(all_objects) do
          p.name = decode_entities(p.name or "")
          p.group = decode_entities(p.group or "")
        end
        problems_cache = all_objects
        callback(all_objects)
      end
    end)
  end

  fetch_page(1)
end

--- Invalidate the cached problem list.
function M.clear_cache()
  problems_cache = nil
end

--- Open the problem list using telescope.
function M.open()
  local has_telescope, _ = pcall(require, "telescope")
  if has_telescope then
    M.open_telescope()
  else
    M.open_fallback()
  end
end

--- Telescope-based problem picker.
function M.open_telescope()
  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")
  local entry_display = require("telescope.pickers.entry_display")

  fetch_problems(function(problems)
    if #problems == 0 then
      ui.notify("No problems found. Are you logged in?", vim.log.levels.WARN)
      return
    end

    -- Fixed-width table columns for even alignment
    local displayer = entry_display.create({
      separator = " ",
      items = {
        { width = 2 },   -- status icon
        { width = 42 },  -- name
        { width = 22 },  -- category/group
        { width = 8 },   -- points
      },
    })

    local function make_display(entry)
      local p = entry.problem
      local icon, icon_hl
      if p.status == "ac" then
        icon = "✔"
        icon_hl = "DiagnosticOk"
      elseif p.status == "attempted" then
        icon = "✘"
        icon_hl = "DiagnosticError"
      else
        icon = " "
        icon_hl = "Comment"
      end
      return displayer({
        { icon, icon_hl },
        { p.name or "" },
        { p.group or "", "TelescopeResultsComment" },
        { string.format("%.0f pts", p.points or 0), "TelescopeResultsNumber" },
      })
    end

    pickers.new({}, {
      prompt_title = "Select a Problem",
      results_title = string.format("%d problems", #problems),
      finder = finders.new_table({
        results = problems,
        entry_maker = function(problem)
          local search_text = string.format(
            "%s %s %s %s",
            problem.name or "",
            problem.code or "",
            problem.group or "",
            table.concat(problem.types or {}, " ")
          )
          return {
            value = problem.code,
            display = make_display,
            ordinal = search_text,
            problem = problem,
          }
        end,
      }),
      sorter = conf.generic_sorter({}),
      attach_mappings = function(prompt_bufnr, map)
        -- Enter: open problem
        actions.select_default:replace(function()
          local entry = action_state.get_selected_entry()
          actions.close(prompt_bufnr)
          if entry then
            M.open_problem(entry.value)
          end
        end)

        -- Ctrl-o: open in browser
        map("i", "<C-o>", function()
          local entry = action_state.get_selected_entry()
          if entry then
            local url = config.options.base_url .. "/problem/" .. entry.value
            vim.fn.jobstart({ config.options.open_cmd, url }, { detach = true })
          end
        end)
        map("n", "o", function()
          local entry = action_state.get_selected_entry()
          if entry then
            local url = config.options.base_url .. "/problem/" .. entry.value
            vim.fn.jobstart({ config.options.open_cmd, url }, { detach = true })
          end
        end)

        -- Ctrl-r: refresh cache
        map("i", "<C-r>", function()
          actions.close(prompt_bufnr)
          M.clear_cache()
          M.open_telescope()
        end)

        return true
      end,
    }):find()
  end)
end

--- Fallback floating window picker (no telescope dependency).
function M.open_fallback()
  fetch_problems(function(problems)
    if #problems == 0 then
      ui.notify("No problems found. Are you logged in?", vim.log.levels.WARN)
      return
    end

    local lines = {}
    table.insert(lines, string.format(" DMOJ Problems  (%d total)", #problems))
    table.insert(lines, string.rep("─", 80))
    table.insert(lines, string.format("     %-42s  %-22s  %s", "NAME", "GROUP", "PTS"))
    table.insert(lines, string.rep("─", 80))

    for i, p in ipairs(problems) do
      local icon
      if p.status == "ac" then
        icon = "✔ "
      elseif p.status == "attempted" then
        icon = "✘ "
      else
        icon = "  "
      end
      lines[i + 4] = string.format(
        "%s %-42s  %-22s  %.0f pts",
        icon, (p.name or ""):sub(1, 42), (p.group or ""):sub(1, 22), p.points or 0
      )
    end

    table.insert(lines, "")
    table.insert(lines, string.rep("─", 80))
    table.insert(lines, " [Enter] Open  [o] Browser  [q] Close")

    local bufnr = ui.create_buf("dmoj://problems", lines, { filetype = "dmoj" })
    ui.open_float(bufnr, { title = "DMOJ Problems" })

    local kopts = { buffer = bufnr, nowait = true, silent = true }

    vim.keymap.set("n", "<CR>", function()
      local row = vim.api.nvim_win_get_cursor(0)[1]
      -- rows 1-4 are header, problems start at row 5
      local idx = row - 4
      if idx >= 1 and idx <= #problems then
        local p = problems[idx]
        local wins = vim.fn.win_findbuf(bufnr)
        for _, w in ipairs(wins) do
          if vim.api.nvim_win_is_valid(w) then vim.api.nvim_win_close(w, true) end
        end
        M.open_problem(p.code)
      end
    end, kopts)

    vim.keymap.set("n", "o", function()
      local row = vim.api.nvim_win_get_cursor(0)[1]
      local idx = row - 4
      if idx >= 1 and idx <= #problems then
        local p = problems[idx]
        vim.fn.jobstart({ config.options.open_cmd, config.options.base_url .. "/problem/" .. p.code }, { detach = true })
      end
    end, kopts)
  end)
end

--- Open a specific problem: fetch metadata, show description on the left,
--- open a code buffer on the right.
---@param code string problem code
function M.open_problem(code)
  local cancel = ui.loading("Loading " .. code .. "...")

  api.problem(code, function(meta, err)
    cancel()
    if err then
      ui.notify(err, vim.log.levels.ERROR)
      return
    end

    -- Determine file extension from configured language
    local lang = config.options.lang
    if meta.languages and #meta.languages > 0 then
      local supported = false
      local lang_lower = lang:lower()
      -- Try exact match
      for _, l in ipairs(meta.languages) do
        if l == lang then supported = true; break end
      end
      -- Try fuzzy match
      if not supported then
        for _, l in ipairs(meta.languages) do
          local stripped = l:lower():gsub("[%s%+%-%_]", "")
          local key_stripped = lang_lower:gsub("[%s%+%-%_]", "")
          -- e.g. "c++ 17" -> "c17", "cpp17" -> "cpp17". Wait, c++ becomes c?
          -- Let's just do simple contains
          if l:lower():find(lang_lower, 1, true) or lang_lower:find(l:lower():gsub("%s+", ""), 1, true) then
            supported = true
            break
          end
        end
      end
      -- Hardcoded common aliases
      if not supported then
        local aliases = {
          cpp17 = { "c++ 17", "c++17" },
          cpp11 = { "c++ 11", "c++11" },
          cpp14 = { "c++ 14", "c++14" },
          cpp20 = { "c++ 20", "c++20" },
          py3 = { "python 3", "python3" },
          py2 = { "python 2", "python2" },
          java = { "java 8", "java 11", "java 17", "java 21" }
        }
        local checks = aliases[lang_lower]
        if checks then
          for _, l in ipairs(meta.languages) do
            for _, c in ipairs(checks) do
              if l:lower() == c then supported = true; break end
            end
            if supported then break end
          end
        end
      end

      if not supported then
        lang = meta.languages[1]
        ui.notify("Language " .. config.options.lang .. " not supported, using " .. lang, vim.log.levels.WARN)
      end
    end

    local ext, _ = info_for_lang(lang)
    local solution_dir = config.options.storage_dir .. "/solutions"
    vim.fn.mkdir(solution_dir, "p")
    local filepath = solution_dir .. "/" .. code .. "." .. ext

    -- Create solution file with boilerplate if it doesn't exist
    if vim.fn.filereadable(filepath) == 0 then
      local f = io.open(filepath, "w")
      if f then
        f:write(get_boilerplate(lang))
        f:close()
      end
    end

    -- Open the solution file in a new tab (like leetcode.nvim)
    -- This avoids buffer name conflicts with dashboard/description buffers
    local ok, edit_err = pcall(vim.cmd, "$tabe " .. vim.fn.fnameescape(filepath))
    if not ok then
      vim.notify("Could not tabe file, falling back to bufadd: " .. tostring(edit_err), vim.log.levels.WARN)
      -- Fallback: try bufadd approach
      local buf = vim.fn.bufadd(filepath)
      vim.fn.bufload(buf)
      vim.cmd("$tabnew")
      vim.api.nvim_set_current_buf(buf)
    end

    -- Store problem metadata on the buffer for submit to use
    local bufnr = vim.api.nvim_get_current_buf()
    
    -- Enable line numbers for the code buffer
    local win = vim.api.nvim_get_current_win()
    vim.wo[win].number = true
    vim.wo[win].relativenumber = false
    vim.wo[win].signcolumn = "yes"
    
    vim.b[bufnr].dmoj_problem_code = code
    vim.b[bufnr].dmoj_language = lang

    -- Fetch and show description in a left split
    description.show(code, meta)
  end)
end

--- Open a problem picker and call `on_select(code)` with the chosen problem code.
--- Reuses the same Telescope/fallback UI as `M.open()`, but instead of opening
--- the problem it passes the code to the caller's callback.
---@param on_select fun(code: string) called with the selected problem code
---@param prompt_title? string custom title for the picker (default "Select a Problem")
function M.pick_problem(on_select, prompt_title)
  prompt_title = prompt_title or "Select a Problem"

  local has_telescope, _ = pcall(require, "telescope")
  if has_telescope then
    M._pick_telescope(on_select, prompt_title)
  else
    M._pick_fallback(on_select, prompt_title)
  end
end

--- Telescope picker that calls on_select(code) instead of open_problem.
---@param on_select fun(code: string)
---@param prompt_title string
function M._pick_telescope(on_select, prompt_title)
  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")
  local entry_display = require("telescope.pickers.entry_display")

  fetch_problems(function(problems)
    if #problems == 0 then
      ui.notify("No problems found. Are you logged in?", vim.log.levels.WARN)
      return
    end

    local displayer = entry_display.create({
      separator = " ",
      items = {
        { width = 2 },   -- status icon
        { width = 42 },  -- name
        { width = 22 },  -- category/group
        { width = 8 },   -- points
      },
    })

    local function make_display(entry)
      local p = entry.problem
      local icon, icon_hl
      if p.status == "ac" then
        icon = "✔"
        icon_hl = "DiagnosticOk"
      elseif p.status == "attempted" then
        icon = "✘"
        icon_hl = "DiagnosticError"
      else
        icon = " "
        icon_hl = "Comment"
      end
      return displayer({
        { icon, icon_hl },
        { p.name or "" },
        { p.group or "", "TelescopeResultsComment" },
        { string.format("%.0f pts", p.points or 0), "TelescopeResultsNumber" },
      })
    end

    pickers.new({}, {
      prompt_title = prompt_title,
      results_title = string.format("%d problems", #problems),
      finder = finders.new_table({
        results = problems,
        entry_maker = function(problem)
          local search_text = string.format(
            "%s %s %s %s",
            problem.name or "",
            problem.code or "",
            problem.group or "",
            table.concat(problem.types or {}, " ")
          )
          return {
            value = problem.code,
            display = make_display,
            ordinal = search_text,
            problem = problem,
          }
        end,
      }),
      sorter = conf.generic_sorter({}),
      attach_mappings = function(prompt_bufnr, _)
        actions.select_default:replace(function()
          local entry = action_state.get_selected_entry()
          actions.close(prompt_bufnr)
          if entry then
            on_select(entry.value)
          end
        end)
        return true
      end,
    }):find()
  end)
end

--- Fallback float picker that calls on_select(code) instead of open_problem.
---@param on_select fun(code: string)
---@param prompt_title string
function M._pick_fallback(on_select, prompt_title)
  fetch_problems(function(problems)
    if #problems == 0 then
      ui.notify("No problems found. Are you logged in?", vim.log.levels.WARN)
      return
    end

    local lines = {}
    table.insert(lines, string.format(" %s  (%d total)", prompt_title, #problems))
    table.insert(lines, string.rep("─", 80))
    table.insert(lines, string.format("     %-42s  %-22s  %s", "NAME", "GROUP", "PTS"))
    table.insert(lines, string.rep("─", 80))

    for i, p in ipairs(problems) do
      local icon
      if p.status == "ac" then
        icon = "✔ "
      elseif p.status == "attempted" then
        icon = "✘ "
      else
        icon = "  "
      end
      lines[i + 4] = string.format(
        "%s %-42s  %-22s  %.0f pts",
        icon, (p.name or ""):sub(1, 42), (p.group or ""):sub(1, 22), p.points or 0
      )
    end

    table.insert(lines, "")
    table.insert(lines, string.rep("─", 80))
    table.insert(lines, " [Enter] Select  [q] Close")

    local bufnr = ui.create_buf("dmoj://pick_problem", lines, { filetype = "dmoj" })
    local win = ui.open_float(bufnr, { title = prompt_title })

    local kopts = { buffer = bufnr, nowait = true, silent = true }

    vim.keymap.set("n", "<CR>", function()
      local row = vim.api.nvim_win_get_cursor(0)[1]
      local idx = row - 4
      if idx >= 1 and idx <= #problems then
        local p = problems[idx]
        if vim.api.nvim_win_is_valid(win) then
          vim.api.nvim_win_close(win, true)
        end
        on_select(p.code)
      end
    end, kopts)
  end)
end

return M
