// Editor integration checks for `make test-editors`.
//
// The driver validates the shared TextMate grammar, the example project and
// the JetBrains artifacts, then runs the Emacs, Vim and VS Code integrations in
// their batch/headless or Extension Host mode. A missing tool is reported as
// BLOCKED, never as a skip or a success.

const root = new URL("../../", import.meta.url);
const editorsUrl = new URL("editors/", root);
const bin = Deno.env.get("CYROGRAF_BIN") ?? "_build/default/bin/contract_cli.exe";

const encoder = new TextEncoder();
const decoder = new TextDecoder();

let failures = 0;
let blocked = 0;

function pass(label: string): void {
  console.log(`PASS: ${label}`);
}

function fail(label: string, detail = ""): void {
  failures += 1;
  console.error(`FAIL: ${label}${detail ? ` (${detail})` : ""}`);
}

function block(label: string, reason: string): void {
  blocked += 1;
  console.error(`BLOCKED: ${label} (${reason})`);
}

function check(label: string, condition: boolean, detail = ""): void {
  if (condition) pass(label);
  else fail(label, detail);
}

function editorsPath(relative: string): string {
  return Deno.realPathSync(new URL(relative, editorsUrl));
}

async function run(
  command: string,
  args: string[],
  options: { cwd?: string; env?: Record<string, string> } = {},
): Promise<{ code: number; stdout: string; stderr: string }> {
  const process = new Deno.Command(command, {
    args,
    cwd: options.cwd,
    env: options.env,
    stdout: "piped",
    stderr: "piped",
  });
  const output = await process.output();
  return {
    code: output.code,
    stdout: decoder.decode(output.stdout),
    stderr: decoder.decode(output.stderr),
  };
}

async function commandExists(command: string): Promise<boolean> {
  const which = await run("which", [command]);
  return which.code === 0;
}

function findNewest(directory: string, prefix: string): string | null {
  let newest: { path: string; name: string } | null = null;
  try {
    for (const entry of Deno.readDirSync(directory)) {
      if (entry.isDirectory && entry.name.startsWith(prefix)) {
        if (!newest || entry.name > newest.name) {
          newest = { path: `${directory}/${entry.name}`, name: entry.name };
        }
      }
    }
  } catch (error) {
    if (!(error instanceof Deno.errors.NotFound)) throw error;
  }
  return newest?.path ?? null;
}

async function readJson(path: string): Promise<Record<string, unknown>> {
  return JSON.parse(decoder.decode(await Deno.readFile(path)));
}

function equalBytes(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false;
  for (let i = 0; i < a.length; i += 1) if (a[i] !== b[i]) return false;
  return true;
}

// ── Shared grammar and example ─────────────────────────────────────

async function testSharedGrammar(): Promise<void> {
  const canonical = await Deno.readFile(new URL("shared/cyrograf.tmLanguage.json", editorsUrl));
  const grammar = JSON.parse(decoder.decode(canonical)) as {
    scopeName?: string;
    fileTypes?: string[];
    repository?: Record<string, unknown>;
  };
  check("grammar scope name", grammar.scopeName === "source.cyrograf");
  check("grammar file type", (grammar.fileTypes ?? []).includes("cyrograf"));
  for (const rule of [
    "comments",
    "primitives",
    "declarations",
    "method-names",
    "field-names",
    "type-names",
    "operators",
    "punctuation",
  ]) {
    check(`grammar rule ${rule}`, grammar.repository?.[rule] !== undefined);
  }

  const copies = [
    "vscode/syntaxes/cyrograf.tmLanguage.json",
    "jetbrains/Cyrograf.tmBundle/Syntaxes/cyrograf.tmLanguage.json",
  ];
  for (const copy of copies) {
    const bytes = await Deno.readFile(new URL(copy, editorsUrl));
    check(`grammar copy matches source: ${copy}`, equalBytes(canonical, bytes));
  }

  const markdown = await Deno.readFile(
    new URL("shared/cyrograf.markdown.tmLanguage.json", editorsUrl),
  );
  const markdownGrammar = JSON.parse(decoder.decode(markdown)) as {
    scopeName?: string;
    injectionSelector?: string;
    patterns?: unknown[];
    repository?: Record<string, { patterns?: Array<{ include?: string }> }>;
  };
  check("markdown adapter scope name", markdownGrammar.scopeName === "markdown.cyrograf.codeblock");
  check("markdown adapter injects into markdown", markdownGrammar.injectionSelector === "L:text.html.markdown");
  const fence = markdownGrammar.repository?.["fenced-cyrograf"] as
    | { contentName?: string; patterns?: Array<{ include?: string }> }
    | undefined;
  check("markdown adapter embeds source.cyrograf", fence?.patterns?.some((p) => p.include === "source.cyrograf") === true);
  const markdownCopy = await Deno.readFile(
    new URL("vscode/syntaxes/cyrograf.markdown.tmLanguage.json", editorsUrl),
  );
  check("markdown adapter copy matches source", equalBytes(markdown, markdownCopy));
}

async function testExampleProject(): Promise<void> {
  const example = editorsPath("example");
  const result = await run(bin, ["check", example]);
  check("example project passes cyrograf check", result.code === 0, result.stderr.trim());
}

async function testNoShellComposition(): Promise<void> {
  const offenders: string[] = [];
  for await (const entry of walk(editorsUrl)) {
    if (!/\.(json|vim|el|ts|md)$/.test(entry.name)) continue;
    if (entry.name === "editors_test.ts") continue;
    const text = decoder.decode(await Deno.readFile(entry.url));
    if (/\bsh\s+-c\b/.test(text)) offenders.push(entry.url.pathname);
  }
  check("no editor configuration composes a shell command", offenders.length === 0, offenders.join(", "));
}

async function* walk(url: URL): AsyncGenerator<{ name: string; url: URL }> {
  for await (const entry of Deno.readDir(url)) {
    const child = new URL(entry.name + (entry.isDirectory ? "/" : ""), url);
    if (entry.isDirectory) {
      if (entry.name === "node_modules" || entry.name === "dist" || entry.name === "out") continue;
      yield* walk(child);
    } else {
      yield { name: entry.name, url: child };
    }
  }
}

// ── Emacs ──────────────────────────────────────────────────────────

function findEmacs(): string | null {
  const configured = Deno.env.get("CYROGRAF_EMACS_BIN");
  if (configured) return configured;
  const cached = `${Deno.env.get("HOME")}/.cache/cyrograf-editors/tools/emacs-30.1/bin/emacs`;
  try {
    if (Deno.statSync(cached).isFile) return cached;
  } catch (error) {
    if (!(error instanceof Deno.errors.NotFound)) throw error;
  }
  return null;
}

async function testEmacs(): Promise<void> {
  const cached = findEmacs();
  const emacs = cached ?? ((await commandExists("emacs")) ? "emacs" : null);
  if (!emacs) {
    block("emacs batch test", "emacs is not on PATH or in the editors cache");
    return;
  }
  const home = Deno.env.get("HOME");
  const elpa = `${home}/.cache/cyrograf-editors/elpa`;
  const eglot = findNewest(elpa, "eglot-");
  const env: Record<string, string> = {
    ...Deno.env.toObject(),
    CYROGRAF_EMACS_EGLOT_PATH: eglot ?? "",
    CYROGRAF_EMACS_MARKDOWN_PATH: elpa,
    CYROGRAF_EMACS_ELPA: elpa,
  };
  const result = await run(
    emacs,
    ["-Q", "--batch", "-l", editorsPath("emacs/test-batch.el")],
    { env },
  );
  const report = result.stdout.replace(/\n$/, "");
  if (report) console.log(report);
  if (result.stderr.trim()) console.error(result.stderr.trim());
  check("emacs batch checks passed", result.code === 0);

  const project = await Deno.realPath(await Deno.makeTempDir({ prefix: "cyrograf-emacs-" }));
  for (const name of ["Common.cyrograf", "Orders.cyrograf"]) {
    await Deno.copyFile(editorsPath(`example/${name}`), `${project}/${name}`);
  }
  const eglotEnv: Record<string, string> = {
    ...env,
    CYROGRAF_BIN: Deno.realPathSync(bin),
    CYROGRAF_EMACS_PROJECT: project,
  };
  const smoke = await run(
    emacs,
    ["-Q", "--batch", "-l", editorsPath("emacs/test-eglot.el")],
    { env: eglotEnv },
  );
  const smokeReport = smoke.stdout.replace(/\n$/, "");
  if (smokeReport) console.log(smokeReport);
  if (smoke.stderr.trim()) console.error(smoke.stderr.trim());
  check("emacs eglot smoke passed", smoke.code === 0);
  await Deno.remove(project, { recursive: true });
}

// ── Vim ────────────────────────────────────────────────────────────

async function testVim(): Promise<void> {
  if (!(await commandExists("vim"))) {
    block("vim headless test", "vim is not on PATH");
    return;
  }
  const out = await Deno.makeTempFile({ prefix: "cyrograf-vim-" });
  const env: Record<string, string> = {
    ...Deno.env.toObject(),
    CYROGRAF_VIM_OUT: out,
    CYROGRAF_VIM_FIXTURE: editorsPath("example/Orders.cyrograf"),
  };
  const result = await run(
    "vim",
    [
      "-N",
      "-u",
      "NONE",
      "-i",
      "NONE",
      "-es",
      "--cmd",
      `let g:editors = '${editorsUrl.pathname.replace(/\/$/, "")}'`,
      "-S",
      editorsPath("vim/test-headless.vim"),
    ],
    { env },
  );
  let report = "";
  try {
    report = (await Deno.readTextFile(out)).trim();
  } catch {
    report = "";
  }
  if (report) console.log(report);
  if (result.stderr.trim()) console.error(result.stderr.trim());
  check("vim headless checks produced a report", report.length > 0);
  check("vim headless checks passed", result.code === 0 && !report.includes("FAIL:"));
  await Deno.remove(out).catch(() => undefined);

  const plugin = `${Deno.env.get("HOME")}/.cache/cyrograf-editors/tools/yegappan-lsp`;
  try {
    Deno.statSync(`${plugin}/plugin/lsp.vim`);
  } catch {
    block("vim yegappan/lsp smoke", "yegappan/lsp is missing; run make editors-tools");
    return;
  }
  const project = await Deno.realPath(await Deno.makeTempDir({ prefix: "cyrograf-vim-" }));
  for (const name of ["Common.cyrograf", "Orders.cyrograf"]) {
    await Deno.copyFile(editorsPath(`example/${name}`), `${project}/${name}`);
  }
  const binDir = await Deno.makeTempDir({ prefix: "cyrograf vim bin " });
  const wrapper = `${binDir}/cyrograf`;
  await Deno.writeTextFile(
    wrapper,
    `#!/bin/sh\nexec "${Deno.realPathSync(bin)}" "$@"\n`,
  );
  await Deno.chmod(wrapper, 0o755);
  const lspOut = await Deno.makeTempFile({ prefix: "cyrograf-vim-lsp-" });
  const lspEnv: Record<string, string> = {
    ...Deno.env.toObject(),
    CYROGRAF_VIM_LSP_PLUGIN: plugin,
    CYROGRAF_VIM_LSP_BIN: wrapper,
    CYROGRAF_VIM_LSP_CLI_BIN: Deno.realPathSync(bin),
    CYROGRAF_VIM_LSP_PROJECT: project,
    CYROGRAF_VIM_LSP_OUT: lspOut,
  };
  const lspResult = await run(
    "vim",
    [
      "-N",
      "-u",
      "NONE",
      "-i",
      "NONE",
      "-es",
      "--cmd",
      `let g:editors = '${editorsUrl.pathname.replace(/\/$/, "")}'`,
      "-S",
      editorsPath("vim/test-lsp.vim"),
    ],
    { env: lspEnv },
  );
  let lspReport = "";
  try {
    lspReport = (await Deno.readTextFile(lspOut)).trim();
  } catch {
    lspReport = "";
  }
  if (lspReport) console.log(lspReport);
  if (lspResult.stderr.trim()) console.error(lspResult.stderr.trim());
  check("vim yegappan/lsp smoke produced a report", lspReport.includes("PASS:"));
  check(
    "vim yegappan/lsp smoke passed",
    lspResult.code === 0 && !lspReport.includes("FAIL:"),
  );
  await Deno.remove(project, { recursive: true }).catch(() => undefined);
  await Deno.remove(binDir, { recursive: true }).catch(() => undefined);
  await Deno.remove(lspOut).catch(() => undefined);
}

// ── Neovim ─────────────────────────────────────────────────────────

function findNeovim(): string | null {
  const cached = `${Deno.env.get("HOME")}/.cache/cyrograf-editors/tools/nvim-linux-x86_64/bin/nvim`;
  try {
    if (Deno.statSync(cached).isFile) return cached;
  } catch (error) {
    if (!(error instanceof Deno.errors.NotFound)) throw error;
  }
  return null;
}

async function testNeovim(): Promise<void> {
  const nvim = (await commandExists("nvim")) ? "nvim" : findNeovim();
  if (!nvim) {
    block("neovim headless test", "nvim is not on PATH or in the editors cache");
    return;
  }
  const project = await Deno.realPath(await Deno.makeTempDir({ prefix: "cyrograf-nvim-" }));
  for (const name of ["Common.cyrograf", "Orders.cyrograf"]) {
    await Deno.copyFile(editorsPath(`example/${name}`), `${project}/${name}`);
  }
  const version = await run(nvim, ["--version"]);
  console.log(version.stdout.split("\n")[0]);
  const env: Record<string, string> = {
    ...Deno.env.toObject(),
    CYROGRAF_EDITORS: Deno.realPathSync(editorsUrl),
    CYROGRAF_BIN: Deno.realPathSync(bin),
    CYROGRAF_NVIM_PROJECT: project,
  };
  const result = await run(
    nvim,
    ["--headless", "-l", editorsPath("neovim/test-headless.lua")],
    { env },
  );
  if (result.stdout.trim()) console.log(result.stdout.trim());
  if (result.stderr.trim()) console.error(result.stderr.trim());
  const report = `${result.stdout}\n${result.stderr}`;
  check("neovim headless checks produced a report", report.includes("PASS:"));
  check(
    "neovim headless checks passed",
    result.code === 0 && !report.includes("FAIL:"),
  );
  await Deno.remove(project, { recursive: true });
}

// ── VS Code ────────────────────────────────────────────────────────

async function testVSCode(): Promise<void> {
  const extension = editorsPath("vscode");
  let hasRunner = false;
  try {
    Deno.statSync(`${extension}/node_modules/.bin/vscode-test`);
    hasRunner = true;
  } catch {
    hasRunner = false;
  }
  if (!hasRunner) {
    block("vscode extension host test", "editors/vscode/node_modules is missing; run npm install there");
    return;
  }
  const npm = (await commandExists("npm")) ? "npm" : null;
  if (!npm) {
    block("vscode extension host test", "npm is not on PATH");
    return;
  }
  const env: Record<string, string> = {
    ...Deno.env.toObject(),
    CYROGRAF_BIN: Deno.realPathSync(bin),
  };
  const needsXvfb = !env.DISPLAY && (await commandExists("xvfb-run"));
  const command = needsXvfb ? "xvfb-run" : npm;
  const args = needsXvfb ? ["-a", npm, "test"] : ["test"];
  const result = await run(command, args, { cwd: extension, env });
  if (result.stdout.trim()) console.log(result.stdout.trim());
  if (result.stderr.trim()) console.error(result.stderr.trim());
  check("vscode extension host test passed", result.code === 0);

  let hasVsce = false;
  try {
    Deno.statSync(`${extension}/node_modules/.bin/vsce`);
    hasVsce = true;
  } catch {
    hasVsce = false;
  }
  if (!hasVsce) {
    block("vscode vsix packaging", "editors/vscode/node_modules/.bin/vsce is missing");
    return;
  }
  const packaged = await run(npm, ["run", "package"], { cwd: extension, env });
  const vsix = `${extension}/cyrograf-vscode.vsix`;
  let listed = "";
  try {
    listed = (await run("unzip", ["-l", vsix])).stdout;
  } catch {
    listed = "";
  }
  check("vsix packaged", packaged.code === 0 && listed.length > 0);
  for (const member of [
    "extension/dist/extension.js",
    "extension/dist/onig.wasm",
    "extension/syntaxes/cyrograf.tmLanguage.json",
    "extension/syntaxes/cyrograf.markdown.tmLanguage.json",
    "extension/media/cyrograf.css",
    "extension/language-configuration.json",
    "extension/package.json",
  ]) {
    check(`vsix contains ${member}`, listed.includes(member));
  }
  await Deno.remove(vsix).catch(() => undefined);

  if (env.CYROGRAF_VSCODE_STABLE === "1") {
    const stableEnv: Record<string, string> = {
      ...env,
      CYROGRAF_VSCODE_VERSION: "stable",
    };
    const stable = await run(command, args, { cwd: extension, env: stableEnv });
    if (stable.stdout.trim()) console.log(stable.stdout.trim());
    if (stable.stderr.trim()) console.error(stable.stderr.trim());
    check("vscode stable extension host test passed", stable.code === 0);
  }
}

// ── JetBrains ──────────────────────────────────────────────────────

async function testJetBrains(): Promise<void> {
  const plist = new URL("jetbrains/Cyrograf.tmBundle/info.plist", editorsUrl);
  let plistText = "";
  try {
    plistText = decoder.decode(await Deno.readFile(plist));
  } catch {
    plistText = "";
  }
  check("jetbrains bundle has info.plist", plistText.includes("<key>name</key>"));

  const grammar = await readJson(
    editorsPath("jetbrains/Cyrograf.tmBundle/Syntaxes/cyrograf.tmLanguage.json"),
  );
  check("jetbrains bundle carries the shared grammar", grammar.scopeName === "source.cyrograf");

  const template = await readJson(editorsPath("jetbrains/lsp4ij/template.json")) as {
    id?: string;
    programArgs?: { default?: string };
    fileTypeMappings?: Array<{ languageId?: string; fileType?: { patterns?: string[] } }>;
  };
  check("lsp4ij template id", template.id === "cyrograf");
  check(
    "lsp4ij program and argument",
    /^cyrograf\s+lsp$/.test((template.programArgs?.default ?? "").trim()),
  );
  const mapping = (template.fileTypeMappings ?? [])[0];
  check("lsp4ij mapping language id", mapping?.languageId === "cyrograf");
  check(
    "lsp4ij mapping extension",
    (mapping?.fileType?.patterns ?? []).includes("*.cyrograf"),
  );
}

async function main(): Promise<void> {
  await testSharedGrammar();
  await testExampleProject();
  await testNoShellComposition();
  await testEmacs();
  await testVim();
  await testNeovim();
  await testVSCode();
  await testJetBrains();

  console.log(`\ntest-editors: ${failures} failure(s), ${blocked} blocked`);
  if (failures > 0 || blocked > 0) Deno.exit(1);
  console.log("all editor checks passed");
}

await main();