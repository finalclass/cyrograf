# Cyrograf for Neovim

Support for `.cyrograf` files in Neovim 0.11 and newer. File type detection,
syntax highlighting and indentation come from the shared
[Vim resources](../vim/); Neovim adds a configuration for its built-in LSP
client that starts the installed `cyrograf lsp` server. A Tree-sitter parser
is not required.

## Installation

Install the [Cyrograf program](../../README.md#install) for LSP features and
check `cyrograf --version`. Fetch the editor files from GitHub:

```sh
mkdir -p "$HOME/.local/share"
git clone https://github.com/finalclass/cyrograf.git "$HOME/.local/share/cyrograf"
```

Skip the clone if you already used that location to install the program.
Add this to `init.lua` (normally `~/.config/nvim/init.lua`); no plugin manager
is required. Both subdirectories are needed:

```lua
local cyrograf = vim.fn.expand("~/.local/share/cyrograf")
vim.opt.runtimepath:append(cyrograf .. "/editors/vim")
vim.opt.runtimepath:append(cyrograf .. "/editors/neovim")

vim.lsp.enable("cyrograf")
```

If you use another checkout location, change `cyrograf` in the snippet.
Restart Neovim and open a `.cyrograf` file. If the program is not on Neovim's
`PATH`, set its location **before** `vim.lsp.enable`, for example after the
default `make install`:

```lua
vim.g.cyrograf_lsp_program = vim.fn.expand("~/.local/bin/cyrograf")
```

`lsp/cyrograf.lua` starts `{ cyrograf, "lsp" }` for `cyrograf` buffers and uses
the buffer's directory as the project root. The command is a list; a path with
spaces is never split by a shell. A missing program is reported by the client
when it tries to start the server, and nothing is downloaded automatically.

Once a `.cyrograf` file is open with the server enabled:

- diagnostics come from the same analysis as `cyrograf check`,
- `vim.lsp.buf.definition()` jumps to local and qualified definitions,
- `vim.lsp.buf.format()` formats through the shared formatter.

## Markdown fenced blocks

Color a `cyrograf` fence with the editor's classic Markdown syntax. Set the
fenced language list before Markdown syntax is loaded:

```lua
local fenced = vim.g.markdown_fenced_languages or {}
if not vim.tbl_contains(fenced, "cyrograf") then
  table.insert(fenced, "cyrograf")
end
vim.g.markdown_fenced_languages = fenced
```

The package does not require a Tree-sitter parser and does not override a
parser you already use. The block highlights with the shared Vim syntax
groups. See [../example/README.md](../example/README.md) for a block to try.

## Verified versions

The batch checks run Neovim 0.11.2 (fetched by `make editors-tools`) with a
separate runtime path; they never edit your configuration. The suite includes
a real built-in `vim.lsp` session that starts `cyrograf lsp` for diagnostics,
definition and formatting. The baseline is Neovim 0.11 with its built-in
`vim.lsp` client; the release report records the exact run.
