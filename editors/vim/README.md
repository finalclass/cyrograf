# Cyrograf for Vim

Syntax recognition, syntax highlighting and indentation for `.cyrograf`
contract files. These files work in Vim without any LSP client.

## Installation

Fetch the files from GitHub, then link the **`editors/vim` subdirectory** as a
native Vim package:

```sh
mkdir -p "$HOME/.local/share"
git clone https://github.com/finalclass/cyrograf.git "$HOME/.local/share/cyrograf"
mkdir -p "$HOME/.vim/pack/cyrograf/start"
ln -s "$HOME/.local/share/cyrograf/editors/vim" \
  "$HOME/.vim/pack/cyrograf/start/cyrograf"
```

If you already have the checkout, skip the clone and use its path in `ln -s`.
If you installed the whole repository at the package path from an older
guide, move that checkout to `~/.local/share/cyrograf` first, then create the
link. Vim needs the directory containing `ftdetect/`, `syntax/`, `ftplugin/`
and `indent/` on its runtime path; these are below the repository root.

Enable the package, filetype plugins, indentation and syntax in `~/.vimrc`:

```vim
packadd cyrograf
filetype plugin indent on
syntax enable
```

Restart Vim and open a `.cyrograf` file; `:set filetype?` should show
`filetype=cyrograf`.

The `ftdetect` script uses `setfiletype`, so it never overrides a filetype that
you set yourself.

## Language server with yegappan/lsp

Install the [Cyrograf program](../../README.md#install) and check
`cyrograf --version`. If you do not already use
[yegappan/lsp](https://github.com/yegappan/lsp), install it as an optional native
package:

```sh
mkdir -p "$HOME/.vim/pack/cyrograf/opt"
git clone https://github.com/yegappan/lsp.git "$HOME/.vim/pack/cyrograf/opt/lsp"
```

Save this Vim9 configuration in `~/.vim/cyrograf-lsp.vim`. Loading the plugin
with `packadd` makes `LspAddServer` available before the server is registered:

```vim
vim9script

packadd lsp

var cyrograf = [{
  name: 'cyrograf',
  filetype: ['cyrograf'],
  path: 'cyrograf',
  args: ['lsp', '--stdio'],
  syncInit: v:true,
}]
g:LspAddServer(cyrograf)
```

Load that file from `~/.vimrc` after the highlighting configuration:

```vim
source ~/.vim/cyrograf-lsp.vim
```

This keeps `vim9script` at the start of its own file and works with an existing
legacy `vimrc`. If you already load yegappan/lsp through a plugin manager, use
its setup hook instead, following the
[upstream configuration guide](https://github.com/yegappan/lsp#configuration).

If `cyrograf` is not on `PATH`, point `path` at the absolute location, for
example `path: expand('~/.local/bin/cyrograf')` after the default `make install`.
The program and its arguments are separate list items, so a path containing
spaces is not split by a shell. Restart Vim after adding the configuration.

Then in a Cyrograf buffer:

- `:LspHover` shows the symbol type,
- `:LspGotoDefinition` jumps to local and qualified definitions,
- `:LspDiag show` lists diagnostics,
- `:LspFormat` formats the document through the shared formatter,
- `:LspDocumentSymbol` and completion (`autoComplete`) use the same server.

A missing program makes the plugin report that the server could not start; it
does not download anything.

## Markdown fenced blocks

Vim's own Markdown syntax can color a `cyrograf` fenced block with this
syntax file. Register the language before the Markdown syntax is loaded, for
example in your `vimrc`:

```vim
let g:markdown_fenced_languages = get(g:, 'markdown_fenced_languages', [])
if index(g:markdown_fenced_languages, 'cyrograf') < 0
  call add(g:markdown_fenced_languages, 'cyrograf')
endif
```

The block then highlights with the same groups as a standalone file. The
registration only adds `cyrograf`; it does not replace the registration of any
other language. The classic `syntax` mechanism is enough, and no Tree-sitter
parser is required. `editors/example/README.md` has a block to try.

## Verified versions

`make test-editors` runs the syntax and indent checks with Vim 9.0 and a real
`yegappan/lsp` session against the built `cyrograf` binary, using the pinned
commit `58eac06e81bad174cfa897614ae01adf0d31d10a` fetched by
`make editors-tools`. The session starts `cyrograf lsp` for diagnostics,
definition and formatting. `yegappan/lsp` requires Vim 9.0 or newer; the
configuration above uses `vim9script`. See the release report for the exact
run.
