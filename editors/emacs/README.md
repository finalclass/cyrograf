# Cyrograf for Emacs

`cyrograf-mode.el` provides `cyrograf-mode` for `.cyrograf` files: syntax
recognition, font-lock, `//` line comments and basic brace indentation. Eglot
uses the installed `cyrograf lsp` server for diagnostics, navigation and
formatting.

## Installation

Install the [Cyrograf program](../../README.md#install) for Eglot and check
`cyrograf --version`. Doom users can go straight to the
[GitHub recipe below](#doom-emacs) to install the mode.

For plain Emacs, fetch the mode from GitHub:

```sh
mkdir -p "$HOME/.local/share"
git clone https://github.com/finalclass/cyrograf.git "$HOME/.local/share/cyrograf"
```

Skip the clone if that checkout already exists. Add this to `init.el`
(normally `~/.emacs.d/init.el`), adjusting the path if you cloned elsewhere:

```elisp
(add-to-list 'load-path
             (expand-file-name "~/.local/share/cyrograf/editors/emacs"))
(require 'cyrograf-mode)
```

Optionally enable Eglot in Cyrograf buffers:

```elisp
(add-hook 'cyrograf-mode-hook #'eglot-ensure)
```

`cyrograf-lsp-program` (default `"cyrograf"`) is the program path; it may
contain spaces because the command is passed to the process as a list, never
through a shell. `cyrograf-lsp-args` defaults to `("lsp")`. Loading the package
does not start a server: Eglot starts it only when it is enabled in a Cyrograf
buffer.

Eglot is built into Emacs 29 and newer. On older Emacs, install Eglot from
GNU ELPA. Restart Emacs and open a `.cyrograf` file. If the program is not on
Emacs's `exec-path`, set its location explicitly after loading the mode:

```elisp
(setq cyrograf-lsp-program (expand-file-name "~/.local/bin/cyrograf"))
```

## Doom Emacs

Declare the package in `packages.el` in your Doom configuration directory:

```elisp
(package! cyrograf-mode
  :recipe (:host github
           :repo "finalclass/cyrograf"
           :files ("editors/emacs/cyrograf-mode.el")))
```

Configure the mode in `config.el`:

```elisp
(use-package! cyrograf-mode
  :mode "\\.cyrograf\\'"
  :hook (cyrograf-mode . eglot-ensure))
```

Run `doom sync` and restart Emacs after adding the package, as described in
[Doom's package installation guide](https://github.com/doomemacs/doomemacs/blob/master/docs/getting_started.org#installing-packages).
The recipe downloads the mode from GitHub; install the `cyrograf` executable
separately and make it available on Emacs's `PATH`, or set `cyrograf-lsp-program`.

Eglot is already present in Doom; the mode registers `cyrograf lsp` through
`eglot-server-programs` when Eglot is loaded.

## Markdown fenced blocks

`markdown-mode` and `gfm-mode` can color a `cyrograf` fenced block with the
same faces as a standalone file. The mode is registered automatically when
`cyrograf-mode.el` is loaded after `markdown-mode`. Enable native block
fontification, for example in your configuration:

```elisp
(setq markdown-fontify-code-blocks-natively t)
```

Block coloring does not start a language server and does not require a
complete contract. `markdown-mode` is an optional dependency of this feature
only; standalone `.cyrograf` files do not need it.

## Verified versions

`make test-editors` runs the batch checks plus a real Eglot session against the
built `cyrograf` binary. The verified environment was Emacs 30.1 with its
built-in Eglot (see the release report for the exact run); the baseline is
Emacs 29 with its built-in Eglot, and older Emacs needs Eglot from GNU ELPA.
The batch checks also run with `markdown-mode` 2.8 for the fenced-block faces.

The language server ignores the Emacs lock files (`.#name`) that Emacs creates
while editing; a lock file does not suppress diagnostics.
