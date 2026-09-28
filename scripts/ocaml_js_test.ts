// W1 acceptance harness: compile the OCaml js_of_ocaml profile with a real
// js_of_ocaml 6.2.0 and exchange Drut messages with native OCaml and TypeScript.
//
// The toolchain lives in an isolated workspace under TOOLCHAINS so no global
// configuration is touched. A missing js_of_ocaml is reported as BLOCKED with a
// non-zero exit, never as a silent success.

const join = (...parts: string[]): string =>
  parts.map((part, index) => (index === 0 ? part.replace(/\/+$/, "") : part.replace(/^\/+/, "")))
    .join("/");

function env(name: string, fallback?: string): string {
  const value = Deno.env.get(name);
  if (value === undefined || value === "") {
    if (fallback !== undefined) return fallback;
    throw new Error(`missing environment variable ${name}`);
  }
  return value;
}

async function exists(path: string): Promise<boolean> {
  try {
    await Deno.stat(path);
    return true;
  } catch (_) {
    return false;
  }
}

async function copyTree(from: string, to: string): Promise<void> {
  await Deno.remove(to, { recursive: true }).catch(() => {});
  await Deno.mkdir(to, { recursive: true });
  for await (const entry of Deno.readDir(from)) {
    const source = join(from, entry.name);
    const target = join(to, entry.name);
    if (entry.isDirectory) await copyTree(source, target);
    else if (entry.isFile) await Deno.copyFile(source, target);
  }
}

interface RunOptions {
  cwd?: string;
  env?: Record<string, string>;
  quiet?: boolean;
}

async function run(command: string, args: string[], options: RunOptions = {}): Promise<string> {
  const process = new Deno.Command(command, {
    args,
    cwd: options.cwd,
    env: options.env,
    stdout: "piped",
    stderr: "piped",
  });
  const result = await process.output();
  const decoder = new TextDecoder();
  const stdout = decoder.decode(result.stdout);
  const stderr = decoder.decode(result.stderr);
  if (!options.quiet) {
    if (stdout) Deno.stdout.writeSync(result.stdout);
    if (stderr) Deno.stderr.writeSync(result.stderr);
  }
  if (!result.success) {
    throw new Error(
      `${command} ${args.join(" ")} failed with code ${result.code}\n${stdout}\n${stderr}`,
    );
  }
  return stdout;
}

function section(title: string): void {
  console.log(`\n=== ${title} ===`);
}

const projectRoot = env("PROJECT_ROOT", Deno.cwd());
const contract = env("CONTRACT");
const fixtures = env("FIXTURES");
const messages = env("MESSAGES");
const invalid = env("INVALID");
const work = env("WORK");
const toolchains = env("TOOLCHAINS");
const dune = env("DUNE", "dune");
const node = env("NODE", "node");

const workspace = join(toolchains, "jsoo");
const cyrografDir = join(workspace, "cyrograf");
const harnessDir = join(workspace, "harness");
const dataDir = join(workspace, "data");
const nativeDir = join(work, "native");
const tsDir = join(work, "ts");
const nativeJson = join(work, "native.json");
const tsJson = join(work, "ts.json");
const jsJson = join(work, "js.json");
const jsProgram = join(workspace, "_build", "default", "harness", "interop_js.bc.js");

async function requireToolchain(): Promise<void> {
  for (const tool of ["node"]) {
    if (tool === "node") {
      try {
        await run(node, ["--version"], { quiet: true });
      } catch (_) {
        throw new Error(`BLOCKED: ${node} is not available`);
      }
    }
  }
  try {
    await run(dune, ["--version"], { quiet: true });
  } catch (_) {
    throw new Error(`BLOCKED: ${dune} is not available`);
  }
}

async function prepareWorkspace(): Promise<void> {
  await Deno.mkdir(workspace, { recursive: true });
  const duneProject = join(workspace, "dune-project");
  if (!(await exists(duneProject))) {
    await Deno.writeTextFile(
      duneProject,
      `(lang dune 3.17)
(name cyrograf_jsoo_harness)
(package
 (name cyrograf_jsoo_harness)
 (synopsis "Isolated js_of_ocaml 6.2.0 acceptance harness for the Cyrograf js profile")
 (depends
  (ocaml (= 5.4.1))
  yojson
  (js_of_ocaml (= 6.2.0))
  (js_of_ocaml-compiler (= 6.2.0))))
`,
    );
  }
  await copyTree(join(projectRoot, "lib", "contract"), cyrografDir);
  await Deno.writeTextFile(
    join(cyrografDir, "dune"),
    `(library
 (name cyrograf)
 (libraries yojson))
`,
  );
  await Deno.mkdir(harnessDir, { recursive: true });
  await Deno.writeTextFile(
    join(harnessDir, "dune"),
    `(executable
 (name interop_js)
 (modes js)
 (libraries cyrograf generated_fixtures yojson))
`,
  );
  await Deno.copyFile(
    join(projectRoot, "test", "interop_ocaml.ml"),
    join(harnessDir, "interop_js.ml"),
  );
  if (!(await exists(join(workspace, "dune.lock")))) {
    section("lock isolated js_of_ocaml 6.2.0 workspace");
    await run(dune, ["pkg", "lock"], { cwd: workspace });
  }
}

async function generateJsProfile(): Promise<void> {
  section("generate js profile data");
  await Deno.remove(dataDir, { recursive: true }).catch(() => {});
  await run(contract, [
    "build",
    fixtures,
    "--output",
    dataDir,
    "--targets",
    "ocaml",
    "--ocaml-profile",
    "js",
    "--ocaml-library",
    "generated_fixtures",
  ]);
  section("compile js profile with js_of_ocaml 6.2.0");
  await run(dune, ["build", "harness/interop_js.bc.js"], { cwd: workspace });
}

function js(args: string[], label = "js"): Promise<string> {
  return run(node, [jsProgram, ...args], { env: { CYROGRAF_PEER: label } });
}

async function exchange(): Promise<void> {
  section("generate native OCaml and TypeScript data");
  await Deno.remove(nativeDir, { recursive: true }).catch(() => {});
  await Deno.remove(tsDir, { recursive: true }).catch(() => {});
  await run(contract, ["build", fixtures, "--output", nativeDir, "--targets", "ocaml"]);
  await run(contract, ["build", fixtures, "--output", tsDir, "--targets", "typescript"]);

  const native = env(
    "INTEROP",
    join(projectRoot, "_build", "default", "test", "interop_ocaml.exe"),
  );
  const deno = env("DENO", "deno");
  const tsRoot = join(tsDir, "typescript");

  section("produce encodings");
  await run(native, ["check", messages, nativeJson], {
    env: { CYROGRAF_PEER: "ocaml" },
  });
  await run(deno, [
    "run",
    "--allow-read",
    "--allow-write",
    "test/deno/interop.ts",
    "check",
    tsRoot,
    messages,
    tsJson,
  ], { cwd: projectRoot });
  await js(["check", messages, jsJson]);

  section("cross-verify encodings");
  await run(native, ["verify", jsJson], { env: { CYROGRAF_PEER: "ocaml" } });
  await js(["verify", nativeJson]);
  await js(["verify", tsJson]);
  await run(deno, [
    "run",
    "--allow-read",
    "test/deno/interop.ts",
    "verify",
    tsRoot,
    nativeJson,
  ], { cwd: projectRoot });
  await run(deno, [
    "run",
    "--allow-read",
    "test/deno/interop.ts",
    "verify",
    tsRoot,
    jsJson,
  ], { cwd: projectRoot });

  section("reject invalid wire");
  await js(["invalid", invalid]);
  await run(native, ["invalid", invalid], { env: { CYROGRAF_PEER: "ocaml" } });

  section("js profile boundary cases");
  await js(["profile"]);
}

try {
  await requireToolchain();
  await prepareWorkspace();
  await generateJsProfile();
  await exchange();
  console.log("\ntest-ocaml-js: ok");
} catch (error) {
  const message = error instanceof Error ? error.message : String(error);
  console.error(`\ntest-ocaml-js: ${message}`);
  Deno.exit(1);
}