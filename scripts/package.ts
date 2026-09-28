// Build the 0.1.0 release artifacts in _build/release/.
//
// The script assembles a source archive, a Linux x86_64 program archive, the
// editor packages (including the VS Code .vsix) and a SHA-256 manifest. It does
// not tag, publish or upload anything.

const rootUrl = new URL("../", import.meta.url);
const root = Deno.realPathSync(rootUrl);

const encoder = new TextEncoder();
const decoder = new TextDecoder();

function run(
  command: string,
  args: string[],
  options: { cwd?: string; env?: Record<string, string>; allowFailure?: boolean } = {},
): { code: number; stdout: string; stderr: string } {
  const output = new Deno.Command(command, {
    args,
    cwd: options.cwd,
    env: options.env,
    stdout: "piped",
    stderr: "piped",
  }).outputSync();
  const result = {
    code: output.code,
    stdout: decoder.decode(output.stdout),
    stderr: decoder.decode(output.stderr),
  };
  if (result.code !== 0 && !options.allowFailure) {
    throw new Error(
      `${command} ${args.join(" ")} failed with code ${result.code}\n${result.stderr}`,
    );
  }
  return result;
}

function remove(path: string): void {
  try {
    Deno.removeSync(path, { recursive: true });
  } catch (error) {
    if (!(error instanceof Deno.errors.NotFound)) throw error;
  }
}

function readVersion(): string {
  const text = Deno.readTextFileSync(`${root}/bin/version.ml`);
  const match = /let\s+value\s*=\s*"([^"]+)"/.exec(text);
  if (!match) throw new Error("cannot read the version from bin/version.ml");
  return match[1];
}

function checkVersionAgreement(version: string): void {
  const pkg = JSON.parse(Deno.readTextFileSync(`${root}/editors/vscode/package.json`)) as {
    version?: string;
  };
  if (pkg.version !== version) {
    throw new Error(`editors/vscode/package.json version ${pkg.version} != ${version}`);
  }
  const project = Deno.readTextFileSync(`${root}/dune-project`);
  const projectVersion = /\(version\s+([0-9][^)\s]*)\)/.exec(project);
  if (projectVersion && projectVersion[1] !== version) {
    throw new Error(`dune-project version ${projectVersion[1]} != ${version}`);
  }
}

function tar(archive: string, contents: string, cwd: string): void {
  run("tar", [
    "--sort=name",
    "--owner=0",
    "--group=0",
    "--numeric-owner",
    "--mtime=@0",
    "--use-compress-program=gzip -n",
    "-cf",
    archive,
    "-C",
    cwd,
    ...contents.split("\u0000").filter((item) => item.length > 0),
  ]);
}

function walkFiles(directory: string, prefix: string): string[] {
  const result: string[] = [];
  for (const entry of Deno.readDirSync(directory)) {
    const path = `${directory}/${entry.name}`;
    const relative = `${prefix}/${entry.name}`;
    if (entry.isDirectory) result.push(...walkFiles(path, relative));
    else if (entry.isFile) result.push(relative);
  }
  return result;
}

function sha256(path: string): string {
  const output = run("sha256sum", [path]).stdout;
  const match = /^([0-9a-f]{64})/.exec(output);
  if (!match) throw new Error(`cannot hash ${path}`);
  return match[1];
}

const version = readVersion();
checkVersionAgreement(version);

const release = `${root}/_build/release`;
remove(release);
Deno.mkdirSync(release, { recursive: true });
const stage = `${release}/stage`;
Deno.mkdirSync(stage, { recursive: true });

const artifacts: string[] = [];

// ── Source archive ─────────────────────────────────────────────────
const sourceName = `cyrograf-${version}-src.tar.gz`;
{
  const prefix = `cyrograf-${version}`;
  const sourceStage = `${stage}/src`;
  const listing = run("git", ["ls-files", "--cached", "--others", "--exclude-standard", "-z"], {
    cwd: root,
  }).stdout;
  const files = listing.split("\u0000").filter((file) => file.length > 0);
  const excluded = (file: string): boolean =>
    file.startsWith(".axe/") || file.startsWith(".git/") || file === "AGENTS.md";
  let copied = 0;
  for (const file of files) {
    if (excluded(file)) continue;
    const target = `${sourceStage}/${prefix}/${file}`;
    Deno.mkdirSync(target.slice(0, target.lastIndexOf("/")), { recursive: true });
    const info = Deno.statSync(`${root}/${file}`);
    if (!info.isFile) continue;
    Deno.copyFileSync(`${root}/${file}`, target);
    Deno.chmodSync(target, info.mode ?? 0o644);
    copied += 1;
  }
  if (copied === 0) throw new Error("the source archive is empty");
  tar(`${release}/${sourceName}`, prefix, sourceStage);
  artifacts.push(sourceName);
}

// ── Program archive for Linux x86_64 ───────────────────────────────
const programName = `cyrograf-${version}-linux-x86_64.tar.gz`;
{
  const prefix = `cyrograf-${version}-linux-x86_64`;
  const programStage = `${stage}/program`;
  Deno.mkdirSync(`${programStage}/${prefix}`, { recursive: true });
  const binary = `${root}/_build/default/bin/contract_cli.exe`;
  if (!Deno.statSync(binary).isFile) throw new Error("build the program first with `make build`");
  Deno.copyFileSync(binary, `${programStage}/${prefix}/cyrograf`);
  Deno.chmodSync(`${programStage}/${prefix}/cyrograf`, 0o755);
  Deno.copyFileSync(`${root}/LICENSE`, `${programStage}/${prefix}/LICENSE`);
  Deno.copyFileSync(`${root}/README.md`, `${programStage}/${prefix}/README.md`);
  tar(`${release}/${programName}`, prefix, programStage);
  artifacts.push(programName);
}

// ── Editor packages ────────────────────────────────────────────────
const editorsName = `cyrograf-${version}-editors.tar.gz`;
let vsixName: string | null = null;
{
  const prefix = `cyrograf-${version}-editors`;
  const editorsStage = `${stage}/editors`;
  for (const item of ["emacs", "vim", "neovim", "jetbrains", "shared", "example", "README.md"]) {
    const source = `${root}/editors/${item}`;
    const target = `${editorsStage}/${prefix}/${item}`;
    if (Deno.statSync(source).isDirectory) {
      Deno.mkdirSync(target, { recursive: true });
      for (const relative of walkFiles(source, "")) {
        const next = `${target}${relative}`;
        Deno.mkdirSync(next.slice(0, next.lastIndexOf("/")), { recursive: true });
        Deno.copyFileSync(source + relative, next);
      }
    } else {
      Deno.copyFileSync(source, target);
    }
  }

  const vscode = `${root}/editors/vscode`;
  const npm = "npm";
  if (!Deno.statSync(`${vscode}/node_modules`).isDirectory) {
    run(npm, ["ci"], { cwd: vscode });
  }
  run(npm, ["run", "compile"], { cwd: vscode });
  const vsix = `cyrograf-vscode-${version}.vsix`;
  run(npm, ["run", "package", "--", "--out", `${release}/${vsix}`], { cwd: vscode });
  if (!Deno.statSync(`${release}/${vsix}`).isFile) {
    throw new Error("vsce did not produce the .vsix");
  }
  Deno.copyFileSync(`${release}/${vsix}`, `${editorsStage}/${prefix}/${vsix}`);
  tar(`${release}/${editorsName}`, prefix, editorsStage);
  artifacts.push(editorsName);
  artifacts.push(vsix);
  vsixName = vsix;
}

// ── SHA-256 manifest ───────────────────────────────────────────────
const sums: string[] = [];
for (const artifact of artifacts.sort()) {
  sums.push(`${sha256(`${release}/${artifact}`)}  ${artifact}`);
}
Deno.writeTextFileSync(`${release}/SHA256SUMS`, sums.join("\n") + "\n");

remove(stage);

console.log(`packaged cyrograf ${version} into ${release}`);
for (const line of sums) console.log(`  ${line}`);