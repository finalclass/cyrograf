# Cyrograf for JetBrains IDEs

Two independent pieces, both importable into IntelliJ IDEA and its paid and
free editions:

- `Cyrograf.tmBundle/` — a TextMate bundle that adds syntax highlighting. Its
  `Syntaxes/cyrograf.tmLanguage.json` is the same grammar artifact used by the
  VS Code extension (see `../shared/sync.ts`), so the two are never edited
  separately.
- `lsp4ij/template.json` — a ready user-defined language server template for
  [LSP4IJ](https://github.com/redhat-developer/lsp4ij). It registers the
  `cyrograf` program with the `lsp` argument for `*.cyrograf` files and sends
  `languageId = "cyrograf"`.

No custom PSI, no paid IDE edition and no plugin build are required.

## Get the files

Install the [Cyrograf program](../../README.md#install) for LSP features and
check `cyrograf --version`. Fetch the editor files from GitHub:

```sh
mkdir -p "$HOME/.local/share"
git clone https://github.com/finalclass/cyrograf.git "$HOME/.local/share/cyrograf"
```

Skip the clone if that checkout already exists. The paths below use this
location; adjust them if you cloned elsewhere.

## Install the TextMate highlighting

1. Make sure the bundled **TextMate Bundles** plugin is enabled
   (Settings | Plugins).
2. Open Settings | Editor | TextMate Bundles.
3. Click `[+]` and select
   `~/.local/share/cyrograf/editors/jetbrains/Cyrograf.tmBundle` (the whole
   directory). See the [TextMate bundle instructions](https://www.jetbrains.com/help/idea/textmate.html).
4. Open a `.cyrograf` file; `struct`, `variant`, primitives, type names, field
   names and `//` comments are highlighted.

## Install the language server

In Settings | Plugins | Marketplace, install **LSP4IJ** and restart the IDE
if requested. Make `cyrograf` available on the IDE's `PATH`, or enter the
absolute program path in the server's Command field. `command -v cyrograf`
in your shell shows the installed location. Then, in LSP4IJ:

1. Open the LSP console or Settings | Languages & Frameworks | Language
   Servers.
2. Choose **New Language Server**, then **Import from custom template…** in
   the Template list. Select
   `~/.local/share/cyrograf/editors/jetbrains/lsp4ij`, the directory containing
   `template.json`, following the
   [LSP4IJ import instructions](https://github.com/redhat-developer/lsp4ij/blob/main/docs/UserDefinedLanguageServer.md#custom-template).
3. Confirm the template. The command is `cyrograf lsp` and the mapping covers
   the `Cyrograf` file type with pattern `*.cyrograf`.

The program string is a command plus one argument, not a shell pipeline; a path
containing spaces is quoted by LSP4IJ rather than split by a shell. A missing
program is reported by LSP4IJ when it tries to start the server; nothing is
downloaded automatically.

Once running, LSP4IJ provides diagnostics, go to definition, document symbols,
completion and formatting through the same server as the other editors.

## Markdown code blocks

Coloring a `cyrograf` fence in Markdown depends on the IDE's own Markdown
support and on how it composes imported TextMate bundles. It is not part of
the guaranteed Markdown scope of this release. Checking the actual result
requires an installed IDE; the release smoke report records the tested IDE and
LSP4IJ versions, or the missing environment.

## Verified versions

The release report records the checked IDE and LSP4IJ versions. The release
attempt used IntelliJ IDEA Community 2025.3 (build 253.28294.334) with its
bundled JBR 21 and LSP4IJ 0.21.0; both the IDE and LSP4IJ loaded. The
editor-feature smoke (highlighting, diagnostics, definition and formatting in
the IDE) is **not verified**: LSP4IJ requires manual configuration and GUI
interaction, and no headless path drives that scenario. Producing a valid
template or bundle is artifact validation only; it is not a JetBrains smoke
test.
