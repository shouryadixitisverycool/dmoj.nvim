local M = {}

local config = require("dmoj.config")
local http = require("dmoj.http")
local auth = require("dmoj.auth")
local ui = require("dmoj.ui")

--- Convert LaTeX math to readable plaintext.
---@param tex string raw LaTeX
---@return string
local function latex_to_text(tex)
  local s = tex

  -- Strip text-style commands: \text{}, \mathrm{}, \mathit{}, etc.
  for _, cmd in ipairs({
    "text", "mathrm", "mathit", "mathbf", "mathbb", "mathcal",
    "textbf", "textit", "textrm", "operatorname",
  }) do
    s = s:gsub("\\" .. cmd .. "%s*{([^}]*)}", "%1")
  end

  -- Fractions: \frac{a}{b} -> (a)/(b)
  s = s:gsub("\\frac%s*{([^}]*)}{([^}]*)}", "(%1)/(%2)")

  -- Sqrt
  s = s:gsub("\\sqrt%s*%[([^%]]*)%]%s*{([^}]*)}", "%1-root(%2)")
  s = s:gsub("\\sqrt%s*{([^}]*)}", "sqrt(%1)")

  -- \left / \right delimiters (process before shorter commands)
  s = s:gsub("\\left%s*\\lfloor", "floor(")
  s = s:gsub("\\right%s*\\rfloor", ")")
  s = s:gsub("\\left%s*\\lceil", "ceil(")
  s = s:gsub("\\right%s*\\rceil", ")")
  s = s:gsub("\\left%s*([%(%)%[%]{|}])", "%1")
  s = s:gsub("\\right%s*([%(%)%[%]{|}])", "%1")
  s = s:gsub("\\left", "")
  s = s:gsub("\\right", "")

  -- Floor/ceil without \left\right
  s = s:gsub("\\lfloor", "floor(")
  s = s:gsub("\\rfloor", ")")
  s = s:gsub("\\lceil", "ceil(")
  s = s:gsub("\\rceil", ")")
  s = s:gsub("\\lvert", "|")
  s = s:gsub("\\rvert", "|")

  -- Multi-character arrows and relations (longest first)
  s = s:gsub("\\Rightarrow", "=>")
  s = s:gsub("\\Leftarrow", "<=")
  s = s:gsub("\\rightarrow", "->")
  s = s:gsub("\\leftarrow", "<-")
  s = s:gsub("\\longrightarrow", "-->")
  s = s:gsub("\\longleftarrow", "<--")
  s = s:gsub("\\leftrightarrow", "<->")

  -- Relations (longer variants first)
  s = s:gsub("\\leq", "<=")
  s = s:gsub("\\geq", ">=")
  s = s:gsub("\\neq", "!=")
  s = s:gsub("\\le([^%a])", "<=%1")
  s = s:gsub("\\le$", "<=")
  s = s:gsub("\\ge([^%a])", ">=%1")
  s = s:gsub("\\ge$", ">=")
  s = s:gsub("\\ne([^%a])", "!=%1")
  s = s:gsub("\\ne$", "!=")
  s = s:gsub("\\approx", "~=")
  s = s:gsub("\\equiv", "===")
  s = s:gsub("\\sim", "~")
  s = s:gsub("\\subseteq", "c=")
  s = s:gsub("\\subset", "c")

  -- Operators
  s = s:gsub("\\times", "*")
  s = s:gsub("\\cdot", "*")
  s = s:gsub("\\div", "/")
  s = s:gsub("\\pm", "+-")
  s = s:gsub("\\mp", "-+")
  s = s:gsub("\\oplus", "xor")
  s = s:gsub("\\land", "AND")
  s = s:gsub("\\lor", "OR")
  s = s:gsub("\\neg", "NOT")
  s = s:gsub("\\bmod", " mod ")
  s = s:gsub("\\pmod", " mod ")
  s = s:gsub("\\mod", " mod ")

  -- Dots
  s = s:gsub("\\ldots", "...")
  s = s:gsub("\\cdots", "...")
  s = s:gsub("\\vdots", "...")
  s = s:gsub("\\dots", "...")

  -- Common functions (handled as-is since they're readable)
  for _, fn in ipairs({ "log", "ln", "lg", "sin", "cos", "tan", "min", "max", "gcd", "lcm" }) do
    s = s:gsub("\\" .. fn, fn)
  end

  -- Special values
  s = s:gsub("\\infty", "inf")
  s = s:gsub("\\emptyset", "{}")
  s = s:gsub("\\varnothing", "{}")

  -- Arrows and set notation
  s = s:gsub("\\to([^%a])", "->%1")
  s = s:gsub("\\to$", "->")
  s = s:gsub("\\gets", "<-")
  s = s:gsub("\\in([^%a])", " in %1")
  s = s:gsub("\\in$", " in")
  s = s:gsub("\\notin", " not in ")
  s = s:gsub("\\forall", "for all ")
  s = s:gsub("\\exists", "exists ")
  s = s:gsub("\\cup", "U")
  s = s:gsub("\\cap", "^")

  -- Summation / product
  s = s:gsub("\\sum", "sum")
  s = s:gsub("\\prod", "prod")

  -- Greek letters
  local greeks = {
    "alpha", "beta", "gamma", "delta", "epsilon", "varepsilon",
    "zeta", "eta", "theta", "iota", "kappa", "lambda",
    "mu", "nu", "xi", "pi", "rho", "sigma", "tau",
    "upsilon", "phi", "varphi", "chi", "psi", "omega",
    "Gamma", "Delta", "Theta", "Lambda", "Xi", "Pi",
    "Sigma", "Phi", "Psi", "Omega",
  }
  for _, g in ipairs(greeks) do
    s = s:gsub("\\" .. g, g)
  end

  -- Superscript/subscript with braces
  s = s:gsub("%^{([^}]*)}", "^%1")
  s = s:gsub("_{([^}]*)}", "_%1")

  -- Spacing commands
  s = s:gsub("\\[,;:!]", " ")
  s = s:gsub("\\quad", "  ")
  s = s:gsub("\\qquad", "    ")
  s = s:gsub("\\%%", "%%")
  s = s:gsub("\\&", "&")
  s = s:gsub("\\\\", " ")
  s = s:gsub("\\%s", " ")

  -- Strip any remaining \command
  s = s:gsub("\\(%a+)", "%1")

  -- Strip grouping braces
  s = s:gsub("{", "")
  s = s:gsub("}", "")

  -- Collapse whitespace
  s = s:gsub("  +", " ")
  s = vim.trim(s)

  return s
end

--- Convert basic HTML to plain text lines for display in Neovim.
--- Handles common tags found in DMOJ problem descriptions.
---@param html string raw HTML
---@return string[]
local function html_to_lines(html)
  local text = html

  -- Remove style blocks
  text = text:gsub("<style.->.-</style>", "")

  -- Handle MathJax <script type="math/tex"> blocks BEFORE removing scripts
  text = text:gsub('<script%s+type="math/tex;%s*mode=display">(.-)</script>', function(tex)
    return "\n" .. latex_to_text(tex) .. "\n"
  end)
  text = text:gsub('<script%s+type="math/tex">(.-)</script>', function(tex)
    return latex_to_text(tex)
  end)

  -- Remove remaining script blocks
  text = text:gsub("<script.->.-</script>", "")

  -- Handle MathJax preview spans
  text = text:gsub('<span class="MathJax_Preview">(.-)</span>', function(content)
    local clean = content:gsub("<[^>]+>", "")
    clean = vim.trim(clean)
    if clean ~= "" then return clean end
    return ""
  end)
  -- Strip rendered MathJax containers (SVG etc.)
  text = text:gsub('<span[^>]*class="[^"]*MathJax[^"]*"[^>]*>.-</span>', "")
  text = text:gsub('<span[^>]*class="[^"]*MathJax_SVG[^"]*"[^>]*>.-</span>', "")

  -- Handle math-tex spans: <span class="math-tex">\(LATEX\)</span>
  text = text:gsub('<span[^>]*class="[^"]*math%-tex[^"]*"[^>]*>(.-)</span>', function(content)
    content = content:gsub("<[^>]+>", "")
    local tex = content:match("^\\%((.-)\\%)$") or content:match("^\\%[(.-)\\%]$") or content
    return latex_to_text(tex)
  end)

  -- Headings
  text = text:gsub("<h(%d)[^>]*>(.-)</h%1>", function(level, content)
    content = content:gsub("<[^>]+>", "")
    local prefix = string.rep("#", tonumber(level) or 1) .. " "
    return "\n" .. prefix .. content .. "\n"
  end)

  -- Paragraphs and divs
  text = text:gsub("<p[^>]*>", "\n")
  text = text:gsub("</p>", "\n")
  text = text:gsub("<div[^>]*>", "\n")
  text = text:gsub("</div>", "\n")

  -- Line breaks
  text = text:gsub("<br%s*/?>", "\n")

  -- Bold / italic (handle tags with attributes like <strong class="...">)
  text = text:gsub("<b[^>]*>(.-)</b>", "%1")
  text = text:gsub("<strong[^>]*>(.-)</strong>", "%1")
  text = text:gsub("<i[^>]*>(.-)</i>", "%1")
  text = text:gsub("<em[^>]*>(.-)</em>", "%1")

  -- Code blocks: <pre><code>...</code></pre> (handle attributes on both tags)
  -- Also handle <pre> without <code>
  text = text:gsub("<pre[^>]*>%s*<code[^>]*>(.-)</code>%s*</pre>", function(code)
    code = code:gsub("<[^>]+>", "") -- strip any inner HTML tags
    code = code:gsub("&lt;", "<")
    code = code:gsub("&gt;", ">")
    code = code:gsub("&amp;", "&")
    code = code:gsub("&quot;", '"')
    code = code:gsub("&#39;", "'")
    code = code:gsub("&nbsp;", " ")
    code = code:gsub("^%s*\n", ""):gsub("\n%s*$", "")
    
    local lines = {}
    for line in vim.gsplit(code, "\n") do
      table.insert(lines, "    " .. line)
    end
    return "\n<dmoj-code>\n" .. table.concat(lines, "\n") .. "\n</dmoj-code>\n"
  end)
  -- <pre> without <code>
  text = text:gsub("<pre[^>]*>(.-)</pre>", function(code)
    code = code:gsub("<[^>]+>", "") -- strip any inner HTML tags
    code = code:gsub("&lt;", "<")
    code = code:gsub("&gt;", ">")
    code = code:gsub("&amp;", "&")
    code = code:gsub("&quot;", '"')
    code = code:gsub("&#39;", "'")
    code = code:gsub("&nbsp;", " ")
    code = code:gsub("^%s*\n", ""):gsub("\n%s*$", "")
    
    local lines = {}
    for line in vim.gsplit(code, "\n") do
      table.insert(lines, "    " .. line)
    end
    return "\n<dmoj-code>\n" .. table.concat(lines, "\n") .. "\n</dmoj-code>\n"
  end)

  -- Inline code (handle <code> with attributes)
  text = text:gsub("<code[^>]*>(.-)</code>", function(code)
    code = code:gsub("<[^>]+>", "")
    code = code:gsub("&lt;", "<")
    code = code:gsub("&gt;", ">")
    code = code:gsub("&amp;", "&")
    return "`" .. code .. "`"
  end)

  -- Lists
  text = text:gsub("<ul[^>]*>", "\n")
  text = text:gsub("</ul>", "\n")
  text = text:gsub("<ol[^>]*>", "\n")
  text = text:gsub("</ol>", "\n")
  text = text:gsub("<li[^>]*>(.-)</li>", "  * %1\n")

  -- Links
  text = text:gsub('<a[^>]*href="([^"]*)"[^>]*>(.-)</a>', "%2 (%1)")

  -- Horizontal rules
  text = text:gsub("<hr[^>]*/?>", "\n" .. string.rep("─", 60) .. "\n")

  -- Tables: proper conversion with dynamic column widths
  text = text:gsub("<table[^>]*>(.-)</table>", function(tbl)
    -- Helper: strip HTML tags and decode entities from cell content
    local function clean_cell(cell_html)
      local c = cell_html
      c = c:gsub("<[^>]+>", "")
      c = c:gsub("&lt;", "<")
      c = c:gsub("&gt;", ">")
      c = c:gsub("&amp;", "&")
      c = c:gsub("&quot;", '"')
      c = c:gsub("&#39;", "'")
      c = c:gsub("&nbsp;", " ")
      c = c:gsub("%s+", " ")
      return vim.trim(c)
    end

    -- Parse all rows
    local rows = {}
    local is_header = {} -- track which rows are header rows
    for row_html in tbl:gmatch("<tr[^>]*>(.-)</tr>") do
      local cells = {}
      local header_row = false
      -- Extract th cells
      for cell in row_html:gmatch("<th[^>]*>(.-)</th>") do
        table.insert(cells, clean_cell(cell))
        header_row = true
      end
      -- Extract td cells
      for cell in row_html:gmatch("<td[^>]*>(.-)</td>") do
        table.insert(cells, clean_cell(cell))
      end
      if #cells > 0 then
        table.insert(rows, cells)
        table.insert(is_header, header_row)
      end
    end

    if #rows == 0 then return "\n" end

    -- Calculate column widths
    local num_cols = 0
    for _, row in ipairs(rows) do
      if #row > num_cols then num_cols = #row end
    end
    local col_widths = {}
    for c = 1, num_cols do
      col_widths[c] = 0
      for _, row in ipairs(rows) do
        local cell = row[c] or ""
        if #cell > col_widths[c] then
          col_widths[c] = #cell
        end
      end
      -- Minimum width of 3, maximum of 30
      col_widths[c] = math.max(3, math.min(col_widths[c], 30))
    end

    -- Build table output
    local out = "\n"
    -- Build separator line
    local sep_parts = {}
    for c = 1, num_cols do
      table.insert(sep_parts, string.rep("-", col_widths[c] + 2))
    end
    local sep_line = "|" .. table.concat(sep_parts, "|") .. "|"

    for r, row in ipairs(rows) do
      local parts = {}
      for c = 1, num_cols do
        local cell = row[c] or ""
        if #cell > col_widths[c] then
          cell = cell:sub(1, col_widths[c])
        end
        table.insert(parts, " " .. cell .. string.rep(" ", col_widths[c] - #cell) .. " ")
      end
      out = out .. "|" .. table.concat(parts, "|") .. "|\n"
      -- Add separator after header row
      if is_header[r] then
        out = out .. sep_line .. "\n"
      end
    end

    -- If no header row was found, add separator after first row
    if not is_header[1] and #rows > 0 then
      -- Insert separator after first line
      local first_nl = out:find("\n", 2)
      if first_nl then
        out = out:sub(1, first_nl) .. sep_line .. "\n" .. out:sub(first_nl + 1)
      end
    end

    return out .. "\n"
  end)

  -- Images: show alt text directly (most are math on DMOJ)
  text = text:gsub('<img[^>]*alt="([^"]*)"[^>]*/?>',  function(alt)
    if alt == "" then return "" end
    return latex_to_text(alt)
  end)
  text = text:gsub("<img[^>]*/?>", "")

  -- Superscript / subscript
  text = text:gsub("<sup>(.-)</sup>", "^%1")
  text = text:gsub("<sub>(.-)</sub>", "_%1")

  -- Strip remaining tags
  text = text:gsub("<[^>]+>", "")

  -- Handle DMOJ tilde-delimited inline math: ~expr~
  text = text:gsub("~([^~\n]+)~", function(content)
    return latex_to_text(content)
  end)

  -- Handle \( \) and \[ \] LaTeX delimiters in text
  text = text:gsub("\\%((.-)\\%)", function(tex) return latex_to_text(tex) end)
  text = text:gsub("\\%[(.-)\\%]", function(tex) return "\n" .. latex_to_text(tex) .. "\n" end)

  -- Unescape common HTML entities
  text = text:gsub("&lt;", "<")
  text = text:gsub("&gt;", ">")
  text = text:gsub("&amp;", "&")
  text = text:gsub("&quot;", '"')
  text = text:gsub("&#39;", "'")
  text = text:gsub("&nbsp;", " ")
  text = text:gsub("&ndash;", "–")
  text = text:gsub("&mdash;", "—")
  text = text:gsub("&le;", "<=")
  text = text:gsub("&ge;", ">=")
  text = text:gsub("&ne;", "!=")
  text = text:gsub("&times;", "*")
  text = text:gsub("&#(%d+);", function(n)
    local num = tonumber(n)
    if num and num < 128 then
      return string.char(num)
    end
    return ""
  end)

  -- Collapse multiple blank lines
  text = text:gsub("\n\n\n+", "\n\n")
  text = vim.trim(text)

  -- Split into lines
  local lines = {}
  local in_code = false
  for line in text:gmatch("([^\n]*)\n?") do
    if line == "<dmoj-code>" then
      in_code = true
      table.insert(lines, "")
    elseif line == "</dmoj-code>" then
      in_code = false
      table.insert(lines, "")
    else
      -- Strip heading markers, but keep track of them for highlighting
      local h_line, matches = line:gsub("<dmoj%-heading>(.-)</dmoj%-heading>", "%1")
      if matches > 0 then
        table.insert(lines, h_line)
      else
        table.insert(lines, line)
      end
    end
  end

  return lines
end

--- Apply syntax highlighting to the description buffer.
---@param bufnr number
---@param header_end number line index (0-based) where header ends
local function apply_highlights(bufnr, header_end)
  local ns = vim.api.nvim_create_namespace("dmoj_description")
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)

  local buf_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  for i, line in ipairs(buf_lines) do
    local row = i - 1

    -- URL is row 1
    if row == 1 then
      vim.api.nvim_buf_add_highlight(bufnr, ns, "Comment", row, 0, -1)
    -- Title is row 4
    elseif row == 4 then
      vim.api.nvim_buf_add_highlight(bufnr, ns, "Title", row, 0, -1)
    -- Stats is row 5
    elseif row == 5 then
      vim.api.nvim_buf_add_highlight(bufnr, ns, "Special", row, 0, -1)
      
    -- Custom headings (Starts with Icon then space then text, matched via our prefix)
    -- " 💡 Example 1:" or "   Constraints:" etc.
    elseif line:match("^ %s*💡") or line:match("^ %s*") or line:match("^ %s*") or line:match("^ %s*📝") then
      vim.api.nvim_buf_add_highlight(bufnr, ns, "@markup.heading", row, 0, -1)
      
    -- Indented code blocks (4 spaces)
    elseif line:match("^    ") and row > header_end then
      vim.api.nvim_buf_add_highlight(bufnr, ns, "String", row, 0, -1)
      
    -- Tables (starts with |)
    elseif line:match("^%s*|") and row > header_end then
      -- Highlight the table separators and text like Leetcode
      -- For simplicity, let's just highlight the whole table row in a nice color
      -- or just the pipes
      local pipe_s = 0
      while true do
        local next_pipe = line:find("|", pipe_s + 1, true)
        if not next_pipe then break end
        vim.api.nvim_buf_add_highlight(bufnr, ns, "FloatBorder", row, next_pipe - 1, next_pipe)
        pipe_s = next_pipe
      end
      -- If it's a separator row like |---|---|
      if line:match("|%-") then
        vim.api.nvim_buf_add_highlight(bufnr, ns, "FloatBorder", row, 0, -1)
      else
        -- Highlight the text inside the row
        vim.api.nvim_buf_add_highlight(bufnr, ns, "Identifier", row, 0, -1)
        -- Redo pipes over it so they stay border colored
        pipe_s = 0
        while true do
          local next_pipe = line:find("|", pipe_s + 1, true)
          if not next_pipe then break end
          vim.api.nvim_buf_add_highlight(bufnr, ns, "FloatBorder", row, next_pipe - 1, next_pipe)
          pipe_s = next_pipe
        end
      end

    -- Bullet points
    elseif line:match("^%s+%*%s") then
      local s, e = line:find("%*")
      if s then
        vim.api.nvim_buf_add_highlight(bufnr, ns, "Special", row, s - 1, e)
      end

    -- Footer line
    elseif line:find("%[o%]") and line:find("%[q%]") then
      vim.api.nvim_buf_add_highlight(bufnr, ns, "Comment", row, 0, -1)
    end
  end
end

--- Fetch the problem description HTML from the website and display in a split.
---@param code string problem code
---@param meta table problem metadata
function M.show(code, meta)
  local cancel = ui.loading("Fetching description...")

  local headers = auth.auth_headers() or {}
  local url = config.options.base_url .. "/problem/" .. code

  http.get(url, { headers = headers, follow_redirects = true, timeout = 30 }, function(resp)
    cancel()

    if resp.status ~= 200 then
      ui.notify("Failed to fetch problem page: HTTP " .. resp.status, vim.log.levels.ERROR)
      return
    end

    -- Extract the problem description from the HTML
    local desc_html = resp.body:match('<div[^>]*class="[^"]*content%-description[^"]*"[^>]*>(.-)</div>%s*</div>')
    if not desc_html then
      desc_html = resp.body:match('<div[^>]*id="problem%-markdown[^"]*"[^>]*>(.-)</div>')
    end
    if not desc_html then
      desc_html = resp.body:match('<div[^>]*class="problem%-content[^"]*"[^>]*>(.-)<div[^>]*class="problem%-info')
    end
    if not desc_html then
      desc_html = resp.body:match('<div[^>]*id="content%-body"[^>]*>(.-)<div[^>]*id="comment')
    end

    -- Calculate split width for centering
    local split_width = math.floor(vim.o.columns * 0.4)
    local text_width = split_width - 4
    local thin_sep = string.rep("─", text_width)

    -- Center text within split
    local function center(s)
      local display_width = vim.fn.strdisplaywidth(s)
      local pad = math.max(0, math.floor((text_width - display_width) / 2))
      return string.rep(" ", pad) .. s
    end

    -- Build header
    local lines = {}
    local title = meta.name or code

    table.insert(lines, "")
    table.insert(lines, center(url))
    table.insert(lines, "")
    table.insert(lines, "")
    table.insert(lines, center(title))

    -- One-line stats
    local stats = {}
    table.insert(stats, tostring(meta.points or 0) .. " pts")
    table.insert(stats, tostring(meta.time_limit or "?") .. "s")
    table.insert(stats, tostring(math.floor((meta.memory_limit or 0) / 1024)) .. " MB")
    if meta.group and meta.group ~= "" then
      table.insert(stats, meta.group)
    end
    local stats_line = table.concat(stats, " | ")
    table.insert(lines, center(stats_line))
    table.insert(lines, "")

    local header_end = #lines

    table.insert(lines, "")

    -- Parse and append description
    if desc_html then
      local desc_lines = html_to_lines(desc_html)
      vim.list_extend(lines, desc_lines)
    else
      table.insert(lines, "  (Could not extract problem description.)")
      table.insert(lines, "  Open in browser: " .. url)
    end

    table.insert(lines, "")
    table.insert(lines, thin_sep)
    table.insert(lines, " [o] Open in browser  [q] Close")

    local bufnr = ui.create_buf("dmoj://problem/" .. code, lines, { filetype = "markdown" })
    ui.open_split_left(bufnr, { width = split_width })

    -- Apply custom highlights on top of markdown
    apply_highlights(bufnr, header_end)

    -- Keymaps for description buffer
    vim.keymap.set("n", "o", function()
      vim.fn.jobstart({ config.options.open_cmd, url }, { detach = true })
    end, { buffer = bufnr, nowait = true, silent = true })

    vim.keymap.set("n", "q", function()
      local wins = vim.fn.win_findbuf(bufnr)
      for _, w in ipairs(wins) do
        if vim.api.nvim_win_is_valid(w) then
          vim.api.nvim_win_close(w, true)
        end
      end
    end, { buffer = bufnr, nowait = true, silent = true })
  end)
end

return M
