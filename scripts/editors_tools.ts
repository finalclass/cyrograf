const home = Deno.env.get("HOME");
if (!home) throw new Error("HOME is not set");

const root = `${home}/.cache/cyrograf-editors`;
const tools = `${root}/tools`;
const elpa = `${root}/elpa`;
await Deno.mkdir(root, { recursive: true });
const tmp = await Deno.makeTempDir({ dir: root, prefix: "fetch-" });

const neovim = {
  archive: "nvim-linux-x86_64.tar.gz",
  url: "https://github.com/neovim/neovim/releases/download/v0.11.2/nvim-linux-x86_64.tar.gz",
  sha256: "a9b24157672eb218ff3e33ef3f8c08db26f8931c5c04bdb0e471371dd1dfe63e",
  binary: `${tools}/nvim-linux-x86_64/bin/nvim`,
};

const markdownMode = {
  archive: "markdown-mode-v2.8.tar.gz",
  url: "https://github.com/jrblevin/markdown-mode/archive/refs/tags/v2.8.tar.gz",
  sha256: "8252904252f771019c0b17e38be07cc8893e39da50e58dc5142dca50b0dd2dee",
  file: "markdown-mode-2.8/markdown-mode.el",
  target: `${elpa}/markdown-mode.el`,
  fileSha256: "73a686707d3e4044b475b5047af9e62c1d3810d4ee5e1002b52782d8bccb6d36",
};

const yegappanLsp = {
  commit: "58eac06e81bad174cfa897614ae01adf0d31d10a",
  archive: "yegappan-lsp.tar.gz",
  url: "https://codeload.github.com/yegappan/lsp/tar.gz/58eac06e81bad174cfa897614ae01adf0d31d10a",
  sha256: "3c7d0eeb410708b0096251401da4a4290e10b3aff233a75358468b69c0f1d9cb",
  target: `${tools}/yegappan-lsp`,
};

function exists(path: string): boolean {
  try {
    return Deno.statSync(path).isFile;
  } catch (error) {
    if (error instanceof Deno.errors.NotFound) return false;
    throw error;
  }
}

function existsAny(path: string): boolean {
  try {
    Deno.statSync(path);
    return true;
  } catch (error) {
    if (error instanceof Deno.errors.NotFound) return false;
    throw error;
  }
}

async function sha256(path: string): Promise<string> {
  const data = await Deno.readFile(path);
  const digest = await crypto.subtle.digest("SHA-256", data);
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

async function download(url: string, destination: string): Promise<void> {
  const response = await fetch(url);
  if (!response.ok || !response.body) {
    throw new Error(`cannot download ${url}: ${response.status}`);
  }
  const file = await Deno.open(destination, { create: true, write: true, truncate: true });
  await response.body.pipeTo(file.writable);
}

function extract(archive: string, directory: string): void {
  const status = new Deno.Command("tar", {
    args: ["-xzf", archive, "-C", directory],
    stdout: "null",
    stderr: "inherit",
  }).outputSync();
  if (!status.success) throw new Error(`tar failed for ${archive}`);
}

await Deno.mkdir(tools, { recursive: true });
await Deno.mkdir(elpa, { recursive: true });

if (exists(neovim.binary)) {
  console.log(`neovim already present at ${neovim.binary}`);
} else {
  const archive = `${tmp}/${neovim.archive}`;
  await download(neovim.url, archive);
  const digest = await sha256(archive);
  if (digest !== neovim.sha256) {
    throw new Error(`neovim checksum mismatch: ${digest}`);
  }
  extract(archive, tools);
  if (!exists(neovim.binary)) throw new Error("neovim archive did not contain the binary");
  console.log(`installed neovim 0.11.2 at ${neovim.binary}`);
}

if (exists(markdownMode.target) && (await sha256(markdownMode.target)) === markdownMode.fileSha256) {
  console.log(`markdown-mode already present at ${markdownMode.target}`);
} else {
  const archive = `${tmp}/${markdownMode.archive}`;
  await download(markdownMode.url, archive);
  const digest = await sha256(archive);
  if (digest !== markdownMode.sha256) {
    throw new Error(`markdown-mode checksum mismatch: ${digest}`);
  }
  const unpacked = `${tmp}/markdown`;
  await Deno.mkdir(unpacked, { recursive: true });
  extract(archive, unpacked);
  const file = `${unpacked}/${markdownMode.file}`;
  if ((await sha256(file)) !== markdownMode.fileSha256) {
    throw new Error("markdown-mode.el checksum mismatch");
  }
  await Deno.copyFile(file, markdownMode.target);
  console.log(`installed markdown-mode 2.8 at ${markdownMode.target}`);
}

if (existsAny(`${yegappanLsp.target}/plugin/lsp.vim`)) {
  console.log(`yegappan/lsp already present at ${yegappanLsp.target}`);
} else {
  const archive = `${tmp}/${yegappanLsp.archive}`;
  await download(yegappanLsp.url, archive);
  const digest = await sha256(archive);
  if (digest !== yegappanLsp.sha256) {
    throw new Error(`yegappan/lsp checksum mismatch: ${digest}`);
  }
  await Deno.remove(yegappanLsp.target, { recursive: true }).catch(() => undefined);
  await Deno.mkdir(yegappanLsp.target, { recursive: true });
  const status = new Deno.Command("tar", {
    args: ["-xzf", archive, "-C", yegappanLsp.target, "--strip-components=1"],
    stdout: "null",
    stderr: "inherit",
  }).outputSync();
  if (!status.success) throw new Error(`tar failed for ${archive}`);
  if (!exists(`${yegappanLsp.target}/plugin/lsp.vim`)) {
    throw new Error("yegappan/lsp archive did not contain plugin/lsp.vim");
  }
  console.log(
    `installed yegappan/lsp ${yegappanLsp.commit.slice(0, 12)} at ${yegappanLsp.target}`,
  );
}

await Deno.remove(tmp, { recursive: true });