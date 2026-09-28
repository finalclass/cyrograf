# Cyrograf Markdown example

This document contains a `cyrograf` fenced block. The block uses the same
syntax rules as a standalone `.cyrograf` file, without a running language
server and without a complete module.

```cyrograf
// A small standalone block; it does not have to form a valid project.
struct Marked {
  item: String
  note?: String
}
```

The text below the fence is ordinary prose and is not colored as Cyrograf.

## Enabling block coloring

First install the integration for your editor using the
[installation guide](../README.md#installation). It links the GitHub
repository and gives the exact directories to load for each editor.

- **Emacs** (`markdown-mode` or `gfm-mode`): load `cyrograf-mode` and enable
  native block fontification, for example

  ```elisp
  (setq markdown-fontify-code-blocks-natively t)
  ```

  The `cyrograf` language is already mapped to `cyrograf-mode` when
  `cyrograf-mode.el` is loaded after `markdown-mode`.

- **Vim and Neovim**: set the fenced language list before Markdown syntax
  loads, for example in your configuration

  ```vim
  let g:markdown_fenced_languages = get(g:, 'markdown_fenced_languages', [])
  if index(g:markdown_fenced_languages, 'cyrograf') < 0
    call add(g:markdown_fenced_languages, 'cyrograf')
  endif
  ```

  The [Neovim guide](../neovim/README.md#markdown-fenced-blocks) includes the
  equivalent Lua configuration. Classic `syntax` highlighting is enough;
  no Tree-sitter parser is required.

- **VS Code**: [build and install the VSIX](../vscode/README.md#installation).
  It colors the fence in the editor and in the built-in Markdown preview.

GitHub.com and other external renderers need their own language registration;
installing a local editor package does not add the language there.
