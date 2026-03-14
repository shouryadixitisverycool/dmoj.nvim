# dmoj.nvim

A Neovim plugin for solving [DMOJ](https://dmoj.ca) problems without leaving your editor. Browse problems, read statements, submit solutions, run local tests, and join contests — all from Neovim.

Works with [dmoj.ca](https://dmoj.ca) and any self-hosted DMOJ instance (e.g. a college OJ).

## Table of Contents

- [Features](#features)
- [Compatibility](#compatibility)
- [Gallery](#gallery)
- [Installation](#installation)
- [Authentication](#authentication)
- [Configuration](#configuration)
- [Commands](#commands)
- [Dashboard](#dashboard)
- [Problem Picker](#problem-picker)
- [Contest Browser](#contest-browser)
- [Opening a Problem](#opening-a-problem)
- [Submitting](#submitting)
- [Local Testing](#local-testing)
- [Security](#security)
- [Private / Organization DMOJ Instances](#private--organization-dmoj-instances)
- [File Structure](#file-structure)
- [Troubleshooting](#troubleshooting)

## Features

- **Dashboard** home screen with ASCII art and quick-access menu
- **Telescope-powered** fuzzy problem picker (with fallback for no-Telescope setups)
- **Problem descriptions** scraped and rendered inline — no browser needed
- **Submit** solutions directly from your buffer with live verdict polling
- **Per-case results** with time/memory breakdown, batched problem support
- **Local test runner** — compile and run against sample cases before submitting
- **Contest browser** — list active/upcoming/past contests, join and leave
- **Submission history** picker
- **Private/organization DMOJ instances** supported out of the box

## Compatibility

| Platform | Status |
|---|---|
| Linux | Fully supported |
| macOS | Fully supported |
| Windows | Not supported |

Requires **Neovim >= 0.9** and **curl** (pre-installed on macOS and most Linux distros).

## Gallery

**Dashboard**

![Dashboard](https://github.com/user-attachments/assets/placeholder-dashboard)

**Problem picker (Telescope)**

![Problem Picker](https://github.com/user-attachments/assets/placeholder-picker)

**Problem description + solution split**

![Problem Description](https://github.com/user-attachments/assets/placeholder-description)

**Submission verdict**

![Submission Verdict](https://github.com/user-attachments/assets/placeholder-verdict)

**Contest browser**

![Contest Browser](https://github.com/user-attachments/assets/placeholder-contests)

**Local test runner**

![Local Runner](https://github.com/user-attachments/assets/placeholder-runner)

> Screenshots are from dmoj.ca. Replace the placeholder image links above with actual screenshots once you've uploaded them to GitHub (drag-and-drop into any GitHub issue to get a link).

## Installation

### lazy.nvim

```lua
{
  "your-username/dmoj.nvim",
  lazy = false,
  dependencies = {
    "nvim-telescope/telescope.nvim", -- optional but strongly recommended
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

For optimal lazy-loading, only load the plugin eagerly when the launch arg matches:

```lua
{
  "your-username/dmoj.nvim",
  lazy = "dmoj.nvim" ~= vim.fn.argv(0, -1),
  dependencies = {
    "nvim-telescope/telescope.nvim",
  },
  opts = {
    lang = "CPP17",
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

### Manual (no plugin manager)

```lua
vim.opt.runtimepath:prepend("~/path/to/dmoj.nvim")
require("dmoj").setup({})
```

## Authentication

DMOJ doesn't expose a public submission API, so the plugin authenticates via your browser session cookie — the same approach used by [leetcode.nvim](https://github.com/kawre/leetcode.nvim).

**Steps:**

1. Log in to your DMOJ instance in your browser
2. Open DevTools (`F12`) → **Network** tab
3. Reload the page and click any request to your OJ domain
4. Go to **Request Headers** (not Response Headers)
5. Find the `Cookie:` line and copy its entire value
   - It looks like: `csrftoken=abc123; sessionid=xyz789`
6. In Neovim, run `:Dmoj login` and paste it

The cookie is stored at:
- **Linux**: `~/.local/share/nvim/dmoj/cookie.txt`
- **macOS**: `~/Library/Application Support/nvim/dmoj/cookie.txt`

The file is created with `600` permissions (readable only by you).

> **Note:** The cookie is tied to your browser session. If you log out in the browser or the session expires, run `:Dmoj login` again.

## Configuration

All options and their defaults:

```lua
require("dmoj").setup({
  -- Base URL of your DMOJ instance (default: "https://dmoj.ca")
  base_url = "https://dmoj.ca",

  -- Default language key for new solution files (default: "CPP17")
  -- Must match DMOJ's language keys (e.g. C, CPP17, PY3, JAVA, RUST, GO ...)
  lang = "CPP17",

  -- Directory to store cookies and solution files
  -- (default: vim.fn.stdpath("data") .. "/dmoj")
  storage_dir = vim.fn.stdpath("data") .. "/dmoj",

  -- Command to open URLs in your browser
  -- Auto-detected: "open" on macOS, "xdg-open" on Linux
  -- Override only if your system uses something different
  -- open_cmd = "xdg-open",

  -- CLI argument for direct-launch: `nvim dmoj.nvim` opens the dashboard
  -- Set to "" to disable
  arg = "dmoj.nvim",

  -- Keymaps (set any to false to disable)
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

| Language | Key | Local runner |
|---|---|---|
| C | `C` | `gcc` |
| C++ 03/11/14/17/20/23 | `CPP03` … `CPP23` | `g++` |
| Python 2 | `PY2` | `python2` (removed on macOS 12.3+) |
| Python 3 | `PY3` | `python3` |
| PyPy / PyPy 3 | `PYPY` / `PYPY3` | `pypy` / `pypy3` |
| Java 8/11/17/21 | `JAVA8` … `JAVA21` | `javac` + `java` |
| Rust | `RUST` | `rustc` |
| Go | `GO` | `go run` |
| Kotlin | `KOTLIN` | `kotlinc` + `java -jar` |
| Ruby | `RUBY` | `ruby` |
| Lua | `LUA` | `lua` |
| Perl | `PERL` | `perl` |
| PHP | `PHP` | `php` |
| Haskell | `HASK` | `ghc` |
| Mono (C#) | `MONO` | `mcs` + `mono` |
| Dart | `DART` | `dart run` |
| Scala | `SCALA` | `scalac` + `scala` |
| Swift | `SWIFT` | `swiftc` |

The local runner only requires the compiler/interpreter to be on your `PATH`. The judge on DMOJ uses its own toolchain, so local and remote language versions may differ.

## Commands

| Command | Description |
|---|---|
| `:Dmoj` or `:Dmoj menu` | Open the dashboard home screen |
| `:Dmoj list` | Browse problems with Telescope fuzzy picker |
| `:Dmoj open <code>` | Open a specific problem by its code |
| `:Dmoj contests` | Browse contests (active, upcoming, past) |
| `:Dmoj submit` | Submit the current buffer |
| `:Dmoj submit <code>` | Submit the current buffer to a specific problem |
| `:Dmoj run` | Run current buffer locally against sample test cases |
| `:Dmoj desc` | Show the description for the current problem |
| `:Dmoj desc <code>` | Show the description for any problem by code |
| `:Dmoj result <id>` | Fetch and display a specific submission result |
| `:Dmoj browser` | Open the current problem in your browser |
| `:Dmoj login` | Paste your session cookie to log in |
| `:Dmoj logout` | Delete the stored cookie |
| `:Dmoj whoami` | Check who you're currently logged in as |
| `:Dmoj refresh` | Clear the cached problem list |

## Dashboard

Opened with `:Dmoj menu` or `nvim dmoj.nvim`.
[image]
## Problem Picker

Opened with `:Dmoj list` or `<leader>dl`.
[image]

Uses **Telescope** for fuzzy searching across problem code, title, and group. Falls back to a floating window picker if Telescope is not installed.

| Key | Action |
|---|---|
| `Enter` | Open problem (description + solution file) |
| `Ctrl-o` / `o` | Open problem in browser |
| `Ctrl-r` | Refresh problem list cache |
| `Esc` / `Ctrl-c` | Close |

## Contest Browser

Opened with `:Dmoj contests` or `[c]` from the dashboard.
[image]

Lists all **active**, **upcoming**, and **past** contests. Uses Telescope for fuzzy search (with fallback float).

**Picker icons:**
- `★` — currently participating
- `●` — active
- `◷` — upcoming
- `○` — past

**Picker keys:**

| Key | Action |
|---|---|
| `Enter` | Open contest detail view |
| `Ctrl-o` / `o` | Open in browser |
| `Ctrl-r` | Refresh |

**Contest detail view** shows title, join status, duration, time remaining, and description.

| Key | Action |
|---|---|
| `Enter` | Join the contest |
| `Backspace` | Leave the contest |
| `o` | Open in browser |
| `q` | Back to dashboard |

## Opening a Problem

`:Dmoj open <code>` (or `Enter` from the picker) will:

1. Fetch problem metadata
2. Open the problem statement in a **left split** (scraped from the problem page)
3. Create or open a solution file at `<storage_dir>/solutions/<code>.<ext>`
4. Set buffer-local variables so `:Dmoj submit` and `:Dmoj run` know the problem and language

## Submitting

Run `:Dmoj submit` (or `<leader>ds`) from your solution buffer.

1. Detects the language integer ID from the submit page
2. POSTs your source code with your session cookie
3. Captures the submission ID from the redirect
4. Polls the submission page every 1.5s until judging completes
5. Displays the verdict in a floating window with per-case breakdown

[image]
Batched problems group cases under their batch header:
[image]
## Local Testing

Run `:Dmoj run` (or `<leader>dt`) from your solution buffer.

1. Extracts sample input/output from the problem description page
2. Compiles (if needed) and runs your solution against each sample
3. Shows a results window comparing expected vs actual output

Runs entirely locally — no submission is made to the judge.

## Security

- **Cookie file is created with `600` permissions** before any data is written, eliminating a brief window of world-readability.
- **No credential logging.** The cookie value is never written to any Neovim buffer or log.

## Private / Organization DMOJ Instances

dmoj.nvim works with private/organization DMOJ instances out of the box. All data is fetched by scraping web pages using cookie-based authentication — no API v2 dependency.

Just set `base_url` in your config:

```lua
opts = {
  base_url = "https://your-college-oj.example.com",
  lang = "C",
}
```

## File Structure

```
dmoj.nvim/
├── plugin/
│   └── dmoj.lua           # Auto-loaded entry point, registers :Dmoj
└── lua/dmoj/
    ├── init.lua            # setup(), command dispatch, keymaps
    ├── config.lua          # Configuration schema and defaults
    ├── http.lua            # Async curl wrapper (vim.system)
    ├── auth.lua            # Cookie storage, login, CSRF extraction
    ├── api.lua             # DMOJ web scraper (problems, metadata)
    ├── ui.lua              # Floating windows, splits, loading spinner
    ├── dashboard.lua       # Home screen
    ├── problems.lua        # Telescope picker + open problem workflow
    ├── description.lua     # HTML → plain text renderer
    ├── contests.lua        # Contest browser, detail view, join/leave
    ├── submit.lua          # Submission, polling, result display
    ├── submissions.lua     # Submission history list
    └── runner.lua          # Local compile+run against sample test cases
```

## Troubleshooting

**"Cookie appears invalid" or `:Dmoj whoami` returns nothing**
- Make sure you copy from **Request Headers** in the Network tab, not Application → Cookies
- The session may have expired — log out and back in to the browser, then copy the new cookie
- If your OJ is on a restricted network (VPN, college WiFi), Neovim must be running on a machine with access to that network

**Problem list is empty**
- Run `:Dmoj login` first — most OJs require authentication to list problems
- Run `:Dmoj refresh` to clear the cache and re-fetch

**Language not found on submit**
- The error message will list the available language names as parsed from the submit page
- Set `lang` in your config to one of those names

**Description shows "(Could not extract problem description)"**
- The HTML scraping patterns may not match your OJ's template version
- Use `o` from the description buffer or `:Dmoj browser` to open in your browser

**Submission times out / no verdict shown**
- The plugin polls for up to 90 seconds. Very slow judges may exceed this.
- Use `:Dmoj result <id>` to manually check the result after the fact

**"Cannot join: no CSRF token in cookie"**
- Run `:Dmoj login` to refresh your session cookie
