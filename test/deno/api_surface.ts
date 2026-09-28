// Public API surface check for the four generated targets.
//
// Usage: api_surface.ts WORK_DIR FIXTURES_DIR
//
// An isolated positive consumer per target uses only the two public text
// conversions from api.md and must compile/run. A negative consumer refers to
// a removed or newly forbidden conversion and must fail to compile for that
// reason, while its positive neighbour keeps working. OCaml additionally
// checks that Cyrograf.Codec, Cyrograf.Wire and the old Contract module do not
// exist, and that the message modules hide the internal value codec.

const repo = Deno.realPathSync(new URL("../../", import.meta.url));
const binary = Deno.env.get("CYROGRAF_BIN");
if (!binary) {
  console.error("api_surface: CYROGRAF_BIN is not set");
  Deno.exit(2);
}

const workDir = Deno.args[0];
const fixtures = Deno.args[1] ?? "test/fixtures/orders";
if (!workDir) {
  console.error("usage: api_surface.ts WORK_DIR [FIXTURES_DIR]");
  Deno.exit(2);
}

const enabled = new Set(
  (Deno.env.get("SURFACE_TARGETS") ?? "ocaml,typescript,go,dart")
    .split(",")
    .map((name) => name.trim())
    .filter((name) => name.length > 0),
);
const wants = (target: string) => enabled.has(target);

interface RunResult {
  code: number;
  stdout: string;
  stderr: string;
}

function run(
  command: string,
  args: string[],
  options: { cwd?: string; env?: Record<string, string> } = {},
): RunResult {
  const output = new Deno.Command(command, {
    args,
    cwd: options.cwd,
    env: options.env,
    stdout: "piped",
    stderr: "piped",
  }).outputSync();
  const decoder = new TextDecoder();
  return {
    code: output.code,
    stdout: decoder.decode(output.stdout),
    stderr: decoder.decode(output.stderr),
  };
}

let failures = 0;

function check(label: string, condition: boolean, detail = ""): void {
  if (condition) {
    console.log(`PASS: ${label}`);
  } else {
    failures += 1;
    console.error(`FAIL: ${label}${detail ? ` (${detail})` : ""}`);
  }
}

try {
  Deno.removeSync(workDir, { recursive: true });
} catch {
  // The work directory does not exist yet.
}
Deno.mkdirSync(workDir, { recursive: true });

const generated = run(binary, [
  "build",
  fixtures,
  "--output",
  workDir,
  "--targets",
  "typescript,go,dart,python,java,csharp,rust",
]);
check(
  "generated typescript, go, dart, python, java, csharp and rust targets",
  generated.code === 0,
  generated.stderr.trim(),
);
if (generated.code !== 0) Deno.exit(1);

// ── TypeScript ─────────────────────────────────────────────────────

if (wants("typescript")) {
const tsDir = `${workDir}/typescript`;
const tsPositive = `${tsDir}/api_surface_positive.ts`;
const tsNegative = `${tsDir}/api_surface_negative.ts`;
Deno.writeTextFileSync(
  tsPositive,
  `import { ReserveRequest } from "./orders.ts";

const text: string = ReserveRequest.toDrut({ ownerId: "o1", quantity: 2 });
const value: ReserveRequest = ReserveRequest.fromDrut(text);
void value.ownerId;
`,
);
Deno.writeTextFileSync(
  tsNegative,
  `import { ReserveRequest } from "./orders.ts";

// The internal value encoder must not be reachable from a message module.
void ReserveRequest.wireEncodeReserveRequest;
`,
);

const tsConfig = `${tsDir}/api_surface_tsconfig.json`;
Deno.writeTextFileSync(
  tsConfig,
  JSON.stringify({
    compilerOptions: {
      strict: true,
      exactOptionalPropertyTypes: true,
      noImplicitAny: true,
    },
  }),
);

const tsPositiveRun = run(
  Deno.execPath(),
  ["check", "--config", tsConfig, tsPositive],
);
check(
  "typescript positive consumer compiles with two conversions",
  tsPositiveRun.code === 0,
  tsPositiveRun.stderr.trim(),
);
const tsNegativeRun = run(
  Deno.execPath(),
  ["check", "--config", tsConfig, tsNegative],
);
check(
  "typescript excess wireEncode export rejected",
  tsNegativeRun.code !== 0 &&
    tsNegativeRun.stderr.includes("wireEncodeReserveRequest"),
  tsNegativeRun.stderr.trim(),
);
}

// ── Go ─────────────────────────────────────────────────────────────

if (wants("go")) {
const goDir = `${workDir}/go`;
Deno.mkdirSync(`${goDir}/cmd/positive`, { recursive: true });
Deno.mkdirSync(`${goDir}/cmd/negative`, { recursive: true });
Deno.writeTextFileSync(
  `${goDir}/cmd/positive/main.go`,
  `package main

import (
	"fmt"

	"generated_contracts/orders"
)

func main() {
	value, err := orders.ReserveRequestFromDrut("[\\"o1\\",2,null]")
	if err != nil {
		panic(err)
	}
	text, err := orders.ReserveRequestToDrut(value)
	if err != nil {
		panic(err)
	}
	fmt.Println(text)
}
`,
);
Deno.writeTextFileSync(
  `${goDir}/cmd/negative/main.go`,
  `package main

import "generated_contracts/orders"

func main() {
	_, _ = orders.EncodeReserveRequestValue(orders.ReserveRequest{})
}
`,
);

const goPositive = run("go", ["build", "-o", "/dev/null", "./cmd/positive"], {
  cwd: goDir,
});
check(
  "go positive consumer builds with two conversions",
  goPositive.code === 0,
  goPositive.stderr.trim(),
);
const goNegative = run("go", ["build", "-o", "/dev/null", "./cmd/negative"], {
  cwd: goDir,
});
check(
  "go excess Encode...Value export rejected",
  goNegative.code !== 0 &&
    goNegative.stderr.includes("EncodeReserveRequestValue"),
  goNegative.stderr.trim(),
);
}

// ── Dart ───────────────────────────────────────────────────────────

if (wants("dart")) {
const dartDir = `${workDir}/dart`;
const dartPositive = `${dartDir}/api_surface_positive.dart`;
const dartNegative = `${dartDir}/api_surface_negative.dart`;
Deno.writeTextFileSync(
  dartPositive,
  `import 'orders.dart';

void main() {
  final ReserveRequest value =
      ReserveRequest.fromDrut('["o1",2,null]');
  print(value.toDrut());
}
`,
);
Deno.writeTextFileSync(
  dartNegative,
  `import 'orders.dart';

void main() {
  // The internal value factory must not be reachable from a message class.
  final ReserveRequest value =
      ReserveRequest.fromValue(<dynamic>["o1", 2, null]);
  print(value);
}
`,
);

const dartPositiveRun = run("dart", ["analyze", dartPositive]);
check(
  "dart positive consumer analyzes with two conversions",
  dartPositiveRun.code === 0,
  dartPositiveRun.stdout.trim(),
);
const dartNegativeRun = run("dart", ["analyze", dartNegative]);
check(
  "dart excess fromValue rejected",
  dartNegativeRun.code !== 0 && dartNegativeRun.stdout.includes("fromValue"),
  dartNegativeRun.stdout.trim(),
);
}

// ── Python ─────────────────────────────────────────────────────────

if (wants("python")) {
const pythonRoot = `${workDir}/python`;
const python = Deno.env.get("CYROGRAF_PYTHON") ?? "python3";
const mypy = Deno.env.get("CYROGRAF_MYPY") ?? "mypy";
const env = { MYPYPATH: pythonRoot };

const positive = run(
  mypy,
  ["--strict", "--no-incremental", `${repo}/test/python/consumer_positive.py`],
  { cwd: pythonRoot, env },
);
check(
  "python positive consumer passes mypy strict with two conversions",
  positive.code === 0,
  positive.stderr.trim(),
);

const negative = run(
  mypy,
  ["--strict", "--no-incremental", `${repo}/test/python/consumer_negative.py`],
  { cwd: pythonRoot, env },
);
check(
  "python negative consumer rejected by mypy strict",
  negative.code !== 0 &&
    negative.stdout.includes("from_value") &&
    negative.stdout.includes("ReserveResponseReserved") &&
    negative.stdout.includes('"None"') &&
    negative.stdout.includes("upper"),
  (negative.stdout + negative.stderr).trim(),
);

const surface = run(
  python,
  [
    "-c",
    `import sys
sys.path.insert(0, ${JSON.stringify(pythonRoot)})
from generated_contracts import orders
from generated_contracts import _wire
assert "ReserveRequest" in orders.__all__
assert orders.__all__ == [name for name in orders.__all__ if not name.startswith("_")]
assert not any(name in orders.__all__ for name in ("to_drut", "from_drut", "_wire"))
assert _wire.CyrografError.__name__ == "CyrografError"
print("python surface ok")`,
  ],
  { cwd: pythonRoot },
);
check(
  "python __all__ exposes models without conversion helpers",
  surface.code === 0 && surface.stdout.includes("python surface ok"),
  surface.stderr.trim(),
);
}

// ── Java ───────────────────────────────────────────────────────────

if (wants("java")) {
const javaDir = `${workDir}/java`;
const classes = `${workDir}/java-classes`;
const javac = Deno.env.get("CYROGRAF_JAVAC") ?? "javac";
const java = Deno.env.get("CYROGRAF_JAVA") ?? "java";
const packageDir = `${javaDir}/src/main/java/generated_contracts`;
const generatedSources = [...Deno.readDirSync(packageDir)]
  .filter((entry) => entry.isFile && entry.name.endsWith(".java"))
  .map((entry) => `${packageDir}/${entry.name}`);

const generatedRun = run(javac, ["--release", "21", "-d", classes, ...generatedSources]);
check(
  "java generated sources compile with JDK 21",
  generatedRun.code === 0,
  generatedRun.stderr.trim(),
);

const positiveRun = run(javac, [
  "--release",
  "21",
  "-cp",
  classes,
  "-d",
  classes,
  `${repo}/test/java/ConsumerPositive.java`,
]);
check(
  "java positive consumer compiles with two conversions",
  positiveRun.code === 0,
  positiveRun.stderr.trim(),
);
const positiveExec = run(java, ["-cp", classes, "ConsumerPositive"]);
check(
  "java positive consumer runs",
  positiveExec.code === 0 && positiveExec.stdout.includes("java consumer ok"),
  positiveExec.stderr.trim(),
);

const negative = run(javac, [
  "--release",
  "21",
  "-cp",
  classes,
  "-d",
  classes,
  `${repo}/test/java/ConsumerNegative.java`,
]);
check(
  "java excess fromValue rejected",
  negative.code !== 0 && negative.stderr.includes("fromValue"),
  negative.stderr.trim(),
);

const wireNegative = run(javac, [
  "--release",
  "21",
  "-cp",
  classes,
  "-d",
  classes,
  `${repo}/test/java/WireNegative.java`,
]);
check(
  "java internal Wire runtime hidden outside the package",
  wireNegative.code !== 0 && wireNegative.stderr.includes("Wire"),
  wireNegative.stderr.trim(),
);
}

// ── C# ─────────────────────────────────────────────────────────────

if (wants("csharp")) {
const csDir = `${workDir}/csharp`;
const dotnet = Deno.env.get("CYROGRAF_DOTNET") ?? "dotnet";

const generatedRun = run(dotnet, ["build", `${csDir}/GeneratedContracts.csproj`, "-v", "q"]);
check(
  "csharp generated project compiles with the .NET SDK",
  generatedRun.code === 0,
  generatedRun.stderr.trim(),
);

function consumerProject(): string {
  return `<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net10.0</TargetFramework>
    <Nullable>enable</Nullable>
    <ImplicitUsings>disable</ImplicitUsings>
    <LangVersion>latest</LangVersion>
    <TreatWarningsAsErrors>true</TreatWarningsAsErrors>
  </PropertyGroup>
  <ItemGroup>
    <ProjectReference Include="../csharp/GeneratedContracts.csproj" />
  </ItemGroup>
</Project>`;
}

const positiveDir = `${workDir}/csharp-positive`;
Deno.mkdirSync(positiveDir, { recursive: true });
Deno.writeTextFileSync(`${positiveDir}/consumer.csproj`, consumerProject());
Deno.writeTextFileSync(
  `${positiveDir}/Main.cs`,
  `using GeneratedContracts.Orders;

public static class PositiveProgram
{
    public static void Main()
    {
        ReserveRequest value = ReserveRequest.FromDrut("[\\"o1\\",2,null]");
        string text = value.ToDrut();
        System.Console.WriteLine("csharp consumer ok " + text);
    }
}
`,
);
const positiveRun = run(dotnet, ["run", "--project", positiveDir, "-v", "q"]);
check(
  "csharp positive consumer compiles and runs with two conversions",
  positiveRun.code === 0 && positiveRun.stdout.includes("csharp consumer ok"),
  (positiveRun.stdout + positiveRun.stderr).trim(),
);

const negativeDir = `${workDir}/csharp-negative`;
Deno.mkdirSync(negativeDir, { recursive: true });
Deno.writeTextFileSync(`${negativeDir}/consumer.csproj`, consumerProject());
Deno.writeTextFileSync(
  `${negativeDir}/Main.cs`,
  `using GeneratedContracts.Orders;

public static class NegativeProgram
{
    public static void Main()
    {
        ReserveRequest value = ReserveRequest.FromValue("[]");
        System.Console.WriteLine(value);
    }
}
`,
);
const negativeRun = run(dotnet, ["build", negativeDir, "-v", "q"]);
check(
  "csharp excess FromValue rejected",
  negativeRun.code !== 0 &&
    (negativeRun.stdout + negativeRun.stderr).includes("FromValue"),
  (negativeRun.stdout + negativeRun.stderr).trim(),
);

const wireDir = `${workDir}/csharp-wire-negative`;
Deno.mkdirSync(wireDir, { recursive: true });
Deno.writeTextFileSync(`${wireDir}/consumer.csproj`, consumerProject());
Deno.writeTextFileSync(
  `${wireDir}/Main.cs`,
  `using GeneratedContracts;

public static class WireProgram
{
    public static void Main()
    {
        System.Console.WriteLine(Wire.ParseText("[]"));
    }
}
`,
);
const wireRun = run(dotnet, ["build", wireDir, "-v", "q"]);
check(
  "csharp internal Wire runtime hidden outside its assembly",
  wireRun.code !== 0 &&
    (wireRun.stdout + wireRun.stderr).includes("Wire"),
  (wireRun.stdout + wireRun.stderr).trim(),
);
}

// ── Rust ───────────────────────────────────────────────────────────

if (wants("rust")) {
const rust = Deno.env.get("CYROGRAF_RUST") ?? "cargo";

function rustProject(name: string, body: string, generated: string): string {
  const dir = `${workDir}/${name}`;
  Deno.mkdirSync(`${dir}/src`, { recursive: true });
  Deno.writeTextFileSync(
    `${dir}/Cargo.toml`,
    `[package]
name = "${name.replace(/-/g, "_")}"
version = "0.0.0"
edition = "2024"
rust-version = "1.85"
publish = false

[[bin]]
name = "${name.replace(/-/g, "_")}"
path = "src/main.rs"

[dependencies]
generated_contracts = { path = ${JSON.stringify(generated)} }
`,
  );
  Deno.writeTextFileSync(`${dir}/src/main.rs`, body);
  return dir;
}

const rustPositiveDir = rustProject(
  "rust-positive",
  `use generated_contracts::orders::ReserveRequest;

fn main() {
    let value = ReserveRequest::from_drut("[\\"o1\\",2,null]").expect("decode");
    let text = value.to_drut().expect("encode");
    println!("rust consumer ok {}", text);
}
`,
  "../rust",
);
const rustPositive = run(rust, ["run", "-q", "--manifest-path", `${rustPositiveDir}/Cargo.toml`]);
check(
  "rust positive consumer compiles and runs with two conversions",
  rustPositive.code === 0 && rustPositive.stdout.includes("rust consumer ok"),
  (rustPositive.stdout + rustPositive.stderr).trim(),
);

const rustHelperDir = rustProject(
  "rust-helper-negative",
  `use generated_contracts::orders::ReserveRequest;

fn main() {
    let value = ReserveRequest::from_drut("[\\"o1\\",2,null]").unwrap();
    let _ = value.encode_value();
}
`,
  "../rust",
);
const rustHelper = run(rust, ["build", "--manifest-path", `${rustHelperDir}/Cargo.toml`]);
check(
  "rust pub(crate) value helper rejected outside the crate",
  rustHelper.code !== 0 &&
    (rustHelper.stdout + rustHelper.stderr).includes("encode_value"),
  (rustHelper.stdout + rustHelper.stderr).trim(),
);

const rustWireDir = rustProject(
  "rust-wire-negative",
  `fn main() {
    let _ = generated_contracts::wire::parse_text("[]");
}
`,
  "../rust",
);
const rustWire = run(rust, ["build", "--manifest-path", `${rustWireDir}/Cargo.toml`]);
check(
  "rust internal wire runtime hidden outside the crate",
  rustWire.code !== 0 && (rustWire.stdout + rustWire.stderr).includes("wire"),
  (rustWire.stdout + rustWire.stderr).trim(),
);
}

// ── OCaml ──────────────────────────────────────────────────────────

if (wants("ocaml")) {
const ocamlCases: [string, string, string][] = [
  ["positive", "test/api_negative/positive.exe", ""],
  ["hidden value codec", "test/api_negative/negative_member.exe", "encode_value"],
  ["absent Cyrograf.Codec", "test/api_negative/negative_codec.exe", "Codec"],
  ["absent Contract module", "test/api_negative/negative_contract.exe", "Contract"],
];
for (const [label, target, expected] of ocamlCases) {
  const result = run("dune", ["build", target], { cwd: repo });
  if (expected === "") {
    check(`ocaml ${label} compiles`, result.code === 0, result.stderr.trim());
  } else {
    check(
      `ocaml negative ${label} rejected`,
      result.code !== 0 && result.stderr.includes(expected),
      result.stderr.trim(),
    );
  }
}
}

console.log(`api surface: ${failures} failure(s)`);
if (failures > 0) Deno.exit(1);