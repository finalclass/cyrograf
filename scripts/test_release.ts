// Acceptance test for the artifacts produced by `make package`.
//
// The script verifies the SHA-256 manifest, unpacks the program and source
// archives outside the repository, exercises the public commands from a fresh
// directory, runs a minimal LSP session and compiles a separate OCaml consumer
// against the `cyrograf` library.

const rootUrl = new URL("../", import.meta.url);
const root = Deno.realPathSync(rootUrl);

const encoder = new TextEncoder();
const decoder = new TextDecoder();

let failures = 0;

function check(label: string, condition: boolean, detail = ""): void {
  if (condition) {
    console.log(`PASS: ${label}`);
  } else {
    failures += 1;
    console.error(`FAIL: ${label}${detail ? ` (${detail})` : ""}`);
  }
}

interface RunResult {
  code: number;
  stdout: string;
  stderr: string;
}

function run(
  command: string,
  args: string[],
  options: { cwd?: string; env?: Record<string, string>; allowFailure?: boolean } = {},
): RunResult {
  const output = new Deno.Command(command, {
    args,
    cwd: options.cwd,
    env: options.env,
    stdin: "null",
    stdout: "piped",
    stderr: "piped",
  }).outputSync();
  return {
    code: output.code,
    stdout: decoder.decode(output.stdout),
    stderr: decoder.decode(output.stderr),
  };
}

async function runWithInput(
  command: string,
  args: string[],
  input: string,
  options: { cwd?: string; env?: Record<string, string> } = {},
): Promise<RunResult> {
  const child = new Deno.Command(command, {
    args,
    cwd: options.cwd,
    env: options.env,
    stdin: "piped",
    stdout: "piped",
    stderr: "piped",
  }).spawn();
  const writer = child.stdin.getWriter();
  await writer.write(encoder.encode(input));
  await writer.close();
  const output = await child.output();
  return {
    code: output.code,
    stdout: decoder.decode(output.stdout),
    stderr: decoder.decode(output.stderr),
  };
}

function readVersion(): string {
  const text = Deno.readTextFileSync(`${root}/bin/version.ml`);
  const match = /let\s+value\s*=\s*"([^"]+)"/.exec(text);
  if (!match) throw new Error("cannot read the version from bin/version.ml");
  return match[1];
}

async function sha256(path: string): Promise<string> {
  const data = await Deno.readFile(path);
  const digest = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

const version = readVersion();
const release = `${root}/_build/release`;
const programName = `cyrograf-${version}-linux-x86_64.tar.gz`;
const sourceName = `cyrograf-${version}-src.tar.gz`;
const programPrefix = `cyrograf-${version}-linux-x86_64`;
const sourcePrefix = `cyrograf-${version}`;

const home = Deno.env.get("HOME") ?? Deno.cwd();
const work = Deno.makeTempDirSync({ dir: home, prefix: "cyrograf-release-" });
Deno.mkdirSync(`${work}/tmp`, { recursive: true });

function duneEnv(): Record<string, string> {
  return { ...Deno.env.toObject(), TMPDIR: `${work}/tmp` };
}

const duneFlags = (Deno.env.get("CYROGRAF_DUNE_FLAGS") ?? "")
  .split(" ")
  .filter((part) => part.length > 0);

function onPath(command: string): boolean {
  return (Deno.env.get("PATH") ?? "")
    .split(":")
    .some((dir) => dir.length > 0 && exists(`${dir}/${command}`));
}

// An isolated workspace without package management needs both a compiler and
// the transitive libraries of `cyrograf`. A system/opam switch provides them on
// PATH; otherwise reach into the Dune package store that built the checkout.
function discoverPkgTools(): { compilerBin: string | null; libraryDirs: string[] } {
  const store = `${sourceRoot}/_build/_private/default/.pkg`;
  const libraryDirs: string[] = [];
  let compilerBin: string | null = null;
  if (exists(store)) {
    for (const entry of Deno.readDirSync(store)) {
      if (!entry.isDirectory) continue;
      const target = `${store}/${entry.name}/target`;
      if (exists(`${target}/lib`)) libraryDirs.push(`${target}/lib`);
      if (compilerBin === null && exists(`${target}/bin/ocamlc`)) {
        compilerBin = `${target}/bin`;
      }
    }
  }
  return { compilerBin, libraryDirs };
}

function consumerEnv(prefix: string): Record<string, string> {
  const env = duneEnv();
  const ocamlpath = [`${prefix}/lib`];
  if (!onPath("ocamlc")) {
    const tools = discoverPkgTools();
    if (tools.compilerBin) env.PATH = `${tools.compilerBin}:${env.PATH ?? ""}`;
    ocamlpath.push(...tools.libraryDirs);
  }
  env.OCAMLPATH = ocamlpath.join(":");
  return env;
}

function isFile(path: string): boolean {
  try {
    return Deno.statSync(path).isFile;
  } catch {
    return false;
  }
}

function symlinksUnder(directory: string): string[] {
  const found: string[] = [];
  const walk = (path: string): void => {
    for (const entry of Deno.readDirSync(path)) {
      const next = `${path}/${entry.name}`;
      const info = Deno.lstatSync(next);
      if (info.isSymlink) found.push(next);
      else if (info.isDirectory) walk(next);
    }
  };
  walk(directory);
  return found;
}

// ── SHA-256 manifest ───────────────────────────────────────────────
{
  const listed = Deno.readTextFileSync(`${release}/SHA256SUMS`)
    .split("\n")
    .filter((line) => line.trim().length > 0);
  let allMatch = listed.length > 0;
  for (const line of listed) {
    const match = /^([0-9a-f]{64})\s+(.+)$/.exec(line.trim());
    if (!match) {
      allMatch = false;
      continue;
    }
    const actual = await sha256(`${release}/${match[2]}`);
    if (actual !== match[1]) {
      console.error(`FAIL: checksum mismatch for ${match[2]}`);
      allMatch = false;
    }
  }
  check(`SHA256SUMS verifies ${listed.length} artifact(s)`, allMatch);
}

// ── Program archive ────────────────────────────────────────────────
const programDir = `${work}/program`;
Deno.mkdirSync(programDir, { recursive: true });
run("tar", ["-xzf", `${release}/${programName}`, "-C", programDir]);
const binary = `${programDir}/${programPrefix}/cyrograf`;
check("program archive contains cyrograf", Deno.statSync(binary).isFile);
check("program archive contains LICENSE", Deno.statSync(`${programDir}/${programPrefix}/LICENSE`).isFile);

const newDirectory = `${work}/elsewhere`;
Deno.mkdirSync(newDirectory, { recursive: true });

{
  const bare = run(binary, [], { cwd: newDirectory });
  check("cyrograf without arguments exits 0", bare.code === 0);
  check("cyrograf without arguments prints help", bare.stdout.includes("Usage:"));
  check("cyrograf without arguments writes no stderr", bare.stderr.trim() === "");

  const versionResult = run(binary, ["--version"], { cwd: newDirectory });
  check("cyrograf --version", versionResult.stdout.trim() === `cyrograf ${version}`);

  for (const command of ["check", "build", "format", "migrate", "lsp", "help"]) {
    const viaHelp = run(binary, ["help", command], { cwd: newDirectory });
    check(`cyrograf help ${command} exits 0`, viaHelp.code === 0 && viaHelp.stdout.length > 0);
    if (command === "help") continue;
    const viaFlag = run(binary, [command, "--help"], { cwd: newDirectory });
    check(`cyrograf ${command} --help exits 0`, viaFlag.code === 0 && viaFlag.stdout.length > 0);
  }

  const unknown = run(binary, ["nonsense"], { cwd: newDirectory });
  check("unknown command exits 2", unknown.code === 2);
}

// ── Source archive ─────────────────────────────────────────────────
const sourceDir = `${work}/source`;
Deno.mkdirSync(sourceDir, { recursive: true });
run("tar", ["-xzf", `${release}/${sourceName}`, "-C", sourceDir]);
const sourceRoot = `${sourceDir}/${sourcePrefix}`;
check("source archive contains dune-project", Deno.statSync(`${sourceRoot}/dune-project`).isFile);
check("source archive contains dune.lock", Deno.statSync(`${sourceRoot}/dune.lock`).isDirectory);
check("source archive excludes .local", !exists(`${sourceRoot}/.local`));
check("source archive excludes .git", !exists(`${sourceRoot}/.git`));
check("source archive excludes author cache", !exists(`${sourceRoot}/_build`));

function exists(path: string): boolean {
  try {
    Deno.statSync(path);
    return true;
  } catch {
    return false;
  }
}

{
  const authorRoot = ["", "home", "sel"].join("/");
  const listing = run("grep", ["-rIl", authorRoot, sourceRoot], { allowFailure: true });
  check(
    "source archive contains no author home directory path",
    listing.code !== 0 || listing.stdout.trim() === "",
    listing.stdout.trim(),
  );
}

// ── Public commands on the example project ─────────────────────────
const example = `${sourceRoot}/examples/orders`;
const output = `${work}/output`;
{
  const checkResult = run(binary, ["check", example], { cwd: newDirectory });
  check("cyrograf check on the quick-start example", checkResult.code === 0, checkResult.stderr.trim());

  const build = run(
    binary,
    ["build", example, "--output", output, "--targets", "ocaml,typescript,go,dart,python,java,csharp,rust"],
    { cwd: newDirectory },
  );
  check("cyrograf build the delivered targets", build.code === 0, build.stderr.trim());
  for (const artifact of [
    "schema.json",
    "manifest.json",
    "ocaml/orders.ml",
    "typescript/orders.ts",
    "go/orders/orders.go",
    "dart/orders.dart",
    "python/generated_contracts/orders.py",
    "python/generated_contracts/py.typed",
    "python/pyproject.toml",
    "java/pom.xml",
    "java/src/main/java/generated_contracts/Orders.java",
    "java/src/main/java/generated_contracts/Common.java",
    "java/src/main/java/generated_contracts/Wire.java",
    "java/src/main/java/generated_contracts/CyrografException.java",
    "csharp/GeneratedContracts.csproj",
    "csharp/GeneratedContracts.Orders.cs",
    "csharp/GeneratedContracts.Common.cs",
    "csharp/GeneratedContracts.Wire.cs",
    "csharp/GeneratedContracts.CyrografException.cs",
    "csharp/GeneratedContracts.CyrografUnit.cs",
    "rust/Cargo.toml",
    "rust/src/lib.rs",
    "rust/src/orders.rs",
    "rust/src/common.rs",
    "rust/src/wire.rs",
    "rust/src/error.rs",
  ]) {
    check(`build produced ${artifact}`, exists(`${output}/${artifact}`));
  }

  const formatCheck = run(binary, ["format", "--check", example], { cwd: newDirectory });
  check("cyrograf format --check on formatted example", formatCheck.code === 0, formatCheck.stdout.trim());

  const unformatted = `${work}/unformatted`;
  Deno.mkdirSync(unformatted, { recursive: true });
  Deno.writeTextFileSync(
    `${unformatted}/Thing.cyrograf`,
    "struct Thing { id: String }\n",
  );
  const formatRun = run(binary, ["format", unformatted], { cwd: newDirectory });
  check("cyrograf format rewrites a file", formatRun.code === 0);
  check(
    "cyrograf format output is canonical",
    Deno.readTextFileSync(`${unformatted}/Thing.cyrograf`) === "struct Thing {\n  id: String\n}\n",
  );

  const stdin = await runWithInput(
    binary,
    ["format", "--stdin", "--filename", "Thing.cyrograf"],
    "struct Thing { id: String }\n",
    { cwd: newDirectory },
  );
  check("cyrograf format --stdin", stdin.code === 0 && stdin.stdout === "struct Thing {\n  id: String\n}\n");

  const tomlDir = `${work}/toml`;
  Deno.mkdirSync(tomlDir, { recursive: true });
  Deno.writeTextFileSync(`${tomlDir}/Thing.toml`, '[msg.Thing.struct]\nid = "string"\n');
  const migrated = `${work}/migrated`;
  const migrate = run(binary, ["migrate", tomlDir, "--output", migrated], { cwd: newDirectory });
  check("cyrograf migrate", migrate.code === 0, migrate.stderr.trim());
  check("migrate produced a native source", exists(`${migrated}/Thing.cyrograf`));
  const migratedCheck = run(binary, ["check", migrated], { cwd: newDirectory });
  check("migrated project checks", migratedCheck.code === 0, migratedCheck.stderr.trim());
}

// ── Minimal LSP session ────────────────────────────────────────────
{
  const child = new Deno.Command(binary, {
    args: ["lsp"],
    cwd: newDirectory,
    stdin: "piped",
    stdout: "piped",
    stderr: "piped",
  }).spawn();
  const writer = child.stdin.getWriter();
  const reader = child.stdout.getReader();
  let buffer = new Uint8Array(0);

  const send = (message: unknown): Promise<void> =>
    writer.write(encoder.encode(frame(message)));

  const next = async (timeoutMs = 8000): Promise<Record<string, unknown> | null> => {
    const deadline = Date.now() + timeoutMs;
    while (Date.now() < deadline) {
      const separator = indexOfHeader(buffer);
      if (separator >= 0) {
        const header = decoder.decode(buffer.slice(0, separator));
        const match = /Content-Length:\s*(\d+)/i.exec(header);
        if (match) {
          const length = parseInt(match[1], 10);
          const start = separator + 4;
          if (buffer.length >= start + length) {
            const body = decoder.decode(buffer.slice(start, start + length));
            buffer = buffer.slice(start + length);
            return JSON.parse(body) as Record<string, unknown>;
          }
        }
      }
      const { value, done } = await Promise.race([
        reader.read(),
        new Promise<{ value: undefined; done: boolean }>((resolve) =>
          setTimeout(() => resolve({ value: undefined, done: false }), 50)
        ),
      ]);
      if (done) return null;
      if (value) buffer = concat(buffer, value);
    }
    return null;
  };

  await send({
    jsonrpc: "2.0",
    id: 1,
    method: "initialize",
    params: { processId: null, rootUri: null, capabilities: {} },
  });
  const initialized = await next();
  check("lsp initialize answered", initialized?.id === 1);
  const capabilities = (initialized?.result as { capabilities?: Record<string, unknown> })?.capabilities;
  check("lsp reports capabilities", typeof capabilities === "object" && capabilities !== null);

  await send({ jsonrpc: "2.0", method: "initialized", params: {} });
  await send({ jsonrpc: "2.0", id: 2, method: "shutdown", params: null });
  const shutdown = await next();
  check("lsp shutdown answered", shutdown?.id === 2);
  await send({ jsonrpc: "2.0", method: "exit", params: null });
  writer.close();
  const status = await child.status;
  check("lsp exits 0 after shutdown", status.code === 0);
}

// ── make install and installed-library OCaml consumer ──────────────
const consumerSource = `let () =
  let request : Orders.ReserveRequest.t =
    Orders.ReserveRequest.make ~owner_id:"o1" ~quantity:2 ~note:"hi" ()
  in
  match Orders.ReserveRequest.to_drut request with
  | Error error ->
    prerr_endline error.Cyrograf.Error.message;
    exit 1
  | Ok encoded -> (
    match Orders.ReserveRequest.from_drut encoded with
    | Error error ->
      prerr_endline error.Cyrograf.Error.message;
      exit 1
    | Ok decoded -> Printf.printf "roundtrip %s\\n" decoded.owner_id)
`;

const installedPrefix = `${work}/prefix with spaces`;

function install(vars: Record<string, string>): RunResult {
  const assignments = Object.entries(vars).map(([name, value]) => `${name}=${value}`);
  return run("make", ["install", ...assignments], {
    cwd: sourceRoot,
    env: { ...duneEnv(), DUNE_FLAGS: duneFlags.join(" ") },
  });
}

{
  const first = install({ PREFIX: installedPrefix });
  check("make install into a prefix with spaces", first.code === 0, first.stderr.trim());
  check("installed cyrograf program", isFile(`${installedPrefix}/bin/cyrograf`));
  check("installed cyrograf META", isFile(`${installedPrefix}/lib/cyrograf/META`));
  check("installed cyrograf dune-package", isFile(`${installedPrefix}/lib/cyrograf/dune-package`));
  check("installed cyrograf.cmxa", isFile(`${installedPrefix}/lib/cyrograf/cyrograf.cmxa`));
  check(
    "installed cyrograf.compiler",
    isFile(`${installedPrefix}/lib/cyrograf/compiler/cyrograf_compiler.cmxa`),
  );
  check(
    "installed cyrograf.tooling",
    isFile(`${installedPrefix}/lib/cyrograf/tooling/cyrograf_tooling.cmxa`),
  );
  check("installed cyrograf.lsp", isFile(`${installedPrefix}/lib/cyrograf/lsp/cyrograf_lsp.cmxa`));
  const links = symlinksUnder(installedPrefix);
  check("installed files are not symlinks into the build", links.length === 0, links.join(", "));

  Deno.writeTextFileSync(`${installedPrefix}/foreign.txt`, "keep");
  const repeated = install({ PREFIX: installedPrefix });
  const kept = exists(`${installedPrefix}/foreign.txt`) &&
    Deno.readTextFileSync(`${installedPrefix}/foreign.txt`) === "keep";
  check(
    "repeated make install succeeds and keeps a foreign file",
    repeated.code === 0 && kept,
    repeated.stderr.trim(),
  );

  const destdir = `${work}/staged root`;
  const staged = install({ PREFIX: "/cyrograf", DESTDIR: destdir });
  check("make install with DESTDIR succeeds", staged.code === 0, staged.stderr.trim());
  check("DESTDIR staging places the program", isFile(`${destdir}/cyrograf/bin/cyrograf`));
  check("DESTDIR staging places the library", isFile(`${destdir}/cyrograf/lib/cyrograf/META`));

  const readonly = `${work}/readonly`;
  Deno.mkdirSync(readonly, { recursive: true });
  Deno.chmodSync(readonly, 0o555);
  const failed = install({ PREFIX: `${readonly}/nested` });
  check("make install fails on a write error", failed.code !== 0, failed.stderr.trim());
  Deno.chmodSync(readonly, 0o755);

  const dry = run("make", ["-n", "install"], {
    cwd: sourceRoot,
    env: { ...duneEnv(), DUNE_FLAGS: duneFlags.join(" ") },
  });
  check(
    "default PREFIX expands to $(HOME)/.local",
    dry.stdout.includes(`${home}/.local`),
    dry.stdout.trim(),
  );
}

const installedBinary = `${installedPrefix}/bin/cyrograf`;
{
  const versionResult = run(installedBinary, ["--version"], { cwd: newDirectory });
  check(
    "installed cyrograf --version outside the repository",
    versionResult.stdout.trim() === `cyrograf ${version}`,
  );
  const installedCheck = run(installedBinary, ["check", example], { cwd: newDirectory });
  check(
    "installed cyrograf checks the example outside the repository",
    installedCheck.code === 0,
    installedCheck.stderr.trim(),
  );
}

{
  const consumer = `${work}/install-consumer`;
  Deno.mkdirSync(consumer, { recursive: true });
  const generated = run(
    installedBinary,
    ["build", example, "--output", `${consumer}/generated`, "--targets", "ocaml"],
    { cwd: newDirectory },
  );
  check(
    "installed cyrograf generates the consumer sources",
    generated.code === 0,
    generated.stderr.trim(),
  );
  for (const module of ["common.ml", "common.mli", "orders.ml", "orders.mli", "drut_runtime.ml"]) {
    Deno.copyFileSync(`${consumer}/generated/ocaml/${module}`, `${consumer}/${module}`);
  }
  Deno.writeTextFileSync(`${consumer}/dune-project`, "(lang dune 3.17)\n");
  Deno.writeTextFileSync(
    `${consumer}/dune`,
    "(executable\n (name main)\n (modules main common orders drut_runtime)\n (libraries cyrograf yojson))\n",
  );
  Deno.writeTextFileSync(`${consumer}/main.ml`, consumerSource);
  const compiled = run("dune", ["build", "--pkg=disabled", "main.exe"], {
    cwd: consumer,
    env: consumerEnv(installedPrefix),
  });
  check(
    "separate OCaml consumer compiles against the installed cyrograf",
    compiled.code === 0,
    compiled.stderr.trim(),
  );
  const consumerBinary = `${consumer}/_build/default/main.exe`;
  if (exists(consumerBinary)) {
    const executed = run(consumerBinary, [], { cwd: newDirectory });
    check(
      "separate OCaml consumer runs",
      executed.code === 0 && executed.stdout.includes("roundtrip o1"),
      executed.stderr.trim(),
    );
  } else {
    check("separate OCaml consumer runs", false, "consumer binary was not built");
  }
}

// ── Python package installation and consumer ───────────────────────
{
  const python = Deno.env.get("PYTHON") ?? "python3";
  const venv = `${work}/python-venv`;
  const created = run(python, ["-m", "venv", venv], { allowFailure: true });
  check("isolated Python environment created", created.code === 0, created.stderr.trim());
  const venvPython = `${venv}/bin/python`;
  if (exists(venvPython)) {
    const buildDir = `${work}/python-build`;
    Deno.mkdirSync(buildDir, { recursive: true });
    Deno.writeTextFileSync(
      `${buildDir}/setup.py`,
      `from setuptools import setup

setup(
    name="generated-contracts",
    version="0.1.0",
    packages=["generated_contracts"],
    package_dir={"generated_contracts": ${JSON.stringify(`${output}/python/generated_contracts`)}},
    package_data={"generated_contracts": ["py.typed"]},
)
`,
    );
    const installed = run(venvPython, ["setup.py", "install"], {
      cwd: buildDir,
      allowFailure: true,
    });
    check(
      "generated Python package installs into the isolated environment",
      installed.code === 0,
      (installed.stdout + installed.stderr).trim(),
    );
    const consumer = run(venvPython, [`${sourceRoot}/test/python/consumer_positive.py`], {
      cwd: newDirectory,
      allowFailure: true,
    });
    check(
      "installed Python consumer imports and roundtrips",
      consumer.code === 0,
      consumer.stderr.trim(),
    );
    const imported = run(
      venvPython,
      ["-c", "from generated_contracts.orders import ReserveRequest; print(ReserveRequest(owner_id='o1', quantity=1).to_drut())"],
      { cwd: newDirectory, allowFailure: true },
    );
    check(
      "installed Python package works outside the repository",
      imported.code === 0 && imported.stdout.includes('["o1",1,null]'),
      imported.stderr.trim(),
    );
  } else {
    check("installed Python consumer imports and roundtrips", false, "venv python missing");
  }
}

// ── Java project compile and consumer ──────────────────────────────
{
  const javac = Deno.env.get("JAVAC") ?? "javac";
  const java = Deno.env.get("JAVA") ?? "java";
  const packageDir = `${output}/java/src/main/java/generated_contracts`;
  const classes = `${work}/java-classes`;
  Deno.mkdirSync(classes, { recursive: true });
  const sources = [...Deno.readDirSync(packageDir)]
    .filter((entry) => entry.isFile && entry.name.endsWith(".java"))
    .map((entry) => `${packageDir}/${entry.name}`);
  const compiled = run(javac, ["--release", "21", "-d", classes, ...sources], {
    allowFailure: true,
  });
  check(
    "generated Java project compiles with javac release 21",
    compiled.code === 0,
    compiled.stderr.trim(),
  );
  const consumerPath = `${work}/JavaConsumer.java`;
  Deno.writeTextFileSync(
    consumerPath,
    `import generated_contracts.Orders;
import java.util.Optional;

public final class JavaConsumer {
  public static void main(String[] arguments) {
    String text = new Orders.ReserveRequest("o1", 1, Optional.empty()).toDrut();
    Orders.ReserveRequest request = Orders.ReserveRequest.fromDrut(text);
    System.out.println("roundtrip " + request.ownerId());
  }
}
`,
  );
  const consumer = run(javac, [
    "--release",
    "21",
    "-cp",
    classes,
    "-d",
    classes,
    consumerPath,
  ], { allowFailure: true });
  check("separate Java consumer compiles outside the repository", consumer.code === 0, consumer.stderr.trim());
  if (consumer.code === 0) {
    const executed = run(java, ["-cp", classes, "JavaConsumer"], { allowFailure: true });
    check(
      "separate Java consumer runs",
      executed.code === 0 && executed.stdout.includes("roundtrip o1"),
      executed.stderr.trim(),
    );
  } else {
    check("separate Java consumer runs", false, "consumer did not compile");
  }
}

// ── C# project compile and consumer ────────────────────────────────
{
  const dotnet = Deno.env.get("DOTNET") ?? "dotnet";
  const consumerDir = `${work}/csharp-consumer`;
  Deno.mkdirSync(consumerDir, { recursive: true });
  Deno.writeTextFileSync(
    `${consumerDir}/consumer.csproj`,
    `<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net10.0</TargetFramework>
    <Nullable>enable</Nullable>
    <ImplicitUsings>disable</ImplicitUsings>
    <LangVersion>latest</LangVersion>
  </PropertyGroup>
  <ItemGroup>
    <ProjectReference Include="${output}/csharp/GeneratedContracts.csproj" />
  </ItemGroup>
</Project>
`,
  );
  Deno.writeTextFileSync(
    `${consumerDir}/Program.cs`,
    `using System;
using GeneratedContracts.Orders;

public static class Program
{
    public static void Main()
    {
        string text = new ReserveRequest("o1", 1, null).ToDrut();
        ReserveRequest request = ReserveRequest.FromDrut(text);
        Console.WriteLine("roundtrip " + request.OwnerId);
    }
}
`,
  );
  const executed = run(dotnet, ["run", "--project", consumerDir, "-v", "q"], {
    allowFailure: true,
  });
  check(
    "separate C# consumer compiles and runs outside the repository",
    executed.code === 0 && executed.stdout.includes("roundtrip o1"),
    (executed.stdout + executed.stderr).trim(),
  );
}

// ── Rust crate compile and consumer ────────────────────────────────
{
  const rust = Deno.env.get("RUST") ?? "cargo";
  const consumerDir = `${work}/rust-consumer`;
  Deno.mkdirSync(`${consumerDir}/src`, { recursive: true });
  Deno.writeTextFileSync(
    `${consumerDir}/Cargo.toml`,
    `[package]
name = "cyrograf_release_rust_consumer"
version = "0.0.0"
edition = "2024"
rust-version = "1.85"
publish = false

[[bin]]
name = "rust_consumer"
path = "src/main.rs"

[dependencies]
generated_contracts = { path = ${JSON.stringify(`${output}/rust`)} }
`,
  );
  Deno.writeTextFileSync(
    `${consumerDir}/src/main.rs`,
    `use generated_contracts::orders::ReserveRequest;

fn main() {
    let text = ReserveRequest {
        owner_id: "o1".to_string(),
        quantity: 1,
        note: None,
    }
    .to_drut()
    .expect("encode");
    let request = ReserveRequest::from_drut(&text).expect("decode");
    println!("roundtrip {}", request.owner_id);
}
`,
  );
  const executed = run(rust, ["run", "-q", "--manifest-path", `${consumerDir}/Cargo.toml`], {
    allowFailure: true,
  });
  check(
    "separate Rust consumer compiles and runs outside the repository",
    executed.code === 0 && executed.stdout.includes("roundtrip o1"),
    (executed.stdout + executed.stderr).trim(),
  );
}

function frame(message: unknown): string {
  const body = JSON.stringify(message);
  return `Content-Length: ${encoder.encode(body).length}\r\n\r\n${body}`;
}

function concat(a: Uint8Array, b: Uint8Array): Uint8Array<ArrayBuffer> {
  const out = new Uint8Array(a.length + b.length);
  out.set(a, 0);
  out.set(b, a.length);
  return out;
}

function indexOfHeader(buffer: Uint8Array): number {
  for (let i = 0; i + 3 < buffer.length; i += 1) {
    if (
      buffer[i] === 13 && buffer[i + 1] === 10 && buffer[i + 2] === 13 && buffer[i + 3] === 10
    ) {
      return i;
    }
  }
  return -1;
}

Deno.removeSync(work, { recursive: true });

console.log(`\ntest-release: ${failures} failure(s)`);
if (failures > 0) Deno.exit(1);
console.log("release artifacts verified");