-- Built-in LSP client configuration for Neovim 0.11 and newer.
--
-- `vim.lsp.enable('cyrograf')` loads this file from the runtime path and starts
-- the installed `cyrograf lsp` server for `cyrograf` buffers. The program is a
-- list item, so a path with spaces is never split by a shell. Set
-- `vim.g.cyrograf_lsp_program` before enabling the server to point at another
-- location.

local function root_dir(bufnr, on_dir)
  local name = vim.api.nvim_buf_get_name(bufnr)
  if name == "" then
    return
  end
  on_dir(vim.fs.dirname(name))
end

return {
  cmd = { vim.g.cyrograf_lsp_program or "cyrograf", "lsp" },
  filetypes = { "cyrograf" },
  root_dir = root_dir,
}