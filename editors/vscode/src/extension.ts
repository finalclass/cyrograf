import * as vscode from "vscode";
import {
  LanguageClient,
  LanguageClientOptions,
  ServerOptions,
  TransportKind,
} from "vscode-languageclient/node";
import {
  createPreviewHighlighter,
  cyrografFencePlugin,
  type MarkdownItLike,
  type PreviewHighlighter,
} from "./markdown";

let client: LanguageClient | undefined;

function serverOptions(): ServerOptions {
  const configuration = vscode.workspace.getConfiguration("cyrograf");
  const command = configuration.get<string>("path", "cyrograf");
  const options = { command, args: ["lsp", "--stdio"], transport: TransportKind.stdio };
  return { run: options, debug: options };
}

function clientOptions(): LanguageClientOptions {
  const watcher = vscode.workspace.createFileSystemWatcher("**/*.cyrograf");
  return {
    documentSelector: [{ scheme: "file", language: "cyrograf" }],
    synchronize: { fileEvents: watcher },
    outputChannelName: "Cyrograf",
  };
}

async function startClient(context: vscode.ExtensionContext): Promise<void> {
  const next = new LanguageClient(
    "cyrograf",
    "Cyrograf",
    serverOptions(),
    clientOptions(),
  );
  try {
    await next.start();
  } catch (error) {
    await next.stop().catch(() => undefined);
    const command = vscode.workspace.getConfiguration("cyrograf").get<string>("path", "cyrograf");
    void vscode.window.showErrorMessage(
      `Cyrograf: could not start '${command} lsp'. Install the cyrograf program ` +
        `or set the cyrograf.path setting. ${String(error)}`,
    );
    return;
  }
  client = next;
  context.subscriptions.push(next);
}

async function stopClient(): Promise<void> {
  const running = client;
  client = undefined;
  if (running) await running.stop();
}

function toArrayBuffer(bytes: Uint8Array): ArrayBuffer {
  return bytes.buffer.slice(
    bytes.byteOffset,
    bytes.byteOffset + bytes.byteLength,
  ) as ArrayBuffer;
}

async function loadPreviewHighlighter(
  context: vscode.ExtensionContext,
): Promise<PreviewHighlighter | undefined> {
  try {
    const grammar = context.asAbsolutePath("syntaxes/cyrograf.tmLanguage.json");
    const wasm = context.asAbsolutePath("dist/onig.wasm");
    const text = new TextDecoder().decode(await vscode.workspace.fs.readFile(vscode.Uri.file(grammar)));
    const bytes = await vscode.workspace.fs.readFile(vscode.Uri.file(wasm));
    return await createPreviewHighlighter(text, toArrayBuffer(bytes));
  } catch {
    return undefined;
  }
}

export async function activate(context: vscode.ExtensionContext): Promise<{
  extendMarkdownIt(md: MarkdownItLike): MarkdownItLike;
}> {
  await startClient(context);
  context.subscriptions.push(
    vscode.workspace.onDidChangeConfiguration(async (event) => {
      if (event.affectsConfiguration("cyrograf.path")) {
        await stopClient();
        await startClient(context);
      }
    }),
  );

  const highlighter = await loadPreviewHighlighter(context);
  return {
    extendMarkdownIt(md: MarkdownItLike): MarkdownItLike {
      return highlighter ? cyrografFencePlugin(highlighter)(md) : md;
    },
  };
}

export async function deactivate(): Promise<void> {
  await stopClient();
}