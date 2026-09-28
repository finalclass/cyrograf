// Protocol-level test for `cyrograf lsp`.
//
// It drives a real child process through public stdin/stdout frames, never the
// internal handler functions. It checks framing, lifecycle, full-document sync,
// diagnostics (including dependency refresh and UTF-16 ranges), formatting
// against the CLI, hover, definition, symbols and completion.

const bin = Deno.env.get("CYROGRAF_BIN") ?? "_build/default/bin/contract_cli.exe";

let failures = 0;

function check(label: string, condition: boolean): void {
  if (!condition) {
    failures += 1;
    console.error(`FAIL: ${label}`);
  }
}

function checkEqual(label: string, actual: unknown, expected: unknown): void {
  const a = JSON.stringify(actual);
  const b = JSON.stringify(expected);
  check(`${label} (got ${a}, want ${b})`, a === b);
}

const encoder = new TextEncoder();
const decoder = new TextDecoder();

function concat(a: Uint8Array, b: Uint8Array): Uint8Array {
  const out = new Uint8Array(a.length + b.length);
  out.set(a, 0);
  out.set(b, a.length);
  return out;
}

function uriOfPath(path: string): string {
  return "file://" + path.split("/").map(encodeURIComponent).join("/");
}

type Message = Record<string, unknown>;

class Conn {
  readonly writer: WritableStreamDefaultWriter<Uint8Array>;
  readonly reader: ReadableStreamDefaultReader<Uint8Array>;
  buffer = new Uint8Array(0);
  inbox: Message[] = [];
  waiters: Array<(message: Message) => void> = [];
  parseError: string | null = null;
  closed = false;

  constructor(
    reader: ReadableStreamDefaultReader<Uint8Array>,
    writer: WritableStreamDefaultWriter<Uint8Array>,
  ) {
    this.reader = reader;
    this.writer = writer;
    void this.pump();
  }

  async pump(): Promise<void> {
    try {
      while (true) {
        const { value, done } = await this.reader.read();
        if (done) break;
        if (value) {
          this.buffer = concat(this.buffer, value);
          this.drain();
        }
      }
    } catch (error) {
      this.parseError = String(error);
    } finally {
      this.closed = true;
    }
  }

  drain(): void {
    while (true) {
      const headerEnd = this.indexOfHeader();
      if (headerEnd < 0) return;
      const header = decoder.decode(this.buffer.slice(0, headerEnd));
      const match = /Content-Length:\s*(\d+)/i.exec(header);
      if (!match) {
        this.parseError = `missing Content-Length in ${JSON.stringify(header)}`;
        this.buffer = new Uint8Array(0);
        return;
      }
      const length = parseInt(match[1], 10);
      const bodyStart = headerEnd + 4;
      if (this.buffer.length < bodyStart + length) return;
      const body = decoder.decode(this.buffer.slice(bodyStart, bodyStart + length));
      this.buffer = this.buffer.slice(bodyStart + length);
      const message = JSON.parse(body) as Message;
      const waiter = this.waiters.shift();
      if (waiter) waiter(message);
      else this.inbox.push(message);
    }
  }

  indexOfHeader(): number {
    for (let i = 0; i + 3 < this.buffer.length; i += 1) {
      if (
        this.buffer[i] === 13 && this.buffer[i + 1] === 10 &&
        this.buffer[i + 2] === 13 && this.buffer[i + 3] === 10
      ) {
        return i;
      }
    }
    return -1;
  }

  next(timeout = 4000): Promise<Message> {
    const queued = this.inbox.shift();
    if (queued) return Promise.resolve(queued);
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.waiters = this.waiters.filter((waiter) => waiter !== wrapped);
        reject(new Error("timeout waiting for a message"));
      }, timeout);
      const wrapped = (message: Message) => {
        clearTimeout(timer);
        resolve(message);
      };
      this.waiters.push(wrapped);
    });
  }

  async waitFor(
    predicate: (message: Message) => boolean,
    timeout = 4000,
  ): Promise<Message> {
    const deadline = Date.now() + timeout;
    while (true) {
      const remaining = deadline - Date.now();
      if (remaining <= 0) throw new Error("timeout waiting for a matching message");
      const message = await this.next(remaining);
      if (predicate(message)) return message;
    }
  }

  send(message: Message): void {
    const body = encoder.encode(JSON.stringify(message));
    const header = encoder.encode(`Content-Length: ${body.length}\r\n\r\n`);
    void this.writer.write(concat(header, body));
  }

  sendRaw(bytes: Uint8Array): Promise<void> {
    return this.writer.write(bytes);
  }

  leftover(): string {
    return decoder.decode(this.buffer).trim();
  }

  clearInbox(): void {
    this.inbox = [];
  }
}

async function settle(session: Session): Promise<void> {
  await new Promise((resolve) => setTimeout(resolve, 30));
  session.conn.clearInbox();
}

class Session {
  readonly proc: Deno.ChildProcess;
  readonly conn: Conn;
  readonly exited: Promise<number>;

  constructor() {
    this.proc = new Deno.Command(bin, {
      args: ["lsp", "--stdio"],
      stdin: "piped",
      stdout: "piped",
      stderr: "null",
    }).spawn();
    this.conn = new Conn(this.proc.stdout.getReader(), this.proc.stdin.getWriter());
    this.exited = this.proc.status.then((status) => status.code);
  }

  async initialize(): Promise<Message> {
    this.conn.send({
      jsonrpc: "2.0",
      id: 1,
      method: "initialize",
      params: { capabilities: {} },
    });
    const response = await this.conn.waitFor((message) => message.id === 1);
    this.conn.send({ jsonrpc: "2.0", method: "initialized", params: {} });
    return response;
  }

  request(id: number, method: string, params: unknown): void {
    this.conn.send({ jsonrpc: "2.0", id, method, params });
  }

  notify(method: string, params: unknown): void {
    this.conn.send({ jsonrpc: "2.0", method, params });
  }

  didOpen(uri: string, text: string, version = 1, languageId = "cyrograf"): void {
    this.notify("textDocument/didOpen", {
      textDocument: { uri, languageId, version, text },
    });
  }

  didChange(uri: string, text: string, version: number): void {
    this.notify("textDocument/didChange", {
      textDocument: { uri, version },
      contentChanges: [{ text }],
    });
  }

  didClose(uri: string): void {
    this.notify("textDocument/didClose", { textDocument: { uri } });
  }

  diagnosticsFor(uri: string, timeout = 4000): Promise<Message> {
    return this.conn.waitFor(
      (message) =>
        message.method === "textDocument/publishDiagnostics" &&
        (message.params as Message).uri === uri,
      timeout,
    );
  }

  async closeInput(): Promise<void> {
    await this.conn.writer.close();
  }
}

async function writeFixture(directory: string, name: string, text: string) {
  await Deno.writeTextFile(`${directory}/${name}`, text);
}

async function runCli(args: string[], stdin?: string): Promise<{ code: number; stdout: string; stderr: string }> {
  const command = new Deno.Command(bin, {
    args,
    stdin: stdin === undefined ? "null" : "piped",
    stdout: "piped",
    stderr: "piped",
  });
  const child = command.spawn();
  if (stdin !== undefined) {
    const writer = child.stdin.getWriter();
    await writer.write(encoder.encode(stdin));
    await writer.close();
  }
  const output = await child.output();
  return {
    code: output.code,
    stdout: decoder.decode(output.stdout),
    stderr: decoder.decode(output.stderr),
  };
}

function errorOf(message: Message): number | null {
  const error = message.error as Message | undefined;
  if (!error) return null;
  return error.code as number;
}

function diagnosticsList(message: Message): Message[] {
  return (message.params as Message).diagnostics as Message[];
}

function codesOf(message: Message): string[] {
  return diagnosticsList(message).map((d) => d.code as string).sort();
}

// ── Lifecycle and framing ──────────────────────────────────────────

async function testLifecycle(): Promise<void> {
  const session = new Session();
  const response = await session.initialize();
  const capabilities = (response.result as Message).capabilities as Message;
  checkEqual("positionEncoding", capabilities.positionEncoding, "utf-16");
  checkEqual("sync change kind", (capabilities.textDocumentSync as Message).change, 1);
  checkEqual("sync openClose", (capabilities.textDocumentSync as Message).openClose, true);
  checkEqual("hover provider", capabilities.hoverProvider, true);
  checkEqual("definition provider", capabilities.definitionProvider, true);
  checkEqual("symbols provider", capabilities.documentSymbolProvider, true);
  check("completion provider", capabilities.completionProvider !== undefined);
  checkEqual("format provider", capabilities.documentFormattingProvider, true);
  check("no unimplemented rename", capabilities.renameProvider === undefined);
  check("server info", (response.result as Message).serverInfo !== undefined);

  session.request(2, "workspace/unknownMethod", {});
  const unknown = await session.conn.waitFor((m) => m.id === 2);
  checkEqual("unknown request error", errorOf(unknown), -32601);

  session.request(6, "textDocument/hover", { textDocument: { uri: "file:///x" }, position: { line: 0, character: 0 } });
  const unopened = await session.conn.waitFor((m) => m.id === 6);
  checkEqual("hover on an unopened document is null", unopened.result, null);

  session.notify("some/unknownNotification", {});
  session.request(3, "workspace/unknownRequest", {});
  const afterUnknown = await session.conn.waitFor((m) => m.id === 3);
  checkEqual("unknown request after unknown notification", errorOf(afterUnknown), -32601);

  session.notify("$/cancelRequest", { id: 2 });
  session.request(4, "textDocument/documentSymbol", { textDocument: { uri: "file:///x" } });
  const afterCancel = await session.conn.waitFor((m) => m.id === 4);
  checkEqual("cancel does not break session", afterCancel.id, 4);

  session.request(5, "shutdown", null);
  const shutdown = await session.conn.waitFor((m) => m.id === 5);
  checkEqual("shutdown result null", shutdown.result, null);
  session.notify("exit", null);
  checkEqual("exit after shutdown", await session.exited, 0);
  checkEqual("no foreign stdout bytes", session.conn.leftover(), "");
}

async function testExitWithoutShutdown(): Promise<void> {
  const session = new Session();
  await session.initialize();
  session.notify("exit", null);
  checkEqual("exit without shutdown", await session.exited, 1);
}

async function testEofEnds(): Promise<void> {
  const session = new Session();
  await session.initialize();
  await session.closeInput();
  checkEqual("EOF ends the process", await session.exited, 0);
}

async function testBeforeInitialize(): Promise<void> {
  const session = new Session();
  session.request(10, "textDocument/hover", { textDocument: { uri: "file:///x" }, position: { line: 0, character: 0 } });
  const response = await session.conn.waitFor((m) => m.id === 10);
  checkEqual("request before initialize", errorOf(response), -32002);
  session.notify("exit", null);
  await session.exited;
}

async function testFragmentedAndBatchedFrames(): Promise<void> {
  const session = new Session();
  const initialize = encoder.encode(JSON.stringify({ jsonrpc: "2.0", id: 20, method: "initialize", params: { capabilities: {} } }));
  const header = encoder.encode(`Content-Length: ${initialize.length}\r\n\r\n`);
  await session.conn.sendRaw(header);
  await session.conn.sendRaw(initialize.slice(0, 5));
  await session.conn.sendRaw(initialize.slice(5));
  const response = await session.conn.waitFor((m) => m.id === 20);
  check("fragmented frame answered", response.result !== undefined);

  const initialized = encoder.encode(JSON.stringify({ jsonrpc: "2.0", method: "initialized", params: {} }));
  const request = encoder.encode(JSON.stringify({ jsonrpc: "2.0", id: 21, method: "textDocument/documentSymbol", params: { textDocument: { uri: "file:///x" } } }));
  const batch = concat(
    concat(encoder.encode(`Content-Length: ${initialized.length}\r\n\r\n`), initialized),
    concat(encoder.encode(`Content-Length: ${request.length}\r\n\r\n`), request),
  );
  await session.conn.sendRaw(batch);
  const batched = await session.conn.waitFor((m) => m.id === 21);
  checkEqual("two frames in one write", batched.id, 21);

  session.notify("exit", null);
  await session.exited;
}

// ── Project diagnostics ────────────────────────────────────────────

async function testDiagnostics(): Promise<void> {
  const directory = await Deno.realPath(await Deno.makeTempDir({ prefix: "cyrograf-lsp-diag" }));
  await writeFixture(directory, "Common.cyrograf", "struct Thing {\n  id: String\n}\n");
  await writeFixture(directory, "Orders.cyrograf", "struct Order {\n  item: Common.Thing\n}\n");
  const commonUri = uriOfPath(`${directory}/Common.cyrograf`);
  const ordersUri = uriOfPath(`${directory}/Orders.cyrograf`);

  const session = new Session();
  await session.initialize();

  const bad = "struct Order {\n  item: Common.Missing\n}\n";
  session.didOpen(ordersUri, bad, 1);
  const first = await session.diagnosticsFor(ordersUri);
  check("unsaved error diagnosed", codesOf(first).includes("UnresolvedReference"));
  check("diagnostics carry the document version", (first.params as Message).version !== undefined);

  await settle(session);
  session.didChange(ordersUri, "struct Order {\n  item: Common.Thing\n}\n", 2);
  const fixed = await session.diagnosticsFor(ordersUri);
  checkEqual("error cleared", diagnosticsList(fixed), []);

  await settle(session);
  session.didOpen(commonUri, "struct Thing {\n  id: String\n}\n", 1);
  await session.diagnosticsFor(commonUri);
  await settle(session);
  session.didChange(commonUri, "struct Other {\n  id: String\n}\n", 2);
  const dependency = await session.diagnosticsFor(ordersUri);
  check("dependency change refreshes open dependent", codesOf(dependency).includes("UnresolvedReference"));

  await settle(session);
  session.didClose(commonUri);
  const closed = await session.diagnosticsFor(commonUri);
  checkEqual("close clears diagnostics", diagnosticsList(closed), []);

  // A brand new file that is not on disk participates in the project: the
// reference is unresolved first and clears once the new buffer is opened.
  await settle(session);
  session.didChange(ordersUri, "struct Order {\n  item: Copies.Thing\n}\n", 3);
  const unresolved = await session.diagnosticsFor(ordersUri);
  check("unresolved before the new file opens", codesOf(unresolved).includes("UnresolvedReference"));

  await settle(session);
  const copiesUri = uriOfPath(`${directory}/Copies.cyrograf`);
  session.didOpen(copiesUri, "struct Thing {\n  id: String\n}\n", 1);
  const resolved = await session.diagnosticsFor(ordersUri);
  checkEqual("new unsaved file participates in the project", diagnosticsList(resolved), []);

  session.notify("exit", null);
  await session.exited;
  await Deno.remove(directory, { recursive: true });
}

async function testEditorLockFileIgnored(): Promise<void> {
  const directory = await Deno.realPath(await Deno.makeTempDir({ prefix: "cyrograf-lsp-lock" }));
  await writeFixture(directory, "Common.cyrograf", "struct Thing {\n  id: String\n}\n");
  await writeFixture(directory, "Orders.cyrograf", "struct Order {\n  item: Common.Thing\n}\n");
  await Deno.symlink("user@host.12345:67890", `${directory}/.#Orders.cyrograf`);

  const session = new Session();
  await session.initialize();
  const ordersUri = uriOfPath(`${directory}/Orders.cyrograf`);
  session.didOpen(ordersUri, "struct Order {\n  item: Common.Missing\n}\n", 1);
  const first = await session.diagnosticsFor(ordersUri);
  check(
    "an editor lock file does not suppress diagnostics",
    codesOf(first).includes("UnresolvedReference"),
  );

  session.notify("exit", null);
  await session.exited;
  await Deno.remove(directory, { recursive: true });
}

async function testOlderVersionIgnored(): Promise<void> {
  const directory = await Deno.realPath(await Deno.makeTempDir({ prefix: "cyrograf-lsp-version" }));
  await writeFixture(directory, "A.cyrograf", "struct A {\n  x: String\n}\n");
  const uri = uriOfPath(`${directory}/A.cyrograf`);
  const session = new Session();
  await session.initialize();

  session.didOpen(uri, "struct A {\n  x: String\n}\n", 1);
  await session.diagnosticsFor(uri);
  session.didChange(uri, "struct A {\n  x: Missing\n}\n", 3);
  const current = await session.diagnosticsFor(uri);
  check("newer version diagnosed", codesOf(current).includes("UnresolvedReference"));
  await settle(session);
  session.didChange(uri, "struct A {\n  x: String\n}\n", 2);
  session.request(30, "textDocument/documentSymbol", { textDocument: { uri } });
  let sawStale = false;
  const response = await session.conn.waitFor((m) => {
    if (m.method === "textDocument/publishDiagnostics") {
      if (codesOf(m).length === 0) sawStale = true;
    }
    return m.id === 30;
  });
  check("stale version did not produce a fresh clean publication and request answered", response.id === 30 && !sawStale);

  session.notify("exit", null);
  await session.exited;
  await Deno.remove(directory, { recursive: true });
}

async function testClosedFileRefreshedByWatcher(): Promise<void> {
  const directory = await Deno.realPath(await Deno.makeTempDir({ prefix: "cyrograf-lsp-watch" }));
  await writeFixture(directory, "Base.cyrograf", "struct Base {\n  id: String\n}\n");
  await writeFixture(directory, "App.cyrograf", "struct App {\n  base: Base\n}\n");
  const appUri = uriOfPath(`${directory}/App.cyrograf`);
  const baseUri = uriOfPath(`${directory}/Base.cyrograf`);
  const session = new Session();
  await session.initialize();

  session.didOpen(appUri, "struct App {\n  base: Base\n}\n", 1);
  await session.diagnosticsFor(appUri);

  await writeFixture(directory, "Base.cyrograf", "struct Renamed {\n  id: String\n}\n");
  await settle(session);
  session.notify("workspace/didChangeWatchedFiles", { changes: [{ uri: baseUri, type: 2 }] });
  const refreshed = await session.diagnosticsFor(appUri);
  check("closed file change visible after an event", codesOf(refreshed).includes("UnresolvedReference"));

  session.notify("exit", null);
  await session.exited;
  await Deno.remove(directory, { recursive: true });
}

async function testIndependentDirectories(): Promise<void> {
  const first = await Deno.realPath(await Deno.makeTempDir({ prefix: "cyrograf-lsp-one" }));
  const second = await Deno.realPath(await Deno.makeTempDir({ prefix: "cyrograf-lsp-two" }));
  await writeFixture(first, "Shared.cyrograf", "struct Shared {\n  id: String\n}\n");
  await writeFixture(second, "Client.cyrograf", "struct Client {\n  s: Shared\n}\n");
  const clientUri = uriOfPath(`${second}/Client.cyrograf`);
  const session = new Session();
  await session.initialize();
  session.didOpen(clientUri, "struct Client {\n  s: Shared\n}\n", 1);
  const diagnostics = await session.diagnosticsFor(clientUri);
  check("projects do not merge across directories", codesOf(diagnostics).includes("UnresolvedReference"));
  session.notify("exit", null);
  await session.exited;
  await Deno.remove(first, { recursive: true });
  await Deno.remove(second, { recursive: true });
}

async function testUriWithSpaces(): Promise<void> {
  const directory = await Deno.realPath(await Deno.makeTempDir({ prefix: "cyrograf lsp space" }));
  await writeFixture(directory, "Space.cyrograf", "struct Space {\n  id: String\n}\n");
  const uri = uriOfPath(`${directory}/Space.cyrograf`);
  const session = new Session();
  await session.initialize();
  session.didOpen(uri, "struct Space {\n  id: String\n}\n", 1);
  const diagnostics = await session.diagnosticsFor(uri);
  checkEqual("URI with spaces resolves", diagnosticsList(diagnostics), []);
  session.request(40, "textDocument/documentSymbol", { textDocument: { uri } });
  const symbols = await session.conn.waitFor((m) => m.id === 40);
  const names = ((symbols.result as Message[]) ?? []).map((s) => s.name);
  check("symbols found under spaced URI", names.includes("Space"));
  session.notify("exit", null);
  await session.exited;
  await Deno.remove(directory, { recursive: true });
}

// ── Features ───────────────────────────────────────────────────────

const FEATURE_SOURCES: Record<string, string> = {
  "Common.cyrograf": "struct Thing {\n  id: String\n}\n",
  "Orders.cyrograf": [
    "struct Line {",
    "  sku: String",
    "  item: Common.Thing",
    "}",
    "",
    "variant Status {",
    "  Ready",
    "  Failed(Line)",
    "}",
    "",
    "struct Order {",
    "  status: Status",
    "}",
    "",
    "rpc place(Order) -> Status",
    "",
  ].join("\n"),
};

async function featureSession(): Promise<{ session: Session; directory: string; ordersUri: string; commonUri: string }> {
  const directory = await Deno.realPath(await Deno.makeTempDir({ prefix: "cyrograf-lsp-feat" }));
  for (const [name, text] of Object.entries(FEATURE_SOURCES)) await writeFixture(directory, name, text);
  const session = new Session();
  await session.initialize();
  const ordersUri = uriOfPath(`${directory}/Orders.cyrograf`);
  const commonUri = uriOfPath(`${directory}/Common.cyrograf`);
  session.didOpen(ordersUri, FEATURE_SOURCES["Orders.cyrograf"], 1);
  await session.diagnosticsFor(ordersUri);
  return { session, directory, ordersUri, commonUri };
}

async function testHoverAndSymbols(): Promise<void> {
  const { session, directory, ordersUri } = await featureSession();

  session.request(50, "textDocument/hover", {
    textDocument: { uri: ordersUri },
    position: { line: 0, character: 8 }, // `Line`
  });
  const structHover = await session.conn.waitFor((m) => m.id === 50);
  const structText = ((structHover.result as Message)?.contents as Message)?.value as string;
  check("hover struct", typeof structText === "string" && structText.includes("struct Line"));

  session.request(51, "textDocument/hover", {
    textDocument: { uri: ordersUri },
    position: { line: 1, character: 3 }, // `sku`
  });
  const fieldHover = await session.conn.waitFor((m) => m.id === 51);
  const fieldText = ((fieldHover.result as Message)?.contents as Message)?.value as string;
  check("hover field type", typeof fieldText === "string" && fieldText.includes("String"));

  session.request(52, "textDocument/documentSymbol", { textDocument: { uri: ordersUri } });
  const symbols = await session.conn.waitFor((m) => m.id === 52);
  const names = ((symbols.result as Message[]) ?? []).map((s) => s.name);
  for (const expected of ["Line", "sku", "item", "Status", "Ready", "Failed", "Order", "place"]) {
    check(`symbol ${expected}`, names.includes(expected));
  }

  session.notify("exit", null);
  await session.exited;
  await Deno.remove(directory, { recursive: true });
}

async function testDefinitionAndCompletion(): Promise<void> {
  const { session, directory, ordersUri, commonUri } = await featureSession();

  session.request(60, "textDocument/definition", {
    textDocument: { uri: ordersUri },
    position: { line: 2, character: 10 }, // `Common.Thing`
  });
  const definition = await session.conn.waitFor((m) => m.id === 60);
  checkEqual("qualified definition target", (definition.result as Message).uri, commonUri);

  session.request(61, "textDocument/definition", {
    textDocument: { uri: ordersUri },
    position: { line: 11, character: 11 }, // `Status` field
  });
  const localDefinition = await session.conn.waitFor((m) => m.id === 61);
  checkEqual("local definition target", (localDefinition.result as Message).uri, ordersUri);

  session.request(62, "textDocument/completion", {
    textDocument: { uri: ordersUri },
    position: { line: 2, character: 11 }, // inside the type position
  });
  const completion = await session.conn.waitFor((m) => m.id === 62);
  const labels = ((completion.result as Message).items as Message[]).map((item) => item.label as string);
  for (const expected of ["String", "Int", "Line", "Common.Thing"]) {
    check(`completion ${expected}`, labels.includes(expected));
  }

  const moduleText = "struct M {\n  x: Common.\n}\n";
  session.didChange(ordersUri, moduleText, 2);
  await session.diagnosticsFor(ordersUri);
  session.request(63, "textDocument/completion", {
    textDocument: { uri: ordersUri },
    position: { line: 1, character: 12 }, // right after `Common.`
  });
  const moduleCompletion = await session.conn.waitFor((m) => m.id === 63);
  const moduleLabels = ((moduleCompletion.result as Message).items as Message[]).map((item) => item.label as string);
  check("completion after module dot", moduleLabels.includes("Thing"));

  session.notify("exit", null);
  await session.exited;
  await Deno.remove(directory, { recursive: true });
}

async function testFormattingMatchesCli(): Promise<void> {
  const directory = await Deno.realPath(await Deno.makeTempDir({ prefix: "cyrograf-lsp-format" }));
  const messy = "struct   A{x:String;y?:Int}\n";
  await writeFixture(directory, "A.cyrograf", messy);
  const uri = uriOfPath(`${directory}/A.cyrograf`);
  const session = new Session();
  await session.initialize();
  session.didOpen(uri, messy, 1);
  await session.diagnosticsFor(uri);

  session.request(70, "textDocument/formatting", {
    textDocument: { uri },
    options: { tabSize: 4, insertSpaces: false },
  });
  const formatting = await session.conn.waitFor((m) => m.id === 70);
  const edits = formatting.result as Message[];
  checkEqual("formatting returns one edit", edits.length, 1);
  const formatted = edits[0].newText as string;

  const cli = await runCli(["format", "--stdin", "--filename", "A.cyrograf"], messy);
  checkEqual("formatter matches CLI", formatted, cli.stdout);
  const onDisk = await Deno.readTextFile(`${directory}/A.cyrograf`);
  checkEqual("LSP formatting does not write disk", onDisk, messy);

  const editRange = edits[0].range as Message;
  checkEqual("edit covers whole document", (editRange.start as Message).line, 0);

  // UTF-16 range end with a non-BMP code point.
  const emoji = "struct B {}\n// \u{1F600}";
  const emojiUri = uriOfPath(`${directory}/B.cyrograf`);
  session.didOpen(emojiUri, emoji, 1);
  await session.diagnosticsFor(emojiUri);
  session.request(71, "textDocument/formatting", { textDocument: { uri: emojiUri }, options: {} });
  const emojiFormat = await session.conn.waitFor((m) => m.id === 71);
  const emojiRange = (emojiFormat.result as Message[])[0].range as Message;
  checkEqual("non-BMP end line", (emojiRange.end as Message).line, 1);
  checkEqual("non-BMP counts two UTF-16 units", (emojiRange.end as Message).character, 5);

  // A syntax error yields a request error, not a partial edit.
  const brokenUri = uriOfPath(`${directory}/Broken.cyrograf`);
  session.didOpen(brokenUri, "struct Broken {\n", 1);
  await session.diagnosticsFor(brokenUri);
  session.request(72, "textDocument/formatting", { textDocument: { uri: brokenUri }, options: {} });
  const broken = await session.conn.waitFor((m) => m.id === 72);
  checkEqual("syntax error blocks formatter", errorOf(broken), -32803);

  session.notify("exit", null);
  await session.exited;
  await Deno.remove(directory, { recursive: true });
}

async function testCrlfDiagnostics(): Promise<void> {
  const directory = await Deno.realPath(await Deno.makeTempDir({ prefix: "cyrograf-lsp-crlf" }));
  await writeFixture(directory, "A.cyrograf", "struct A {\r\n  x: String\r\n}\r\n");
  const uri = uriOfPath(`${directory}/A.cyrograf`);
  const session = new Session();
  await session.initialize();
  const text = "struct A {\r\n  x: Missing\r\n}\r\n";
  session.didOpen(uri, text, 1);
  const diagnostics = await session.diagnosticsFor(uri);
  const first = diagnosticsList(diagnostics)[0];
  const range = first.range as Message;
  checkEqual("CRLF error line", (range.start as Message).line, 1);
  checkEqual("CRLF error character", (range.start as Message).character, 5);
  session.notify("exit", null);
  await session.exited;
  await Deno.remove(directory, { recursive: true });
}

async function testDiagnosticsMatchCli(): Promise<void> {
  const directory = await Deno.realPath(await Deno.makeTempDir({ prefix: "cyrograf-lsp-cli" }));
  const source = "struct A {\n  x: Missing\n  y: String\n}\n";
  await writeFixture(directory, "A.cyrograf", source);
  const uri = uriOfPath(`${directory}/A.cyrograf`);

  const session = new Session();
  await session.initialize();
  session.didOpen(uri, source, 1);
  const diagnostics = await session.diagnosticsFor(uri);
  const lspCodes = codesOf(diagnostics);

  const cli = await runCli(["check", directory]);
  const cliCodes = [...cli.stderr.matchAll(/\b([A-Z][A-Za-z]+):/g)].map((m) => m[1]).sort();
  check("CLI check fails on the same source", cli.code === 1);
  check("LSP and CLI agree on codes", JSON.stringify(lspCodes) === JSON.stringify([...new Set(cliCodes)].sort()));

  session.notify("exit", null);
  await session.exited;
  await Deno.remove(directory, { recursive: true });
}

// The same target-name collision must surface through the real CLI (check and
// build) and the LSP session. The LSP analyzes the unsaved buffer: it reports
// the collision while the on-disk file still has it and clears the diagnostic
// once the buffer is fixed, even though the disk copy is unchanged. CLI and LSP
// agree on the diagnostic code; the CLI adds a schema path while the LSP points
// the diagnostic at the document with an empty range (its location model).
async function testCollisionDiagnostics(): Promise<void> {
  const directory = await Deno.realPath(await Deno.makeTempDir({ prefix: "cyrograf-lsp-collision" }));
  const collision = "struct M {\n  owner_id: String\n  owner_i_d: String\n}\n";
  const fixed = "struct M {\n  owner_id: String\n  owner_name: String\n}\n";
  await writeFixture(directory, "M.cyrograf", collision);
  const uri = uriOfPath(`${directory}/M.cyrograf`);

  const cliCheck = await runCli(["check", directory]);
  const cliBuild = await runCli(["build", directory, "--output", `${directory}/out`, "--targets", "go"]);
  check("CLI check rejects the collision", cliCheck.code === 1);
  check("CLI build rejects the collision", cliBuild.code === 1);
  check("CLI check reports NameCollision", cliCheck.stderr.includes("NameCollision"));
  check("CLI identifies the colliding names", cliCheck.stderr.includes("owner_id") && cliCheck.stderr.includes("owner_i_d"));
  check("CLI presents the schema path", /\bM\.M:\s+NameCollision:/.test(cliCheck.stderr));
  check("no artifact after a failed build", !(await Deno.stat(`${directory}/out`).then(() => true).catch(() => false)));

  const session = new Session();
  await session.initialize();
  session.didOpen(uri, collision, 1);
  const reported = await session.diagnosticsFor(uri);
  const diagnostic = diagnosticsList(reported).find((d) => d.code === "NameCollision") as Message | undefined;
  check("LSP reports the collision from the unsaved buffer", diagnostic !== undefined);
  check("LSP and CLI agree on the code", diagnostic?.code === "NameCollision");
  check(
    "LSP identifies the colliding names",
    typeof diagnostic?.message === "string" &&
      (diagnostic.message as string).includes("owner_id") &&
      (diagnostic.message as string).includes("owner_i_d"),
  );
  check("LSP attributes the collision to the document", (reported.params as Message).uri === uri);

  await settle(session);
  session.didChange(uri, fixed, 2);
  const cleared = await session.diagnosticsFor(uri);
  checkEqual("LSP clears the collision after the buffer is fixed", diagnosticsList(cleared), []);

  session.notify("exit", null);
  await session.exited;
  await Deno.remove(directory, { recursive: true });
}

async function testPythonCollisionDiagnostics(): Promise<void> {
  const directory = await Deno.realPath(await Deno.makeTempDir({ prefix: "cyrograf-lsp-python" }));
  const collision = "struct M {\n  to_drut: String\n}\n";
  const fixed = "struct M {\n  owner_id: String\n}\n";
  await writeFixture(directory, "M.cyrograf", collision);
  const uri = uriOfPath(`${directory}/M.cyrograf`);

  const goCheck = await runCli(["check", directory, "--targets", "go"]);
  check("a target without the Python member stays valid", goCheck.code === 0);
  const pythonCheck = await runCli(["check", directory, "--targets", "python"]);
  const pythonBuild = await runCli([
    "build",
    directory,
    "--output",
    `${directory}/out`,
    "--targets",
    "python",
  ]);
  check("Python check rejects the reserved member", pythonCheck.code === 1);
  check("Python build rejects the reserved member", pythonBuild.code === 1);
  check("Python check reports NameCollision", pythonCheck.stderr.includes("NameCollision"));
  check("Python check names the reserved member", pythonCheck.stderr.includes("to_drut"));
  check("no Python artifact after a failed build",
    !(await Deno.stat(`${directory}/out`).then(() => true).catch(() => false)));

  const session = new Session();
  await session.initialize();
  session.didOpen(uri, collision, 1);
  const reported = await session.diagnosticsFor(uri);
  const diagnostic = diagnosticsList(reported).find((d) => d.code === "NameCollision") as Message | undefined;
  check("LSP reports the Python collision from the unsaved buffer", diagnostic !== undefined);
  await settle(session);
  session.didChange(uri, fixed, 2);
  const cleared = await session.diagnosticsFor(uri);
  checkEqual("LSP clears the Python collision after the buffer is fixed", diagnosticsList(cleared), []);

  session.notify("exit", null);
  await session.exited;
  await Deno.remove(directory, { recursive: true });
}

async function testJavaCollisionDiagnostics(): Promise<void> {
  const directory = await Deno.realPath(await Deno.makeTempDir({ prefix: "cyrograf-lsp-java" }));
  const collision = "struct M {\n  hash_code: String\n}\n";
  const fixed = "struct M {\n  owner_id: String\n}\n";
  await writeFixture(directory, "M.cyrograf", collision);
  const uri = uriOfPath(`${directory}/M.cyrograf`);

  const goCheck = await runCli(["check", directory, "--targets", "go"]);
  check("a target without the Java member stays valid", goCheck.code === 0);
  const javaCheck = await runCli(["check", directory, "--targets", "java"]);
  const javaBuild = await runCli([
    "build",
    directory,
    "--output",
    `${directory}/out`,
    "--targets",
    "java",
  ]);
  check("Java check rejects the reserved member", javaCheck.code === 1);
  check("Java build rejects the reserved member", javaBuild.code === 1);
  check("Java check reports NameCollision", javaCheck.stderr.includes("NameCollision"));
  check("Java check names the reserved member", javaCheck.stderr.includes("hash_code"));
  check("no Java artifact after a failed build",
    !(await Deno.stat(`${directory}/out`).then(() => true).catch(() => false)));

  const session = new Session();
  await session.initialize();
  session.didOpen(uri, collision, 1);
  const reported = await session.diagnosticsFor(uri);
  const diagnostic = diagnosticsList(reported).find((d) => d.code === "NameCollision") as Message | undefined;
  check("LSP reports the Java collision from the unsaved buffer", diagnostic !== undefined);
  await settle(session);
  session.didChange(uri, fixed, 2);
  const cleared = await session.diagnosticsFor(uri);
  checkEqual("LSP clears the Java collision after the buffer is fixed", diagnosticsList(cleared), []);

  session.notify("exit", null);
  await session.exited;
  await Deno.remove(directory, { recursive: true });
}

async function testCsharpCollisionDiagnostics(): Promise<void> {
  const directory = await Deno.realPath(await Deno.makeTempDir({ prefix: "cyrograf-lsp-csharp" }));
  const collision = "struct M {\n  to_drut: String\n}\n";
  const fixed = "struct M {\n  owner_id: String\n}\n";
  await writeFixture(directory, "M.cyrograf", collision);
  const uri = uriOfPath(`${directory}/M.cyrograf`);

  const goCheck = await runCli(["check", directory, "--targets", "go"]);
  check("a target without the C# member stays valid", goCheck.code === 0);
  const csharpCheck = await runCli(["check", directory, "--targets", "csharp"]);
  const csharpBuild = await runCli([
    "build",
    directory,
    "--output",
    `${directory}/out`,
    "--targets",
    "csharp",
  ]);
  check("C# check rejects the reserved member", csharpCheck.code === 1);
  check("C# build rejects the reserved member", csharpBuild.code === 1);
  check("C# check reports NameCollision", csharpCheck.stderr.includes("NameCollision"));
  check("C# check names the reserved member", csharpCheck.stderr.includes("to_drut"));
  check("no C# artifact after a failed build",
    !(await Deno.stat(`${directory}/out`).then(() => true).catch(() => false)));

  const session = new Session();
  await session.initialize();
  session.didOpen(uri, collision, 1);
  const reported = await session.diagnosticsFor(uri);
  const diagnostic = diagnosticsList(reported).find((d) => d.code === "NameCollision") as Message | undefined;
  check("LSP reports the C# collision from the unsaved buffer", diagnostic !== undefined);
  await settle(session);
  session.didChange(uri, fixed, 2);
  const cleared = await session.diagnosticsFor(uri);
  checkEqual("LSP clears the C# collision after the buffer is fixed", diagnosticsList(cleared), []);

  session.notify("exit", null);
  await session.exited;
  await Deno.remove(directory, { recursive: true });
}

async function testRustCollisionDiagnostics(): Promise<void> {
  const directory = await Deno.realPath(await Deno.makeTempDir({ prefix: "cyrograf-lsp-rust" }));
  const collision = "struct M {\n  encode_value: String\n}\n";
  const fixed = "struct M {\n  owner_id: String\n}\n";
  await writeFixture(directory, "M.cyrograf", collision);
  const uri = uriOfPath(`${directory}/M.cyrograf`);

  const goCheck = await runCli(["check", directory, "--targets", "go"]);
  check("a target without the Rust member stays valid", goCheck.code === 0);
  const rustCheck = await runCli(["check", directory, "--targets", "rust"]);
  const rustBuild = await runCli([
    "build",
    directory,
    "--output",
    `${directory}/out`,
    "--targets",
    "rust",
  ]);
  check("Rust check rejects the reserved member", rustCheck.code === 1);
  check("Rust build rejects the reserved member", rustBuild.code === 1);
  check("Rust check reports NameCollision", rustCheck.stderr.includes("NameCollision"));
  check("Rust check names the reserved member", rustCheck.stderr.includes("encode_value"));
  check("no Rust artifact after a failed build",
    !(await Deno.stat(`${directory}/out`).then(() => true).catch(() => false)));

  const session = new Session();
  await session.initialize();
  session.didOpen(uri, collision, 1);
  const reported = await session.diagnosticsFor(uri);
  const diagnostic = diagnosticsList(reported).find((d) => d.code === "NameCollision") as Message | undefined;
  check("LSP reports the Rust collision from the unsaved buffer", diagnostic !== undefined);
  await settle(session);
  session.didChange(uri, fixed, 2);
  const cleared = await session.diagnosticsFor(uri);
  checkEqual("LSP clears the Rust collision after the buffer is fixed", diagnosticsList(cleared), []);

  session.notify("exit", null);
  await session.exited;
  await Deno.remove(directory, { recursive: true });
}

async function testRepeatedSessionsDoNotShareOverlay(): Promise<void> {
  const directory = await Deno.realPath(await Deno.makeTempDir({ prefix: "cyrograf-lsp-reset" }));
  const path = `${directory}/New.cyrograf`;
  const uri = uriOfPath(path);

  const first = new Session();
  await first.initialize();
  first.didOpen(uri, "struct New {\n  x: String\n}\n", 1);
  const opened = await first.diagnosticsFor(uri);
  checkEqual("first session new file clean", diagnosticsList(opened), []);
  first.notify("exit", null);
  await first.exited;

  const second = new Session();
  await second.initialize();
  second.didOpen(uri, "struct New {\n  x: Other\n}\n", 1);
  const reopened = await second.diagnosticsFor(uri);
  check("second session uses its own overlay", codesOf(reopened).includes("UnresolvedReference"));
  second.notify("exit", null);
  await second.exited;
  await Deno.remove(directory, { recursive: true });
}

async function testIncompleteDocument(): Promise<void> {
  const directory = await Deno.realPath(await Deno.makeTempDir({ prefix: "cyrograf-lsp-partial" }));
  const uri = uriOfPath(`${directory}/Partial.cyrograf`);
  const session = new Session();
  await session.initialize();
  const partial = "struct Kept {\n  id: String\n}\n\nstruct Broken {\n";
  session.didOpen(uri, partial, 1);
  await session.diagnosticsFor(uri);
  session.request(80, "textDocument/documentSymbol", { textDocument: { uri } });
  const symbols = await session.conn.waitFor((m) => m.id === 80);
  const names = ((symbols.result as Message[]) ?? []).map((s) => s.name);
  check("recovered symbols on incomplete document", names.includes("Kept"));
  session.request(81, "textDocument/hover", {
    textDocument: { uri },
    position: { line: 1, character: 3 },
  });
  const hover = await session.conn.waitFor((m) => m.id === 81);
  check("hover does not crash on incomplete document", hover.id === 81);
  session.notify("exit", null);
  await session.exited;
  await Deno.remove(directory, { recursive: true });
}

async function main(): Promise<void> {
  await testLifecycle();
  await testExitWithoutShutdown();
  await testEofEnds();
  await testBeforeInitialize();
  await testFragmentedAndBatchedFrames();
  await testDiagnostics();
  await testEditorLockFileIgnored();
  await testOlderVersionIgnored();
  await testClosedFileRefreshedByWatcher();
  await testIndependentDirectories();
  await testUriWithSpaces();
  await testHoverAndSymbols();
  await testDefinitionAndCompletion();
  await testFormattingMatchesCli();
  await testCrlfDiagnostics();
  await testDiagnosticsMatchCli();
  await testCollisionDiagnostics();
  await testPythonCollisionDiagnostics();
  await testJavaCollisionDiagnostics();
  await testCsharpCollisionDiagnostics();
  await testRustCollisionDiagnostics();
  await testRepeatedSessionsDoNotShareOverlay();
  await testIncompleteDocument();

  if (failures === 0) console.log("all lsp protocol tests passed");
  else {
    console.error(`${failures} lsp test(s) failed`);
    Deno.exit(1);
  }
}

await main();