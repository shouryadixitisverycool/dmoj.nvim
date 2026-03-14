<div align="center">
    # ⚠️⚠️⚠️🚨🚨🚨 AI SLOP ALERT 🚨🚨🚨⚠️⚠️⚠️
    the following project is 100% written by claude and probably contains a fuck ton of security flaws and non-functioning code. This was made mostly for personal use and hasn't been tested on any device other than mine (it works on my machine bro). Proceed with caution, you have been warned.

<div align="center">

# dmoj.nvim

Solve [DMOJ] problems without leaving [Neovim]

</div>

<!-- demo video/gif here -->

## 📋 Table of Contents
- [✨ Features](#-features)
- [📬 Requirements](#-requirements)
- [📦 Installation](#-installation)
- [🔑 Authentication](#-authentication)
- [🛠️ Configuration](#️-configuration)
- [📋 Commands](#-commands-1)
- [🚀 Usage](#-usage)
- [🖼️ Gallery](#️-gallery)
- [🔒 Security](#-security)
- [❓ FAQ](#-faq)

## ✨ Features

- 📌 dashboard home screen for quick navigation
- 🔭 [Telescope]-powered fuzzy problem picker (with fallback for non-Telescope setups)
- 📄 problem descriptions rendered inline — no browser needed
- ⚡ submit solutions with live verdict polling and per-case results
- 🧪 local test runner — compile and run against sample cases before submitting
- 🏆 contest browser — list active/upcoming/past contests, join and leave
- 🏛️ works with [dmoj.ca] and any self-hosted DMOJ instance (college OJs, etc.)

## 📬 Requirements

- [Neovim] >= 0.9
- `curl` (pre-installed on macOS and most Linux distros)
- [telescope.nvim] _(optional, but strongly recommended)_

| Platform | Status |
|---|---|
| Linux | Fully supported |
| macOS | Fully supported |
| Windows | Not supported |

## 📦 Installation

**[lazy.nvim]**

```lua
{
  "your-username/dmoj.nvim",
  lazy = false,
  dependencies = {
    "nvim-telescope/telescope.nvim",
  },
  opts = {
    lang = "CPP17",
  },
}
```

For lazy-loading (only loads when launched as `nvim dmoj.nvim`):

```lua
{
  "your-username/dmoj.nvim",
  lazy = "dmoj.nvim" ~= vim.fn.argv(0, -1),
  dependencies = { "nvim-telescope/telescope.nvim" },
  opts = { lang = "CPP17" },
}
```

**Manual (no plugin manager)**

```lua
vim.opt.runtimepath:prepend("~/path/to/dmoj.nvim")
require("dmoj").setup({})
```

## 🔑 Authentication

DMOJ has no public submission API, so dmoj.nvim authenticates via your browser session cookie — the same approach used by [leetcode.nvim].

> [!WARNING]
> Copy the `Cookie` value from **Request Headers** in the Network tab, not from Application → Cookies or Response Headers.

**Steps:**
1. Log in to your DMOJ instance in your browser
2. Open DevTools (`F12`) → **Network** tab
3. Reload the page and click any request to the OJ domain
4. Under **Request Headers**, find the `Cookie:` line and copy its full value
   - It looks like: `csrftoken=abc123; sessionid=xyz789`
5. In Neovim, run `:Dmoj login` and paste it

Cookie stored at:
- **Linux:** `~/.local/share/nvim/dmoj/cookie.txt`
- **macOS:** `~/Library/Application Support/nvim/dmoj/cookie.txt`

File is created with `600` permissions (readable only by you).

> [!NOTE]
> The cookie is tied to your browser session. If you log out in the browser or the session expires, run `:Dmoj login` again.

## 🛠️ Configuration

```lua
require("dmoj").setup({
  base_url = "https://dmoj.ca",
  lang = "CPP17",
  storage_dir = vim.fn.stdpath("data") .. "/dmoj",
  -- open_cmd = "xdg-open",  -- auto-detected: "open" on macOS, "xdg-open" on Linux
  arg = "dmoj.nvim",
  keymaps = {
    list         = "<leader>dl",
    submit       = "<leader>ds",
    test         = "<leader>dt",
    desc         = "<leader>dd",
    open_browser = "<leader>do",
  },
})
```

<details>
  <summary>Available language keys</summary>

| Language | Key | Local runner |
|---|---|---|
| C | `C` | `gcc` |
| C++ 03/11/14/17/20/23 | `CPP03` … `CPP23` | `g++` |
| Python 2 | `PY2` | `python2` |
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

The local runner requires the compiler/interpreter to be on your `PATH`. The judge on DMOJ uses its own toolchain, so local and remote language versions may differ.

</details>

## 📋 Commands

| Command | Description |
|---|---|
| `:Dmoj` / `:Dmoj menu` | Open the dashboard |
| `:Dmoj list` | Browse problems (Telescope picker) |
| `:Dmoj open <code>` | Open a problem by code |
| `:Dmoj contests` | Browse contests |
| `:Dmoj submit` | Submit current buffer |
| `:Dmoj submit <code>` | Submit current buffer to a specific problem |
| `:Dmoj run` | Run locally against sample test cases |
| `:Dmoj desc [code]` | Show problem description |
| `:Dmoj result <id>` | Fetch a submission result by ID |
| `:Dmoj browser` | Open current problem in browser |
| `:Dmoj login` | Set session cookie |
| `:Dmoj logout` | Delete stored cookie |
| `:Dmoj whoami` | Check current login |
| `:Dmoj refresh` | Clear problem list cache |

## 🚀 Usage

Launch directly into the DMOJ dashboard:

```
nvim dmoj.nvim
```

Or from within Neovim: `:Dmoj`

**Opening a problem** — `:Dmoj open <code>` or `Enter` from picker:
1. Opens description in a left split
2. Creates/opens solution file at `<storage_dir>/solutions/<code>.<ext>`
3. Pre-fills a language-appropriate comment header

**Submitting** — `:Dmoj submit` or `<leader>ds`: polls judge every 1.5s, shows floating verdict with per-case breakdown.

**Local testing** — `:Dmoj run` or `<leader>dt`: compiles and runs against sample cases from the description. No submission made.

**Contest browser** — `:Dmoj contests` or `[c]` from dashboard:

| Icon | Meaning |
|---|---|
| `★` | Currently participating |
| `●` | Active |
| `◷` | Upcoming |
| `○` | Past |

From contest detail: `Enter` to join, `Backspace` to leave, `q` to go back.

**Private/organization DMOJ instances** — set `base_url` in config. All data is scraped via cookie auth; no API v2 dependency.

## 🖼️ Gallery

> Replace placeholder links by dragging screenshots into any GitHub issue to get upload URLs.

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

## 🔒 Security

- **No credential exposure in `ps aux`** — headers and form data are written to restricted temp files (`600`) passed to curl via `--header @file` / `--data @file`
- **Cookie file `600` from creation** — no world-readable window
- **HTTPS only** — no `-k` flag
- **No credential logging** — cookie never written to any buffer

## ❓ FAQ

**"Cookie appears invalid" or `:Dmoj whoami` returns nothing**
Log out and back in to the browser, copy the new `Cookie` from Request Headers, run `:Dmoj login`.

**Problem list is empty**
Run `:Dmoj login` first, then `:Dmoj refresh`.

**Language not found on submit**
The error lists available names from the submit page. Set `lang` in config to one of those.

**Description shows "(Could not extract problem description)"**
The HTML scraping patterns may not match your OJ's template version. Use `:Dmoj browser` to open in your browser instead.

**Submission times out / no verdict**
Plugin polls 90s max. Use `:Dmoj result <id>` to check manually.

**"Cannot join: no CSRF token in cookie"**
Run `:Dmoj login` to refresh your session cookie.

**Works with private/organization DMOJ instances?**
Yes — set `base_url` in config. All data is scraped via cookie auth, no API needed.

[dmoj.ca]: https://dmoj.ca
[dmoj.nvim]: https://github.com/your-username/dmoj.nvim
[Neovim]: https://github.com/neovim/neovim
[lazy.nvim]: https://github.com/folke/lazy.nvim
[telescope.nvim]: https://github.com/nvim-telescope/telescope.nvim
[leetcode.nvim]: https://github.com/kawre/leetcode.nvim
