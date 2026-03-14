# AGENTS.md

Guidelines for agentic coding assistants working in `dmoj.nvim`.
This is a Neovim plugin for the DMOJ online judge, modelled on `leetcode.nvim`.

## 1. Project Structure

```
plugin/dmoj.lua            -- Entry point (auto-loaded by Neovim, registers :Dmoj)
lua/dmoj/
  init.lua                 -- setup(), command dispatch, global keymaps
  config.lua               -- Config schema (dmoj.Config class) and defaults
  http.lua                 -- Async curl wrapper via vim.system()
  auth.lua                 -- Cookie storage, login, CSRF extraction
  api.lua                  -- DMOJ web scraper (problems, metadata)
  ui.lua                   -- Buffer creation, split/float windows, loading spinner
  dashboard.lua            -- Home screen (ASCII art, menu, highlights)
  problems.lua             -- Telescope picker + open-problem workflow
  description.lua          -- HTML-to-plaintext renderer (LaTeX, tables, inline hl)
  submit.lua               -- Submit, poll/scrape results, verdict popup
  submissions.lua          -- Submission history list
  runner.lua               -- Local compile+run against sample test cases
```

## 2. Build, Lint, and Test Commands

No build step. Lua 5.1 / LuaJIT, minimum Neovim 0.9+.

```bash
# Syntax check (always run after edits)
luac -p lua/dmoj/runner.lua          # single file
luac -p lua/dmoj/*.lua               # all files
```

No automated test suite. Testing is manual. Live-reload a module in Neovim:
```lua
:lua package.loaded["dmoj.runner"] = nil
```

No formatter is configured. If using stylua, use 2-space indent and 120 column width.

## 3. Code Style

### Module Pattern

Every file follows this structure:
```lua
local M = {}
local config = require("dmoj.config")

--- Brief description.
---@param arg string
---@return boolean
function M.func(arg)
  -- ...
end

return M
```

- Exported table is always `M`
- Private helpers: `local function name()` at module level
- Semi-private internals: `M._name` prefix (e.g., `M._state`)

### Indentation

2 spaces, no tabs. Aim for 80-120 char lines; long regexes may exceed this.

### Imports

All `require()` at top of file as locals. Lazy require only for optional deps:
```lua
local ok, pickers = pcall(require, "telescope.pickers")
if not ok then return false end
```

### Naming Conventions

| Kind | Convention | Examples |
|------|-----------|----------|
| Functions, variables | `snake_case` | `fetch_problems`, `lang_key` |
| Module table | `M` | `local M = {}` |
| Private fields | `M._name` | `M._state`, `M._result_bufs` |
| LuaLS classes | `PascalCase` | `dmoj.Config`, `DmojRunnerState` |
| Highlight groups | `PascalCase` + prefix | `DmojCaseOk`, `DmojCaseFocusErr` |
| Namespace strings | `snake_case` + prefix | `"dmoj_runner"` |
| String constants | `UPPER_CASE` | `LOGO`, `UA` |

### Type Annotations (LuaLS)

Always annotate exported functions and structured data:
```lua
---@class dmoj.Config
---@field base_url string
---@field storage_dir string         -- optional fields use ?

--- Fetch problem metadata.
---@param code string The problem code
---@param callback fun(data: table|nil, err: string|nil)
function M.problem(code, callback)
```

### Error Handling

1. **User-facing**: `ui.notify("message", vim.log.levels.ERROR)`
2. **Fallible API calls**: wrap with `pcall(vim.api.nvim_buf_add_highlight, ...)`
3. **Async callbacks**: `(data, err)` tuple -- `callback(result, nil)` or `callback(nil, "msg")`
4. **Guard clauses**: `if not vim.api.nvim_buf_is_valid(bufnr) then return end`

### State Management

- No global state. Module-level locals only (`M._state`, `M._result_bufs`)
- Buffer-local vars via `vim.b[bufnr].dmoj_problem_code`
- Clean up on window close via `WinClosed` autocmd with `once = true`

## 4. Async Patterns

All network I/O is async via `vim.system()` shelling out to `curl`:
```lua
vim.system(curl_args, { text = true }, function(result)
  vim.schedule(function()
    -- ALWAYS vim.schedule() before touching UI from async callbacks
    callback({ status = code, body = body })
  end)
end)
```

- Polling: `vim.defer_fn(fn, delay_ms)`
- Timers: `vim.uv.new_timer()` (spinners, process timeouts)
- Process exec: `vim.fn.jobstart()` with `on_stdout`/`on_exit`

## 5. UI Patterns

Three component types:
1. **Left split** (descriptions): `ui.open_split_left(bufnr, { width = N })`
2. **Centered float** (results): `ui.open_float(bufnr, { title, width, height })`
3. **Full-window** (dashboard): `vim.api.nvim_set_current_buf(bufnr)`

All UI buffers via `ui.create_buf(name, lines, opts)`:
- `buftype="nofile"`, `bufhidden="wipe"`, `modifiable=false`
- Highlights via `nvim_buf_add_highlight()` with named namespaces
- Buffer-local keymaps: `q` close, `o` open browser, `<CR>` select

**Deprecated**: Do NOT use `vim.api.nvim_win_set_option()`. Use `vim.wo[win].prop` instead.

## 6. UI/UX Design Rules

- Mimic `leetcode.nvim` UI conventions
- **No markdown filetype** on description buffers -- custom highlights only
- **No backtick fences** -- code blocks as 4-space-indented text with `String` highlight
- **No `####` headings** -- emoji icon prefixes instead
- **Bold**: `@markup.strong`; **Inline code**: `@markup.raw`
- **Tables**: Unicode box-drawing (┌┬┐├┼┤└┴┘│─), not ASCII
- **HR separators**: Full-width `─`, dynamically resized via `WinResized` autocmd
- **Verdict colors**: AC=green (`DiagnosticOk`), WA=red (`DiagnosticError`), other=yellow (`DiagnosticWarn`)

## 7. Common Pitfalls

- No `print()` in production code. Use `vim.notify` with `vim.log.levels.DEBUG`.
- Always `vim.schedule()` when modifying UI from async callbacks.
- Lua `.-` is non-greedy and spans across HTML tag boundaries. Use backreferences
  (`<h(%d)>.-</h%1>`) or balanced-depth tracking for nested HTML.
- `gmatch("([^\n]*)\n?")` produces an extra empty match at end-of-string.
- All DMOJ data is fetched by scraping HTML pages (no API v2 dependency).
  Cookie-based authentication is required for most pages.
- HR row indices must use `header_end + 1` offset (accounts for the blank line
  between header and description content).
