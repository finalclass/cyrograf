# Cyrograf for VS Code

The extension registers the `cyrograf` language, contributes the shared
TextMate grammar, sets `//` comments and bracket pairs, and starts the
installed `cyrograf lsp` server for documents of the language.

## Installation

Install the [Cyrograf program](../../README.md#install) and check
`cyrograf --version`. Build the extension from GitHub using Node.js and npm:

```sh
mkdir -p "$HOME/.local/share"
git clone https://github.com/finalclass/cyrograf.git "$HOME/.local/share/cyrograf"
cd "$HOME/.local/share/cyrograf/editors/vscode"
npm ci
npm run compile        # esbuild bundle in dist/
npm run package        # produces cyrograf-vscode.vsix
code --install-extension cyrograf-vscode.vsix
```

If you already have the checkout, skip the clone and use its path in `cd`.
If the `code` command is unavailable, run **Extensions: Install from VSIX…**
from the Command Palette and select
`~/.local/share/cyrograf/editors/vscode/cyrograf-vscode.vsix`, as described in
the [VS Code installation guide](https://code.visualstudio.com/docs/configure/extensions/extension-marketplace#_install-from-a-vsix).
Reload VS Code when prompted, then open a `.cyrograf` file.

The client dependencies are bundled into `dist/extension.js`, so the installed
extension needs neither a separate Node.js installation nor Deno. The
`cyrograf` program is installed separately from the extension.

## Settings

- `cyrograf.path` (default `"cyrograf"`): path to the program. It may contain
  spaces; the command and arguments are passed as a list and never composed
  into a shell command.

If VS Code cannot find the program, run `command -v cyrograf` in your shell
and paste the resulting absolute path into the **Cyrograf: Path** setting.

The server is stopped when the extension is deactivated. Changing
`cyrograf.path` restarts the client. Format Document uses the server's
formatting, and diagnostics come from the same analysis as `cyrograf check`.

## Markdown code blocks

The extension colors `cyrograf` fenced blocks in Markdown documents and in the
built-in Markdown preview. The editor grammar injects the shared
`source.cyrograf` grammar, so the block uses the same tokens as a standalone
file. The preview reuses that grammar to render tokens; it does not execute
code, does not fetch resources and escapes HTML in the code text. Both the
grammar and the preview assets are inside the `.vsix`.

Only `cyrograf` fences are affected; other languages and fences without a
language identifier keep the editor's behavior. GitHub.com and other external
renderers need their own language registration and are not changed by
installing this extension.

## Tests

```sh
cd "$HOME/.local/share/cyrograf/editors/vscode"
npm test               # Extension Host tests via @vscode/test-cli
```

`make test-editors` runs the same tests together with the other editors when a
VS Code download and the Electron libraries are available. The Extension Host
suite also checks diagnostics repair, go to definition and Format Document
against the same server as the CLI.

Verified hosts: VS Code 1.95.3 and the current stable (1.139.1 at the time of
the release report). The `.vsix` members are checked as well; the bundle that
the Extension Host loads is the `dist/extension.js` packed into the `.vsix`.
