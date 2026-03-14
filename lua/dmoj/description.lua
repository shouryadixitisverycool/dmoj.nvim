local M = {}

local config = require("dmoj.config")
local http = require("dmoj.http")
local auth = require("dmoj.auth")
local ui = require("dmoj.ui")

--- Sentinel bytes used by latex_to_text() to protect literal < and >
--- from the HTML tag-stripping pass.  Restored to real characters by
--- html_to_lines() after all tags have been removed.
local LT = "\x01"  -- placeholder for <
local GT = "\x02"  -- placeholder for >

--- Convert LaTeX math to readable plaintext.
--- Uses sentinel bytes (LT/GT) for < and > so that a later
--- gsub("<[^>]+>","") pass does not consume maths expressions.
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
  -- Use LT/GT sentinels so the HTML tag stripper does not eat these.
  s = s:gsub("\\Rightarrow", "=" .. GT)
  s = s:gsub("\\Leftarrow", LT .. "=")
  s = s:gsub("\\rightarrow", "-" .. GT)
  s = s:gsub("\\leftarrow", LT .. "-")
  s = s:gsub("\\longrightarrow", "--" .. GT)
  s = s:gsub("\\longleftarrow", LT .. "--")
  s = s:gsub("\\leftrightarrow", LT .. "-" .. GT)

  -- Relations (longer variants first)
  s = s:gsub("\\leq", LT .. "=")
  s = s:gsub("\\geq", GT .. "=")
  s = s:gsub("\\neq", "!=")
  s = s:gsub("\\le([^%a])", LT .. "=%1")
  s = s:gsub("\\le$", LT .. "=")
  s = s:gsub("\\ge([^%a])", GT .. "=%1")
  s = s:gsub("\\ge$", GT .. "=")
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
  s = s:gsub("\\to([^%a])", "-" .. GT .. "%1")
  s = s:gsub("\\to$", "-" .. GT)
  s = s:gsub("\\gets", LT .. "-")
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

local function extract_inline_hls(text, row)
  local hls = {}
  local out = ""
  
  local i = 1
  local stack = {}
  
  local markers = {
    ["__B__"] = "@markup.strong",
    ["__/B__"] = "@markup.strong",
    ["__C__"] = "@markup.raw",
    ["__/C__"] = "@markup.raw",
  }
  
  while i <= #text do
    local s, e = text:find("__[^_]+__", i)
    if not s then
      out = out .. text:sub(i)
      break
    end
    
    local marker = text:sub(s, e)
    if markers[marker] then
      out = out .. text:sub(i, s - 1)
      if marker:sub(3,3) == "/" then
        -- end marker
        for j = #stack, 1, -1 do
          if stack[j].marker:sub(3) == marker:sub(4) then
            local start_col = stack[j].col
            table.insert(hls, { hl = markers[marker], row = row, col_start = start_col, col_end = #out })
            table.remove(stack, j)
            break
          end
        end
      else
        -- start marker
        table.insert(stack, { marker = marker, col = #out })
      end
    else
      -- not a valid marker, keep it
      out = out .. text:sub(i, e)
    end
    i = e + 1
  end
  return out, hls
end

--- Convert basic HTML to plain text lines for display in Neovim.
--- Handles common tags found in DMOJ problem descriptions.
---@param html string raw HTML
---@return string[], table[]
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

  -- Remove copy-clipboard buttons (DMOJ adds these before sample output <pre> blocks)
  -- The data-clipboard-text attribute can contain newlines, so use [^<]* for span
  -- content and match the whole div structure explicitly.
  text = text:gsub('<div class="copy%-clipboard">%s*<span[^>]*>.-</span>%s*</div>', "")

  -- Strip MathJax preview spans (we already process the <script type="math/tex"> blocks)
  text = text:gsub('<span class="MathJax_Preview">(.-)</span>', "")
  -- Strip rendered MathJax containers (SVG etc.)
  text = text:gsub('<span[^>]*class="[^"]*MathJax[^"]*"[^>]*>.-</span>', "")
  text = text:gsub('<span[^>]*class="[^"]*MathJax_SVG[^"]*"[^>]*>.-</span>', "")

  -- Handle inline-math spans FIRST (before tex-text stripping)
  -- DMOJ structure: <span class="inline-math"><img alt="LATEX" ...><span class="tex-text" style="display:none;">~LATEX~</span></span>
  -- Use iterative approach to handle nested spans reliably
  local function process_inline_math(t)
    local result = t
    local changed = true
    while changed do
      changed = false
      local start_pat = '<span[^>]*class="[^"]*inline%-math[^"]*"[^>]*>'
      local s, e = result:find(start_pat)
      if s then
        -- Find balanced closing </span> from position e+1
        local depth = 1
        local pos = e + 1
        local end_pos = nil
        while depth > 0 and pos <= #result do
          local open_s, open_e = result:find("<span[^>]*>", pos)
          local close_s, close_e = result:find("</span>", pos)
          if not close_s then break end
          if open_s and open_s < close_s then
            depth = depth + 1
            pos = open_e + 1
          else
            depth = depth - 1
            if depth == 0 then
              end_pos = close_e
            end
            pos = close_e + 1
          end
        end
        if end_pos then
          local inner = result:sub(e + 1, end_pos - #("</span>"))
          local alt = inner:match('<img[^>]*alt="([^"]*)"')
          local replacement = ""
          if alt and alt ~= "" then
            replacement = latex_to_text(alt)
          else
            -- Fallback: try to get content from tex-text span or tilde-delimited math
            local tex_content = inner:match('class="[^"]*tex%-text[^"]*"[^>]*>~?([^<]*)~?<')
            if tex_content and tex_content ~= "" then
              tex_content = tex_content:gsub("^~", ""):gsub("~$", "")
              replacement = latex_to_text(tex_content)
            else
              -- Last resort: strip all tags and use remaining text
              local plain = inner:gsub("<[^>]+>", " ")
              plain = vim.trim(plain:gsub("%s+", " "))
              if plain ~= "" then
                replacement = plain
              end
            end
          end
          result = result:sub(1, s - 1) .. replacement .. result:sub(end_pos + 1)
          changed = true
        end
      end
    end
    return result
  end
  text = process_inline_math(text)

  -- Strip hidden tex-text fallback spans that weren't inside inline-math
  text = text:gsub('<span[^>]*class="[^"]*tex%-text[^"]*"[^>]*>.-</span>', "")

  -- Handle math-tex spans: <span class="math-tex">\(LATEX\)</span>
  text = text:gsub('<span[^>]*class="[^"]*math%-tex[^"]*"[^>]*>(.-)</span>', function(content)
    content = content:gsub("<[^>]+>", "")
    local tex = content:match("^\\%((.-)\\%)$") or content:match("^\\%[(.-)\\%]$") or content
    return latex_to_text(tex)
  end)

  -- Headings: render as plain text with icon prefix for highlighting
  -- Process each heading level separately to avoid backreference issues
  for level = 1, 6 do
    local tag_open = "<h" .. level .. "[^>]*>"
    local tag_close = "</h" .. level .. ">"
    text = text:gsub(tag_open .. "(.-)" .. tag_close, function(content)
      content = content:gsub("<[^>]+>", "")
      content = vim.trim(content)
      return "\n__H__" .. content .. "__/H__\n"
    end)
  end

  -- Paragraphs and divs
  text = text:gsub("<p[^>]*>", "\n")
  text = text:gsub("</p>", "\n")
  text = text:gsub("<div[^>]*>", "\n")
  text = text:gsub("</div>", "\n")

  -- Line breaks
  text = text:gsub("<br%s*/?>", "\n")

  -- Bold / italic (handle tags with attributes like <strong class="...">)
  text = text:gsub("<b[^>]*>(.-)</b>", "__B__%1__/B__")
  text = text:gsub("<strong[^>]*>(.-)</strong>", "__B__%1__/B__")
  text = text:gsub("<i[^>]*>(.-)</i>", "%1")
  text = text:gsub("<em[^>]*>(.-)</em>", "%1")

  -- Code blocks: <pre><code>...</code></pre> (handle attributes on both tags)
  -- Also handle <pre> without <code>
  text = text:gsub("<pre[^>]*>%s*<code[^>]*>(.-)</code>%s*</pre>", function(code)
    code = code:gsub("<[^>]+>", "") -- strip any inner HTML tags
    code = code:gsub("&lt;", LT)
    code = code:gsub("&gt;", GT)
    code = code:gsub("&amp;", "&")
    code = code:gsub("&quot;", '"')
    code = code:gsub("&#39;", "'")
    code = code:gsub("&nbsp;", " ")
    code = code:gsub("^%s*\n", ""):gsub("\n%s*$", "")
    
    local lines = {}
    for line in vim.gsplit(code, "\n") do
      table.insert(lines, "    " .. line)
    end
    return "\n__CODE__\n" .. table.concat(lines, "\n") .. "\n__/CODE__\n"
  end)
  -- <pre> without <code>
  text = text:gsub("<pre[^>]*>(.-)</pre>", function(code)
    code = code:gsub("<[^>]+>", "") -- strip any inner HTML tags
    code = code:gsub("&lt;", LT)
    code = code:gsub("&gt;", GT)
    code = code:gsub("&amp;", "&")
    code = code:gsub("&quot;", '"')
    code = code:gsub("&#39;", "'")
    code = code:gsub("&nbsp;", " ")
    code = code:gsub("^%s*\n", ""):gsub("\n%s*$", "")
    
    local lines = {}
    for line in vim.gsplit(code, "\n") do
      table.insert(lines, "    " .. line)
    end
    return "\n__CODE__\n" .. table.concat(lines, "\n") .. "\n__/CODE__\n"
  end)

  -- Inline code (handle <code> with attributes)
  -- Multi-line <code> blocks get treated as code blocks (indented + highlighted)
  text = text:gsub("<code[^>]*>(.-)</code>", function(code)
    code = code:gsub("<[^>]+>", "")
    code = code:gsub("&lt;", LT)
    code = code:gsub("&gt;", GT)
    code = code:gsub("&amp;", "&")
    if code:find("\n") then
      -- Multi-line: treat as a code block
      code = code:gsub("^%s*\n", ""):gsub("\n%s*$", "")
      local lines = {}
      for line in vim.gsplit(code, "\n") do
        table.insert(lines, "    " .. line)
      end
      return "\n__CODE__\n" .. table.concat(lines, "\n") .. "\n__/CODE__\n"
    end
    return "__C__" .. code .. "__/C__"
  end)

  -- Lists
  text = text:gsub("<ul[^>]*>", "\n")
  text = text:gsub("</ul>", "\n")
  text = text:gsub("<ol[^>]*>", "\n")
  text = text:gsub("</ol>", "\n")
  text = text:gsub("<li[^>]*>(.-)</li>", "  * %1\n")

  -- Links
  text = text:gsub('<a[^>]*href="([^"]*)"[^>]*>(.-)</a>', "%2 (%1)")

  -- Horizontal rules (use marker, will be replaced with full-width line dynamically)
  text = text:gsub("<hr[^>]*/?>", "\n__HR__\n")

  -- Tables: proper conversion with dynamic column widths
  text = text:gsub("<table[^>]*>(.-)</table>", function(tbl)
    -- Helper: strip HTML tags and decode entities, preserving inline markers
    local function clean_cell(cell_html)
      local c = cell_html
      -- Convert inline formatting to markers BEFORE stripping HTML
      c = c:gsub("<code>(.-)</code>", "__C__%1__/C__")
      c = c:gsub("<strong>(.-)</strong>", "__B__%1__/B__")
      c = c:gsub("<b>(.-)</b>", "__B__%1__/B__")
      c = c:gsub("<em>(.-)</em>", "__B__%1__/B__")
      c = c:gsub("<i>(.-)</i>", "__B__%1__/B__")
      -- Strip remaining HTML tags
      c = c:gsub("<[^>]+>", "")
      c = c:gsub("&lt;", LT)
      c = c:gsub("&gt;", GT)
      c = c:gsub("&amp;", "&")
      c = c:gsub("&quot;", '"')
      c = c:gsub("&#39;", "'")
      c = c:gsub("&nbsp;", " ")
      c = c:gsub("%s+", " ")
      return vim.trim(c)
    end

    -- Helper: get display width by stripping inline markers
    local function display_width(s)
      local clean = s:gsub("__/?[BCH]__", "")
      return vim.fn.strdisplaywidth(clean)
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
        local w = display_width(cell)
        if w > col_widths[c] then
          col_widths[c] = w
        end
      end
      -- Minimum width of 3
      col_widths[c] = math.max(3, col_widths[c])
    end

    -- Build table output
    local out = "\n"

    local function make_border(left, mid, right, fill)
      local parts = {}
      for c = 1, num_cols do
        table.insert(parts, string.rep(fill, col_widths[c] + 2))
      end
      return left .. table.concat(parts, mid) .. right
    end

    local top_line = make_border("┌", "┬", "┐", "─")
    local sep_line = make_border("├", "┼", "┤", "─")
    local bot_line = make_border("└", "┴", "┘", "─")

    out = out .. top_line .. "\n"

    for r, row in ipairs(rows) do
      local parts = {}
      for c = 1, num_cols do
        local cell = row[c] or ""
        local w = display_width(cell)
        local pad = math.max(0, col_widths[c] - w)
        table.insert(parts, " " .. cell .. string.rep(" ", pad) .. " ")
      end
      out = out .. "│" .. table.concat(parts, "│") .. "│\n"

      -- Add separator after header row (or first row if no header)
      if (is_header[r] and r < #rows) or (not is_header[1] and r == 1 and #rows > 1) then
        out = out .. sep_line .. "\n"
      end
    end

    out = out .. bot_line .. "\n"

    return out .. "\n"
  end)

  -- Images: show [alt](url) for non-math images (math images already handled via inline-math spans)
  text = text:gsub('<img[^>]*>', function(tag)
    local alt = tag:match('alt="([^"]*)"') or "img"
    local src = tag:match('src="([^"]*)"') or ""
    if alt == "" then alt = "img" end
    -- If src is a relative URL, make it absolute
    if src ~= "" and not src:match("^https?://") then
      src = config.options.base_url .. src
    end
    if src ~= "" then
      return "[" .. alt .. "](" .. src .. ")"
    end
    return "[" .. alt .. "]"
  end)

  -- Superscript / subscript
  text = text:gsub("<sup>(.-)</sup>", "^%1")
  text = text:gsub("<sub>(.-)</sub>", "_%1")

  -- Strip remaining tags
  text = text:gsub("<[^>]+>", "")

  -- Restore sentinel bytes from latex_to_text() to real < and >
  text = text:gsub(LT, "<")
  text = text:gsub(GT, ">")

  -- Handle DMOJ tilde-delimited inline math: ~expr~
  -- (After tag stripping, so we can safely restore sentinels immediately)
  text = text:gsub("~([^~\n]+)~", function(content)
    local r = latex_to_text(content)
    return r:gsub(LT, "<"):gsub(GT, ">")
  end)

  -- Handle \( \) and \[ \] LaTeX delimiters in text
  text = text:gsub("\\%((.-)\\%)", function(tex)
    local r = latex_to_text(tex)
    return r:gsub(LT, "<"):gsub(GT, ">")
  end)
  text = text:gsub("\\%[(.-)\\%]", function(tex)
    local r = latex_to_text(tex)
    return "\n" .. r:gsub(LT, "<"):gsub(GT, ">") .. "\n"
  end)

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
  text = text:gsub("&asymp;", "~=")
  text = text:gsub("&equiv;", "===")
  text = text:gsub("&sub;", "c")
  text = text:gsub("&sube;", "c=")
  text = text:gsub("&sup;", ")c")
  text = text:gsub("&supe;", ")c=")
  text = text:gsub("&isin;", " in ")
  text = text:gsub("&notin;", " not in ")
  text = text:gsub("&sum;", "sum")
  text = text:gsub("&prod;", "prod")
  text = text:gsub("&infin;", "inf")
  text = text:gsub("&radic;", "sqrt")
  text = text:gsub("&alpha;", "alpha")
  text = text:gsub("&beta;", "beta")
  text = text:gsub("&pi;", "pi")
  text = text:gsub("&sigma;", "sigma")
  text = text:gsub("&#(%d+);", function(n)
    local num = tonumber(n)
    if not num then return "" end
    if num < 128 then
      return string.char(num)
    elseif num < 2048 then
      return string.char(
        192 + math.floor(num / 64),
        128 + (num % 64)
      )
    elseif num < 65536 then
      return string.char(
        224 + math.floor(num / 4096),
        128 + math.floor((num % 4096) / 64),
        128 + (num % 64)
      )
    end
    return ""
  end)
  text = text:gsub("&#x(%x+);", function(h)
    local num = tonumber(h, 16)
    if not num then return "" end
    if num < 128 then
      return string.char(num)
    elseif num < 2048 then
      return string.char(
        192 + math.floor(num / 64),
        128 + (num % 64)
      )
    elseif num < 65536 then
      return string.char(
        224 + math.floor(num / 4096),
        128 + math.floor((num % 4096) / 64),
        128 + (num % 64)
      )
    end
    return ""
  end)

  -- Collapse multiple blank lines
  text = text:gsub("\n\n\n+", "\n\n")
  text = vim.trim(text)

  -- Split into lines
  local lines = {}
  local inline_hls = {}
  local hr_rows = {} -- track HR separator row positions (0-based within desc lines)
  local in_code = false
  for line in text:gmatch("([^\n]*)\n?") do
    if line == "__CODE__" then
      in_code = true
      table.insert(lines, "")
    elseif line == "__/CODE__" then
      in_code = false
      table.insert(lines, "")
    elseif line == "__HR__" then
      -- HR placeholder: insert a 40-char placeholder (will be dynamically resized)
      table.insert(hr_rows, #lines) -- 0-based row index
      table.insert(lines, string.rep("─", 40))
    else
      -- Convert heading markers to icon-prefixed lines
      local heading_text = line:match("__H__(.-)__/H__")
      if heading_text then
        -- Choose icon based on heading content
        local lower = heading_text:lower()
        local icon = "📝"
        -- Check input/output first so "Sample Input" and "Sample Output" get
        -- the correct directional icon instead of the generic "💡" sample icon.
        if lower:match("input") and not lower:match("output") then
          icon = "📥"
        elseif lower:match("output") then
          icon = "📤"
        elseif lower:match("constraint") or lower:match("limit") or lower:match("bound") then
          icon = "📏"
        elseif lower:match("note") or lower:match("hint") or lower:match("explanation") then
          icon = "💬"
        elseif lower:match("example") or lower:match("sample") then
          icon = "💡"
        end
        -- Replace the heading markup with the icon and plain text
        line = line:gsub("__H__(.-)__/H__", icon .. " %1")
      end

      -- Extract inline formatting and record highlights
      local out_line, hls = extract_inline_hls(line, #lines)
      table.insert(lines, out_line)
      for _, h in ipairs(hls) do
        table.insert(inline_hls, h)
      end
    end
  end

  return lines, inline_hls, hr_rows
end

--- Apply syntax highlighting to the description buffer.
---@param bufnr number
---@param header_end number line index (0-based) where header ends
---@param inline_hls? table list of inline highlight ranges
local function apply_highlights(bufnr, header_end, inline_hls)
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
      
    -- Custom headings (icon-prefixed lines from html_to_lines)
    elseif line:match("^💡 ") or line:match("^📥 ") or line:match("^📤 ") or line:match("^📏 ") or line:match("^💬 ") or line:match("^📝 ") then
      vim.api.nvim_buf_add_highlight(bufnr, ns, "@markup.heading", row, 0, -1)
      
    -- Indented code blocks (4 spaces)
    elseif line:match("^    ") and row > header_end then
      vim.api.nvim_buf_add_highlight(bufnr, ns, "String", row, 0, -1)
      
    -- Bullet points
    elseif line:match("^%s+%*%s") then
      local s, e = line:find("%*")
      if s then
        vim.api.nvim_buf_add_highlight(bufnr, ns, "Special", row, s - 1, e)
      end

    -- Footer line
    elseif line:find("%[o%]") and line:find("%[q%]") then
      vim.api.nvim_buf_add_highlight(bufnr, ns, "Comment", row, 0, -1)

    -- HR separator lines (all ─ characters)
    elseif line:match("^─+$") then
      vim.api.nvim_buf_add_highlight(bufnr, ns, "Comment", row, 0, -1)

    -- Image links [alt](url)
    elseif row > header_end then
      -- Highlight image link URLs inline
      local search_start = 1
      while true do
        local s, e = line:find("%[.-%]%(https?://[^%)]+%)", search_start)
        if not s then break end
        local bracket_end = line:find("%]%(", s)
        if bracket_end then
          -- [alt] part: @markup.link
          vim.api.nvim_buf_add_highlight(bufnr, ns, "@markup.link", row, s - 1, bracket_end)
          -- (url) part: @markup.link.url
          vim.api.nvim_buf_add_highlight(bufnr, ns, "@markup.link.url", row, bracket_end, e)
        end
        search_start = e + 1
      end
    end
  end

  if inline_hls then
    for _, h in ipairs(inline_hls) do
      local r = h.row + header_end + 1
      pcall(vim.api.nvim_buf_add_highlight, bufnr, ns, h.hl, r, h.col_start, h.col_end)
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

    -- Extract the problem description from the HTML.
    -- DMOJ wraps the description content inside <div class="content-description">
    -- which often contains <html><body>...</body></html>. We extract the <body>
    -- content to avoid truncation at nested </div> tags (e.g. from h-scrollable-table).
    local desc_html
    local desc_div = resp.body:match('<div[^>]*class="[^"]*content%-description[^"]*"[^>]*>(.*)')
    if desc_div then
      -- Try to extract <body> content first (DMOJ embeds <html><body>...</body></html>)
      desc_html = desc_div:match("<body>(.-)</body>")
      if not desc_html then
        -- No <body> wrapper — find the balanced end of the content-description div
        -- by tracking div nesting depth
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

    -- Build header (raw text, centering applied dynamically)
    local lines = {}
    local title = meta.name or code

    -- One-line stats
    local stats = {}
    table.insert(stats, tostring(meta.points or 0) .. " pts")
    table.insert(stats, tostring(meta.time_limit or "?") .. "s")
    table.insert(stats, tostring(math.floor((meta.memory_limit or 0) / 1024)) .. " MB")
    if meta.group and meta.group ~= "" then
      table.insert(stats, meta.group)
    end
    local stats_line = table.concat(stats, " | ")

    -- Header lines (rows 0-6): will be centered dynamically
    -- Row 0: empty, Row 1: URL, Row 2: empty, Row 3: empty, Row 4: title, Row 5: stats, Row 6: empty
    table.insert(lines, "")
    table.insert(lines, url)       -- placeholder, will be centered
    table.insert(lines, "")
    table.insert(lines, "")
    table.insert(lines, title)     -- placeholder, will be centered
    table.insert(lines, stats_line) -- placeholder, will be centered
    table.insert(lines, "")

    local header_end = #lines

    table.insert(lines, "")

    local inline_hls = {}
    local hr_rows = {} -- HR separator row indices relative to buffer (0-based)
    -- Parse and append description
    if desc_html then
      local desc_lines, hls, desc_hr_rows = html_to_lines(desc_html)
      vim.list_extend(lines, desc_lines)
      inline_hls = hls
      -- Offset HR rows by header_end + 1 (they are relative to desc_lines, need buffer-relative;
      -- +1 accounts for the blank line inserted between header and description at line 751)
      for _, r in ipairs(desc_hr_rows or {}) do
        table.insert(hr_rows, r + header_end + 1)
      end
    else
      table.insert(lines, "  (Could not extract problem description.)")
      table.insert(lines, "  Open in browser: " .. url)
    end

    table.insert(lines, "")
    table.insert(lines, string.rep("─", 40)) -- placeholder, will be resized dynamically
    table.insert(lines, " [o] Open in browser  [q] Close")

    local footer_sep_row = #lines - 2 -- 0-based: #lines - 2 (the separator line)

    local split_width = math.floor(vim.o.columns * 0.4)
    local bufnr = ui.create_buf("dmoj://problem/" .. code, lines, {})
    ui.open_split_left(bufnr, { width = split_width })

    -- Dynamic centering function: centers header rows and resizes footer separator
    local function recenter_header(win)
      if not vim.api.nvim_buf_is_valid(bufnr) then return end
      if not vim.api.nvim_win_is_valid(win) then return end

      local win_width = vim.api.nvim_win_get_width(win)
      local text_width = win_width - 4 -- account for padding/signcolumn

      local function center(s)
        local display_width = vim.fn.strdisplaywidth(s)
        local pad = math.max(0, math.floor((text_width - display_width) / 2))
        return string.rep(" ", pad) .. s
      end

      vim.bo[bufnr].modifiable = true
      -- Row 1 (0-indexed): URL
      vim.api.nvim_buf_set_lines(bufnr, 1, 2, false, { center(url) })
      -- Row 4 (0-indexed): title
      vim.api.nvim_buf_set_lines(bufnr, 4, 5, false, { center(title) })
      -- Row 5 (0-indexed): stats
      vim.api.nvim_buf_set_lines(bufnr, 5, 6, false, { center(stats_line) })
      -- Footer separator
      vim.api.nvim_buf_set_lines(bufnr, footer_sep_row, footer_sep_row + 1, false, { string.rep("─", text_width) })
      -- HR separators (within description content)
      for _, hr_row in ipairs(hr_rows) do
        if hr_row >= 0 and hr_row < vim.api.nvim_buf_line_count(bufnr) then
          vim.api.nvim_buf_set_lines(bufnr, hr_row, hr_row + 1, false, { string.rep("─", text_width) })
        end
      end
      vim.bo[bufnr].modifiable = false

      -- Re-apply highlights after changing lines
      apply_highlights(bufnr, header_end, inline_hls)
    end

    -- Get the window we just opened
    local win = vim.api.nvim_get_current_win()

    -- Initial centering
    recenter_header(win)

    -- Re-center on window resize
    vim.api.nvim_create_autocmd("WinResized", {
      callback = function()
        if not vim.api.nvim_buf_is_valid(bufnr) then return true end
        if not vim.api.nvim_win_is_valid(win) then return true end
        -- Check if our window was among the resized ones
        local resized = vim.v.event and vim.v.event.windows or {}
        for _, w in ipairs(resized) do
          if w == win then
            recenter_header(win)
            break
          end
        end
      end,
    })

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

--- Export html_to_lines for reuse in other modules (e.g., contests).
M.html_to_lines = html_to_lines

return M
