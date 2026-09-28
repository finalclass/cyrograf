# Cyrograf editor integrations

Editor support for Cyrograf contract files (`.cyrograf`). Every integration
recognizes the extension, highlights the native syntax and connects to the
installed `cyrograf lsp` server. None of them contains a type validator, a copy
of the formatter or a generator: parsing, formatting and code generation stay
in the `cyrograf` program.

A missing `cyrograf` program produces a readable error and installation hint.
No client downloads anything automatically, and no client edits your editor
configuration for you.

## Installation

All editor packages live in
[finalclass/cyrograf on GitHub](https://github.com/finalclass/cyrograf), under
`editors/`. The guides below include the repository URL and the exact
subdirectory to load or import. Manual installation uses
`~/.local/share/cyrograf` as the checkout directory; reuse an existing checkout
and adjust the paths if you prefer. Clone the repository only once when
installing support for several editors. Doom Emacs downloads its mode through
the GitHub recipe instead.

Install the **`cyrograf` program separately** using the
[program installation instructions](../README.md#install), then check
`cyrograf --version`. A source checkout can install it with `make install`.
The editor must see the program on its own `PATH`; if an editor launched from
the desktop does not inherit your shell's `PATH`, set the program's absolute
path in the editor configuration described below. Highlighting alone does not
need the program.

| Editor | Artifact | Install |
|---|---|---|
| Emacs 29+ | [`emacs/cyrograf-mode.el`](emacs/cyrograf-mode.el) | [Clone and configure Eglot, or use the Doom GitHub recipe](emacs/README.md). |
| Vim 9+ | [`vim/`](vim/) | [Link `editors/vim` as a native package and configure yegappan/lsp](vim/README.md). |
| Neovim 0.11+ | [`neovim/`](neovim/) | [Clone, add both editor directories to `runtimepath` and enable the built-in LSP client](neovim/README.md). |
| VS Code 1.85+ | [`vscode/`](vscode/) | [Clone, build and install the VSIX](vscode/README.md); Node.js and npm are needed only to build it. |
| JetBrains IDEs | [`jetbrains/`](jetbrains/) | [Clone and import the TextMate bundle and LSP4IJ template](jetbrains/README.md). |

The VS Code extension and the JetBrains bundle highlight with one shared
[TextMate grammar](shared/cyrograf.tmLanguage.json). `editors/shared/sync.ts`
copies it into both packages and `make test-editors` fails if a copy drifts.

## Markdown code blocks

The language identifier of a Cyrograf fenced block is `cyrograf`, the same
name as the standalone language. Fenced blocks use the same presentation rules
as `.cyrograf` files and never require a complete module, valid types or a
running language server.

- **Emacs**: `markdown-mode` and `gfm-mode` color a `cyrograf` block when
  `markdown-fontify-code-blocks-natively` is enabled. `cyrograf-mode` is
  registered as the block's mode. See [emacs/README.md](emacs/README.md).
- **Vim and Neovim**: add `cyrograf` to the editor's
  `markdown_fenced_languages` setting before Markdown syntax loads, as shown
  in the [Vim](vim/README.md#markdown-fenced-blocks) and
  [Neovim](neovim/README.md#markdown-fenced-blocks) guides. Both packages share
  the same syntax files; a Tree-sitter parser is not required for this path.
- **VS Code**: the editor colors the block through the shared TextMate
  adapter, and the built-in Markdown preview renders the same tokens. The
  adapter and the preview assets are part of the `.vsix`. See
  [vscode/README.md](vscode/README.md).

A fenced block opens with at least three backticks (or tildes) and closes with
a fence of the same character and length; a shorter run of backticks inside
the block does not close it. A comment or an incomplete Cyrograf does not leak
coloring into the prose after the block. Blocks of another language and blocks
without a language identifier keep the editor's default behavior.

Editing Markdown and rendering a preview are separate integrations. The local
editors above are what this release provides. External renderers such as
GitHub.com, static site generators or HTML export have their own language
registries (for GitHub, Linguist) and need a separate registration; installing
a Cyrograf editor package does not add the language to GitHub.com or any other
external renderer. This release does not claim support for untested renderers
or HTML export.

For JetBrains, coloring a Markdown fence through the imported TextMate bundle
depends on the IDE's own Markdown support and is not part of the guaranteed
Markdown scope of this release. Recording the actual result requires an
installed IDE and is left to the release smoke report.

## Trying it out

The [example](example/) is a small, self-contained Cyrograf project. It does
not require Well or any other framework. [`example/README.md`](example/README.md)
is a Markdown document with a `cyrograf` fence for checking the block
coloring:

1. Install the integration for your editor and the `cyrograf` program.
2. Open `editors/example/Orders.cyrograf`. `struct`, `variant`, `rpc`, primitive
   names, message names, field names and the `//` comment are highlighted.
3. Change a type to an unknown name, for example `item: Common.Missing`, and
   save in the editor. The server reports `UnresolvedReference`.
4. Restore `item: Common.Thing` and use go to definition on `Common.Thing`;
   the editor opens `Common.cyrograf`.
5. Run Format Document. The result equals `cyrograf format` on the same file.
6. Open `editors/example/README.md` and enable Markdown block coloring as
   described there; the block's `struct`, `String` and `//` tokens are colored.

Because `cyrograf lsp` keeps an unsaved buffer as the source of truth, steps 3
to 5 work before the file is written.

## Verification

`make test-editors` runs the shared artifact checks and the editor clients:

- the grammar copies match the shared sources, including the Markdown adapter,
- the example keeps a valid project shape,
- Vim runs its ftplugin, syntax and indent in headless mode, including the
  Markdown fence groups, and then runs a real [yegappan/lsp](https://github.com/yegappan/lsp)
  session that starts `cyrograf lsp` for diagnostics, definition and
  formatting,
- Neovim runs the shared syntax and a real built-in `vim.lsp` session for
  diagnostics, definition and formatting in headless mode,
- Emacs runs `cyrograf-mode`, font-lock and the `markdown-mode`/`gfm-mode`
  block faces in batch mode, and then a real Eglot session that starts
  `cyrograf lsp` for diagnostics, repair, definition and formatting,
- VS Code builds, exercises the extension in the Extension Host (including
  repair, definition and formatting through the server), tokenizes the
  Markdown editor grammar and renders the Markdown preview HTML,
- the JetBrains TextMate bundle and LSP4IJ template pass artifact validation.

The clients used for the real sessions are listed in the release report
(`.local/release-progress/08.json`) with their versions. The JetBrains
editor-feature smoke remains open: the IDE and LSP4IJ load, but the required
scenario is not scriptable headlessly, so it is recorded as a blocker rather
than claimed as verified. A valid bundle or template is not a JetBrains smoke
test.
