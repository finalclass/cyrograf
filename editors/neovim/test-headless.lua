-- Batch checks for the Cyrograf Neovim integration.
--
-- Run with:
--   nvim --headless -l test-headless.lua
-- with CYROGRAF_EDITORS, CYROGRAF_BIN and CYROGRAF_NVIM_PROJECT set.
--
-- The script checks the shared Vim syntax resources in Neovim, the Markdown
-- fenced-block highlighting with the classic `syntax` mechanism, and a real
-- session against the installed `cyrograf lsp` server. It never edits the
-- user configuration: the runtime path is extended in this process only.

local editors = assert(vim.env.CYROGRAF_EDITORS, "CYROGRAF_EDITORS is not set")
local bin = assert(vim.env.CYROGRAF_BIN, "CYROGRAF_BIN is not set")
local project = assert(vim.env.CYROGRAF_NVIM_PROJECT, "CYROGRAF_NVIM_PROJECT is not set")

local failures = 0

local function check(label, condition)
  if condition then
    print("PASS: " .. label)
  else
    failures = failures + 1
    print("FAIL: " .. label)
  end
end

local function group_name(lnum, col)
  return vim.fn.synIDattr(vim.fn.synID(lnum, col, 1), "name")
end

local function find_line(pattern)
  for lnum = 1, vim.api.nvim_buf_line_count(0) do
    local col = string.find(vim.api.nvim_buf_get_lines(0, lnum - 1, lnum, false)[1], pattern)
    if col then
      return lnum, col
    end
  end
  return nil, nil
end

vim.opt.runtimepath:prepend(editors .. "/vim")
vim.opt.runtimepath:prepend(editors .. "/neovim")
vim.g.cyrograf_lsp_program = bin
vim.g.markdown_fenced_languages = { "cyrograf" }
vim.cmd("syntax enable")
vim.cmd("filetype plugin indent on")
vim.lsp.enable("cyrograf")

-- ── Shared syntax on a standalone file ─────────────────────────────
vim.cmd("edit " .. vim.fn.fnameescape(project .. "/Orders.cyrograf"))
check("filetype detected as cyrograf", vim.bo.filetype == "cyrograf")
do
  local lnum, col = find_line("struct")
  check("struct highlighted as declaration",
    lnum ~= nil and group_name(lnum, col) == "cyrografDeclarationStruct")
  lnum, col = find_line("String")
  check("primitive highlighted", lnum ~= nil and group_name(lnum, col) == "cyrografPrimitive")
  lnum, col = find_line("owner_id")
  check("field highlighted", lnum ~= nil and group_name(lnum, col) == "cyrografField")
  lnum, col = find_line("//")
  check("comment highlighted", lnum ~= nil and group_name(lnum, col) == "cyrografComment")
end

-- ── Markdown fenced blocks through the classic syntax mechanism ────
local markdown = vim.fn.tempname() .. ".md"
vim.fn.writefile({
  "# Example",
  "",
  "```cyrograf",
  "// <b>&</b> comment",
  "struct Marked {",
  "  item: String",
  "}",
  "```",
  "",
  "prose stays prose",
  "",
  "````cyrograf",
  "```",
  "struct Longer {",
  "}",
  "````",
  "",
  "```json",
  "struct NotCyrograf {}",
  "```",
}, markdown)
vim.cmd("edit " .. vim.fn.fnameescape(markdown))
check("markdown filetype", vim.bo.filetype == "markdown")
do
  local lnum, col = find_line("struct Marked")
  check("markdown block declaration highlighted",
    lnum ~= nil and group_name(lnum, col) == "cyrografDeclarationStruct")
  local clnum = vim.fn.search("// <b>")
  if clnum > 0 then
    local ccol = string.find(vim.api.nvim_buf_get_lines(0, clnum - 1, clnum, false)[1], "//")
    check("markdown block comment highlighted", group_name(clnum, ccol) == "cyrografComment")
  else
    check("markdown block comment highlighted", false)
  end
  local llnum, lcol = find_line("struct Longer")
  check("shorter backtick run inside a longer fence does not close it",
    llnum ~= nil and group_name(llnum, lcol) == "cyrografDeclarationStruct")
  local pnum, pcol = find_line("prose stays prose")
  check("prose after the fence is not cyrograf",
    pnum ~= nil and group_name(pnum, pcol) ~= "cyrografDeclarationStruct")
  local jnum, jcol = find_line("struct NotCyrograf")
  check("other language block is not cyrograf",
    jnum ~= nil and group_name(jnum, jcol) ~= "cyrografDeclarationStruct")
end
do
  local markdown_buf = vim.api.nvim_get_current_buf()
  check("markdown highlighting does not start the server",
    #vim.lsp.get_clients({ bufnr = markdown_buf, name = "cyrograf" }) == 0)
end

-- ── A real language server session ─────────────────────────────────
local orders = project .. "/Orders.cyrograf"
vim.cmd("edit " .. vim.fn.fnameescape(orders))
local bufnr = vim.api.nvim_get_current_buf()

local function attached()
  return #vim.lsp.get_clients({ bufnr = bufnr, name = "cyrograf" }) > 0
end

vim.wait(30000, attached, 100)
check("lsp client attached", attached())

vim.wait(30000, function()
  return #vim.diagnostic.get(bufnr) == 0
end, 100)

local function diagnostic_codes()
  local codes = {}
  for _, diagnostic in ipairs(vim.diagnostic.get(bufnr)) do
    codes[#codes + 1] = tostring(diagnostic.code)
  end
  return codes
end

local function replace_line(pattern, replacement)
  local lnum = vim.fn.search(pattern, "nw")
  if lnum > 0 then
    vim.api.nvim_buf_set_lines(bufnr, lnum - 1, lnum, false, { replacement })
  end
  return lnum
end

check("unsaved error introduced",
  replace_line("Common.Thing", "  item: Common.Missing") > 0)
vim.wait(30000, function()
  return vim.tbl_contains(diagnostic_codes(), "UnresolvedReference")
end, 100)
check("unsaved error diagnosed", vim.tbl_contains(diagnostic_codes(), "UnresolvedReference"))

check("error repaired", replace_line("Common.Missing", "  item: Common.Thing") > 0)
vim.wait(30000, function()
  return #vim.diagnostic.get(bufnr) == 0
end, 100)
check("diagnostics cleared after repair", #vim.diagnostic.get(bufnr) == 0)

local def_line = vim.fn.search("Common.Thing", "nw")
vim.api.nvim_win_set_cursor(0, { def_line, string.find(vim.api.nvim_buf_get_lines(0, def_line - 1, def_line, false)[1], "Common") - 1 })
vim.lsp.buf.definition()
vim.wait(30000, function()
  return vim.api.nvim_buf_get_name(0):match("Common%.cyrograf$") ~= nil
end, 100)
check("definition opens the other module",
  vim.api.nvim_buf_get_name(0):match("Common%.cyrograf$") ~= nil)

local messy = "struct   A{x:String;y?:Int}\n"
local formatted_file = vim.fn.tempname() .. "/A.cyrograf"
vim.fn.mkdir(vim.fn.fnamemodify(formatted_file, ":h"), "p")
vim.fn.writefile({ "struct   A{x:String;y?:Int}" }, formatted_file)
vim.cmd("edit " .. vim.fn.fnameescape(formatted_file))
local format_buf = vim.api.nvim_get_current_buf()
vim.wait(30000, function()
  return #vim.lsp.get_clients({ bufnr = format_buf, name = "cyrograf" }) > 0
end, 100)
vim.wait(30000, function()
  return #vim.diagnostic.get(format_buf) == 0
end, 100)
vim.lsp.buf.format({ async = false })
local expected = vim.fn.system({ bin, "format", "--stdin", "--filename", "A.cyrograf" }, messy)
expected = expected:gsub("\n$", "")
local formatted = table.concat(vim.api.nvim_buf_get_lines(format_buf, 0, -1, false), "\n")
check("LSP formatting matches the CLI", formatted == expected)

print(("neovim checks: %d failure(s)"):format(failures))
vim.cmd(failures == 0 and "qall!" or "cquit")
os.exit(failures == 0 and 0 or 1)