# dmoj.nvim

A Neovim plugin for solving DMOJ (and DMOJ-based) online judge problems without leaving your editor. Browse problems, read problem statements, and submit solutions — all from Neovim.

Works with [dmoj.ca](https://dmoj.ca) and any self-hosted DMOJ instance (e.g. a college OJ).

## Features

- Dashboard home screen with ASCII art and quick-access menu
- Telescope-powered fuzzy problem picker (with fallback for no-telescope setups)
- Browse and join contests directly from Neovim
- Read problem statements scraped and rendered inline (no browser needed)
- Submit solutions directly from your buffer using session cookie auth
- Polls for the judge verdict automatically and shows per-case results
- Run solutions locally against sample test cases before submitting
- Solutions stored locally per problem code with correct file extension and comment style
- Full support for organization-private DMOJ instances (scrapes `/problems/` when API returns empty)

## Requirements

- Neovim >= 0.9
- `curl` (almost certainly already installed)
- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) (recommended, for the fuzzy problem picker)

## Installation

### lazy.nvim

```lua
{
  "your-username/dmoj.nvim",
  lazy = false,
  dependencies = {
    "nvim-telescope/telescope.nvim", -- optional but recommended
  },
  opts = {
    lang = "CPP17",
  },
}
```

To launch directly into the DMOJ dashboard from the terminal (like `leetcode.nvim`):

```bash
nvim dmoj.nvim
```

For optimal lazy-loading, only load the plugin eagerly when the arg matches:

```lua
{
  "your-username/dmoj.nvim",
  lazy = "dmoj.nvim" ~= vim.fn.argv(0, -1),
  dependencies = {
    "nvim-telescope/telescope.nvim",
  },
  opts = {
    lang = "CPP17",
    -- arg = "dmoj.nvim",  -- customize if desired (default: "dmoj.nvim")
  },
}
```

For a self-hosted DMOJ instance (e.g. a college OJ):

```lua
{
  "your-username/dmoj.nvim",
  lazy = false,
  dependencies = {
    "nvim-telescope/telescope.nvim",
  },
  opts = {
    base_url = "https://your-college-oj.example.com",
    lang = "C",
  },
}
```

For local development, point directly to the directory:

```lua
{
  dir = "~/projects/dmoj.nvim",
  name = "dmoj.nvim",
  lazy = false,
  opts = {
    base_url = "https://oj-test.iiit.ac.in",
    lang = "C",
  },
  config = function(_, opts)
    require("dmoj").setup(opts)
  end,
}
```

### Manual (no plugin manager)

```lua
vim.opt.runtimepath:prepend("~/projects/dmoj.nvim")
require("dmoj").setup({})
```

## Authentication

DMOJ doesn't expose a submission API, so the plugin submits via your browser session cookie — the same approach used by [leetcode.nvim](https://github.com/kawre/leetcode.nvim).

**Steps:**

1. Log in to your DMOJ instance in your browser
2. Open DevTools (`F12`) → **Network** tab
3. Click any request to your OJ domain
4. Go to **Request Headers** (not Response)
5. Find the `Cookie:` line and copy its entire value
   - It will look like: `csrftoken=abc123; sessionid=xyz789`
6. In Neovim, run `:Dmoj login` and paste it

The cookie is stored at `~/.local/share/nvim/dmoj/cookie.txt` with `600` permissions.

> **Note:** The cookie is tied to your browser session. If you log out in the browser or the session expires, you'll need to repeat this process.

## Configuration

```lua
require("dmoj").setup({
  -- Base URL of your DMOJ instance (default: "https://dmoj.ca")
  base_url = "https://dmoj.ca",

  -- Default language key for new solution files (default: "CPP17")
  -- Must match DMOJ's language keys (e.g. C, CPP17, PY3, JAVA, RUST, GO ...)
  lang = "CPP17",

  -- Directory to store cookies and solution files (default: stdpath("data") .. "/dmoj")
  storage_dir = vim.fn.stdpath("data") .. "/dmoj",

  -- Command to open URLs in your browser
  -- Linux: "xdg-open", macOS: "open", Windows: "start"
  open_cmd = "xdg-open",

  -- CLI argument for direct-launch: `nvim dmoj.nvim` opens the dashboard
  -- Set to "" to disable this feature
  arg = "dmoj.nvim",

  -- Default keymaps (set any to false to disable)
  keymaps = {
    list         = "<leader>dl",  -- Open problem list
    submit       = "<leader>ds",  -- Submit current buffer
    test         = "<leader>dt",  -- Run locally against sample cases
    desc         = "<leader>dd",  -- Show problem description
    open_browser = "<leader>do",  -- Open problem in browser
  },
})
```

### Language keys

| Language | Key |
|---|---|
| C | `C` |
| C++ 17 | `CPP17` |
| C++ 20 | `CPP20` |
| Python 3 | `PY3` |
| PyPy 3 | `PYPY3` |
| Java | `JAVA` |
| Rust | `RUST` |
| Go | `GO` |
| Kotlin | `KOTLIN` |
| Ruby | `RUBY` |
| Haskell | `HASK` |

## Commands

| Command | Description |
|---|---|
| `:Dmoj` or `:Dmoj menu` | Open the dashboard home screen |
| `:Dmoj list` | Browse problems with telescope fuzzy picker |
| `:Dmoj open <code>` | Open a specific problem by its code |
| `:Dmoj contests` | Browse contests (active, upcoming, past) |
| `:Dmoj submit` | Submit the current buffer |
| `:Dmoj submit <code>` | Submit the current buffer to a specific problem |
| `:Dmoj run` | Run current buffer locally against sample test cases |
| `:Dmoj desc` | Show the description for the current problem |
| `:Dmoj desc <code>` | Show the description for any problem |
| `:Dmoj result <id>` | Fetch and display a submission result |
| `:Dmoj browser` | Open the current problem in your browser |
| `:Dmoj login` | Paste your session cookie to log in |
| `:Dmoj logout` | Delete the stored cookie |
| `:Dmoj whoami` | Check who you're currently logged in as |
| `:Dmoj refresh` | Clear the cached problem list |

## Dashboard

Opened with `:Dmoj menu`. Shows an ASCII art logo and quick-access menu:

```
     /$$$$$$$  /$$      /$$  /$$$$$$     /$$$$$$
    | $$__  $$| $$$    /$$$ /$$__  $$   |_  $$_/
    | $$  \ $$| $$$$  /$$$$| $$  \ $$     | $$
    | $$  | $$| $$ $$/$$ $$| $$  | $$     | $$
    | $$  | $$| $$  $$$| $$| $$  | $$     | $$
    | $$  | $$| $$\  $ | $$| $$  | $$ /$$ | $$
    | $$$$$$$/| $$ \/  | $$|  $$$$$$/| $$$$$$/
    |_______/ |__/     |__/ \______/  \______/

                https://oj-test.iiit.ac.in

  [l]  Problems               Browse and search problems
  [c]  Contests               Browse and join contests
  [s]  Submit                  Submit current buffer
  [i]  Login                   Paste session cookie
  [w]  Who Am I                Check login status
  [o]  Open in Browser         Open OJ in browser
  [q]  Quit                    Close dashboard
```

## Problem Picker

Opened with `:Dmoj list` or `<leader>dl`.

Uses **telescope.nvim** for fuzzy searching across problem code, name, and group. Type to filter instantly.

| Key | Action |
|---|---|
| `Enter` | Open problem (description + solution file) |
| `Ctrl-o` / `o` | Open problem in browser |
| `Ctrl-r` | Refresh problem cache |
| `Esc` / `Ctrl-c` | Close picker |

If telescope is not installed, a fallback floating window picker is used instead.

## Contest Browser

Opened with `:Dmoj contests` or `[c]` from the dashboard.

Lists all **active**, **upcoming**, and **past** contests scraped from the `/contests/` page. Uses Telescope for fuzzy search (with fallback float).

**Contest Picker:**

| Key | Action |
|---|---|
| `Enter` | Open contest detail view |
| `Ctrl-o` / `o` | Open contest in browser |
| `Ctrl-r` | Refresh contest cache |
| `Esc` / `Ctrl-c` | Close picker |

Icons in the picker indicate status:
- `★` — currently participating
- `●` — active contest
- `◷` — upcoming contest
- `○` — past contest

**Contest Detail View:**

Selecting a contest opens a full-window detail view showing the contest title, join status, duration, time remaining, and description.

| Key | Action |
|---|---|
| `Enter` | Join the contest (if not joined) |
| `Backspace` | Leave the contest (if joined) |
| `o` | Open in browser |
| `q` | Close |

## Opening a Problem

`:Dmoj open <code>` (or `Enter` from the picker) will:

1. Fetch problem metadata (API with scraping fallback for private instances)
2. Open the problem statement in a left split (scraped from the problem page)
3. Create/open a solution file in the right window at `<storage_dir>/solutions/<code>.<ext>`
4. Set buffer-local variables so `:Dmoj submit` knows which problem and language to use

Solution files are pre-filled with a language-appropriate comment header:

```c
// Problem: Disc Collection
// https://dmoj.ca/problem/ds2
// Language: CPP17
// Time limit: 1.0s
// Memory limit: 256 MB
```

```python
# Problem: Trading
# https://oj-test.iiit.ac.in/problem/dsaa2q1
# Language: PY3
# Time limit: 2.0s
# Memory limit: 262144 KB
```

## Submitting

Run `:Dmoj submit` (or `<leader>ds`) from your solution buffer.

The plugin will:

1. Scrape the language integer ID from the submit page
2. POST your source code with your session cookie
3. Capture the submission ID from the redirect
4. Poll the submission page every 1.5s until judging completes
5. Display the verdict in a floating window with per-case breakdown

```
┌─ ✓ Accepted ──────────────────────────────┐
│                                            │
│   Accepted  |  10/10 testcases passed      │
│                                            │
│   Score: 100/100  (100%)                   │
│                                            │
│   Resources: 0.085s, 1.58 MB               │
│   Problem:   aplusb                        │
│                                            │
│   ──────────────────────────────────────   │
│                                            │
│   Execution Results                        │
│                                            │
│   ✓ ✓ ✓ ✓ ✓ ✓ ✓ ✓ ✓ ✓                     │
│                                            │
│   Test case #1    AC [0.007s, 1.20 MB]     │
│   Test case #2    AC [0.008s, 1.22 MB]     │
│   ...                                      │
│                                            │
│   ──────────────────────────────────────   │
│   [q] Close  [o] Open in browser           │
│                                            │
└────────────────────────────────────────────┘
```

For batched problems, cases are grouped under their batch:

```
│   Batch 1    [5.0/5.0]                     │
│     Case 1     AC [0.012s, 1.24 MB]        │
│     Case 2     AC [0.015s, 1.26 MB]        │
│   Batch 2    [5.0/5.0]                     │
│     Case 3     AC [0.031s, 2.34 MB]        │
│     ...                                    │
```

## Local Testing

Run `:Dmoj run` (or `<leader>dt`) from your solution buffer.

The plugin will:

1. Extract sample input/output from the problem description page
2. Compile (if needed) and run your solution against each sample
3. Show a results floating window comparing expected vs actual output

This runs entirely locally — no submission is made to the judge.

## File Structure

```
dmoj.nvim/
├── plugin/
│   └── dmoj.lua           # Auto-loaded, registers :Dmoj command
└── lua/dmoj/
    ├── init.lua            # setup(), command dispatch, keymaps
    ├── config.lua          # Configuration defaults
    ├── http.lua            # Async curl wrapper (vim.system)
    ├── auth.lua            # Cookie storage, login, CSRF extraction
    ├── api.lua             # DMOJ web scraper (problems, metadata)
    ├── ui.lua              # Floating windows, splits, spinners
    ├── dashboard.lua       # Home screen with ASCII art and menu
    ├── problems.lua        # Telescope picker + open problem workflow
    ├── description.lua     # HTML → plain text renderer
    ├── contests.lua        # Contest browser, detail view, join/leave
    ├── submit.lua          # Submission, polling, result display
    ├── submissions.lua     # Submission history list
    └── runner.lua          # Local compile+run against sample test cases
```

## Private / Organization DMOJ Instances

dmoj.nvim works with private/organization DMOJ instances out of the box. All data is fetched by scraping the web pages directly using cookie-based authentication:

- **Problem list**: scraped from `/problems/` HTML page (with pagination)
- **Problem metadata**: scraped from the individual problem page
- **Submission**: uses cookie-based form POST

No extra configuration needed — just set `base_url` to your instance.

## Troubleshooting

**"Cookie appears invalid" on login**
- Make sure you copy from **Request Headers** in the Network tab, not from Application → Cookies
- The session may have expired — log out and back in to the browser, then copy again
- If your OJ is on a restricted network (VPN, college WiFi), make sure Neovim is running on a machine on that network

**Problem list is empty**
- Run `:Dmoj login` first — most problems require authentication to see
- Run `:Dmoj refresh` to clear the cache and re-fetch

**Language not found on submit**
- Run `:Dmoj submit` and check the error — it will list available language names as parsed from the submit page
- Set `lang` in your config to one of those names, or use `:Dmoj submit <code> <lang>`

**Description shows "(Could not extract problem description)"**
- The HTML scraping patterns may not match your OJ's template if it's heavily customized
- Use `o` in the description buffer or `:Dmoj browser` to open the problem in your browser instead

**"API error: HTTP 404" on opening a problem**
- This is expected on organization-private instances — the plugin automatically falls back to scraping
- If the scraping fallback also fails, the instance may require a VPN or specific network access

**Submission times out / no verdict**
- The plugin polls up to 90 seconds (60 attempts x 1.5s). Very slow judges may exceed this.
- Use `:Dmoj result <id>` to manually check the result later
- The plugin scrapes the submission HTML page for results; if your DMOJ instance uses a heavily customized template, the scraping patterns may not match
