import * as assert from "assert";
import { execFileSync } from "child_process";
import * as fs from "fs";
import * as os from "os";
import * as path from "path";
import * as vscode from "vscode";
import MarkdownIt from "markdown-it";
import {
  createInjectionTokenizer,
  createPreviewHighlighter,
  cyrografFencePlugin,
  type MarkdownItLike,
} from "../markdown";

const extensionRoot = path.resolve(__dirname, "../../..");

function readText(relative: string): string {
  return fs.readFileSync(path.join(extensionRoot, relative), "utf8");
}

function readWasm(relative: string): ArrayBuffer {
  const bytes = fs.readFileSync(path.join(extensionRoot, relative));
  return bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
}

async function renderMarkdown(source: string): Promise<string> {
  const highlighter = await createPreviewHighlighter(
    readText("syntaxes/cyrograf.tmLanguage.json"),
    readWasm("dist/onig.wasm"),
  );
  const md = new MarkdownIt();
  cyrografFencePlugin(highlighter)(md as unknown as MarkdownItLike);
  return md.render(source);
}

function scopesOf(
  tokenizer: Awaited<ReturnType<typeof createInjectionTokenizer>>,
  text: string,
): string[][] {
  const lines = text.split("\n");
  let stack = tokenizer.tokenizeLine("", null).ruleStack;
  const result: string[][] = [];
  for (const line of lines) {
    const tokenized = tokenizer.tokenizeLine(line, stack);
    stack = tokenized.ruleStack;
    const scopes: string[] = [];
    for (const token of tokenized.tokens) {
      scopes.push(...token.scopes);
    }
    result.push(scopes);
  }
  return result;
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function waitForDiagnostics(
  uri: vscode.Uri,
  timeoutMs: number,
): Promise<vscode.Diagnostic[]> {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const diagnostics = vscode.languages.getDiagnostics(uri);
    if (diagnostics.length > 0) return diagnostics;
    await sleep(250);
  }
  return vscode.languages.getDiagnostics(uri);
}

async function waitForCondition(
  predicate: () => boolean,
  timeoutMs: number,
): Promise<boolean> {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    if (predicate()) return true;
    await sleep(250);
  }
  return predicate();
}

async function configureServer(): Promise<string> {
  const binary = process.env.CYROGRAF_BIN;
  assert.ok(binary, "CYROGRAF_BIN must point at the built cyrograf binary");
  assert.ok(fs.existsSync(binary), `cyrograf binary exists: ${binary}`);
  const wrapperDir = await fs.promises.mkdtemp(path.join(os.tmpdir(), "cyrograf ext "));
  const wrapper = path.join(wrapperDir, "cyrograf");
  await fs.promises.writeFile(wrapper, `#!/bin/sh\nexec "${binary}" "$@"\n`, { mode: 0o755 });
  const setting = vscode.workspace.getConfiguration("cyrograf");
  await setting.update("path", wrapper, vscode.ConfigurationTarget.Workspace);
  return binary;
}

suite("Cyrograf extension", () => {
  test("contributes the cyrograf language", async () => {
    const languages = await vscode.languages.getLanguages();
    assert.ok(languages.includes("cyrograf"), "cyrograf language is registered");
  });

  test("starts cyrograf lsp and publishes diagnostics", async function () {
    this.timeout(90000);
    const binary = process.env.CYROGRAF_BIN;
    assert.ok(binary, "CYROGRAF_BIN must point at the built cyrograf binary");
    assert.ok(fs.existsSync(binary), `cyrograf binary exists: ${binary}`);

    const wrapperDir = await fs.promises.mkdtemp(path.join(os.tmpdir(), "cyrograf ext "));
    const wrapper = path.join(wrapperDir, "cyrograf");
    await fs.promises.writeFile(wrapper, `#!/bin/sh\nexec "${binary}" "$@"\n`, { mode: 0o755 });

    const setting = vscode.workspace.getConfiguration("cyrograf");
    assert.strictEqual(setting.get<string>("path"), "cyrograf");
    await setting.update("path", wrapper, vscode.ConfigurationTarget.Workspace);

    const folder = vscode.workspace.workspaceFolders?.[0];
    assert.ok(folder, "a workspace folder is open");
    const uri = vscode.Uri.joinPath(folder.uri, "Orders.cyrograf");
    const document = await vscode.workspace.openTextDocument(uri);
    await vscode.window.showTextDocument(document);
    assert.strictEqual(document.languageId, "cyrograf");

    const diagnostics = await waitForDiagnostics(uri, 60000);
    assert.ok(diagnostics.length > 0, "the server published diagnostics");
    const codes = diagnostics.map((diagnostic) => String(diagnostic.code));
    assert.ok(codes.includes("UnresolvedReference"), `codes: ${codes.join(", ")}`);

    await setting.update("path", undefined, vscode.ConfigurationTarget.Workspace);
  });

  test("repairs, resolves a definition and formats through the server", async function () {
    this.timeout(120000);
    const binary = await configureServer();
    const folder = vscode.workspace.workspaceFolders?.[0];
    assert.ok(folder, "a workspace folder is open");
    const uri = vscode.Uri.joinPath(folder.uri, "Orders.cyrograf");
    const document = await vscode.workspace.openTextDocument(uri);
    const editor = await vscode.window.showTextDocument(document);

    await waitForDiagnostics(uri, 60000);

    const broken = "Common.Missing";
    const brokenStart = document.getText().indexOf(broken);
    assert.ok(brokenStart >= 0, "the fixture carries the unknown type");
    await editor.edit((builder) =>
      builder.replace(
        new vscode.Range(
          document.positionAt(brokenStart),
          document.positionAt(brokenStart + broken.length),
        ),
        "Common.Thing",
      ),
    );
    assert.ok(
      await waitForCondition(() => vscode.languages.getDiagnostics(uri).length === 0, 60000),
      "diagnostics cleared after the unsaved repair",
    );

    const reference = document.getText().indexOf("Common.Thing");
    assert.ok(reference >= 0, "the repaired reference is present");
    const locations = await vscode.commands.executeCommand<vscode.Location[]>(
      "vscode.executeDefinitionProvider",
      uri,
      document.positionAt(reference),
    );
    assert.ok(locations && locations.length > 0, "definition returned a location");
    assert.ok(
      locations.some((location) => location.uri.path.endsWith("Common.cyrograf")),
      `definition target: ${locations.map((location) => location.uri.toString()).join(", ")}`,
    );

    const expected = execFileSync(
      binary,
      ["format", "--stdin", "--filename", "Orders.cyrograf"],
      { input: document.getText(), encoding: "utf8" },
    );
    const edits = await vscode.commands.executeCommand<vscode.TextEdit[]>(
      "vscode.executeFormatDocumentProvider",
      uri,
      { tabSize: 2, insertSpaces: true },
    );
    assert.ok(edits && edits.length > 0, "the format provider returned edits");
    const workspaceEdit = new vscode.WorkspaceEdit();
    for (const edit of edits) workspaceEdit.replace(uri, edit.range, edit.newText);
    await vscode.workspace.applyEdit(workspaceEdit);
    assert.strictEqual(document.getText(), expected, "formatted text equals the CLI");

    await vscode.workspace
      .getConfiguration("cyrograf")
      .update("path", undefined, vscode.ConfigurationTarget.Workspace);
  });

  test("highlights cyrograf fences in the built-in Markdown preview", async function () {
    this.timeout(30000);
    const html = await renderMarkdown(
      [
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
      ].join("\n"),
    );
    assert.ok(html.includes("language-cyrograf"), "the fence is marked as cyrograf");
    assert.ok(html.includes("cy-comment"), "the comment is a token");
    assert.ok(html.includes("cy-keyword"), "struct is a keyword token");
    assert.ok(html.includes("cy-storage"), "string is a primitive token");
    assert.ok(html.includes("&lt;b&gt;&amp;"), "HTML in a comment is escaped");
    assert.ok(!html.includes("<b>"), "code text is not active HTML");
    assert.ok(html.includes("prose stays prose"), "prose after the block is rendered");
  });

  test("leaves other Markdown fences to the default renderer", async function () {
    this.timeout(30000);
    const html = await renderMarkdown("```json\n{\"a\": 1}\n```\n");
    assert.ok(html.includes("a"), "the other block is rendered");
    assert.ok(!html.includes("cy-keyword"), "no cyrograf token classes leak into other blocks");
  });

  test("tokenizes cyrograf fences in the Markdown editor grammar", async function () {
    this.timeout(30000);
    const markdownGrammar = path.join(
      vscode.env.appRoot,
      "extensions/markdown-basics/syntaxes/markdown.tmLanguage.json",
    );
    assert.ok(fs.existsSync(markdownGrammar), "the built-in Markdown grammar is present");
    const tokenizer = await createInjectionTokenizer(
      readText("syntaxes/cyrograf.tmLanguage.json"),
      readText("syntaxes/cyrograf.markdown.tmLanguage.json"),
      fs.readFileSync(markdownGrammar, "utf8"),
      "text.html.markdown",
      readWasm("dist/onig.wasm"),
    );
    const document = [
      "# Title",
      "",
      "```cyrograf",
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
    ].join("\n");
    const scopes = scopesOf(tokenizer, document);
    const has = (line: number, prefix: string): boolean =>
      scopes[line].some((scope) => scope.startsWith(prefix));

    assert.ok(has(3, "meta.embedded.block.cyrograf"), "the cyrograf fence embeds the native grammar");
    assert.ok(
      has(3, "keyword.other.declaration.cyrograf"),
      "struct is tokenized as a native declaration",
    );
    assert.ok(has(3, "entity.name.type.cyrograf"), "the message name uses the native type scope");
    assert.ok(!has(8, "meta.embedded.block.cyrograf"), "prose after the fence is back to Markdown");
    assert.ok(
      has(12, "meta.embedded.block.cyrograf"),
      "a shorter backtick run does not close a longer fence",
    );
    assert.ok(!has(17, "meta.embedded.block.cyrograf"), "another language block is not cyrograf");
  });
});