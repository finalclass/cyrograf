// Keeps the TextMate grammars as the single source of truth.
//
// The canonical native grammar lives in editors/shared/cyrograf.tmLanguage.json
// and the Markdown fence adapter in
// editors/shared/cyrograf.markdown.tmLanguage.json. The VS Code extension and
// the JetBrains TextMate bundle consume byte-identical copies so no editor
// maintains a second, hand-edited grammar. The Markdown adapter embeds
// `source.cyrograf`; it is not a second lexer.
//
// Usage:
//   deno run --allow-read --allow-write editors/shared/sync.ts
//   deno run --allow-read editors/shared/sync.ts --check

const here = new URL(".", import.meta.url);

interface Pair {
  source: URL;
  targets: URL[];
}

const pairs: Pair[] = [
  {
    source: new URL("cyrograf.tmLanguage.json", here),
    targets: [
      new URL("../vscode/syntaxes/cyrograf.tmLanguage.json", here),
      new URL("../jetbrains/Cyrograf.tmBundle/Syntaxes/cyrograf.tmLanguage.json", here),
    ],
  },
  {
    source: new URL("cyrograf.markdown.tmLanguage.json", here),
    targets: [
      new URL("../vscode/syntaxes/cyrograf.markdown.tmLanguage.json", here),
    ],
  },
];

const decoder = new TextDecoder();

function fail(message: string): never {
  console.error(message);
  Deno.exit(1);
}

function equal(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false;
  for (let i = 0; i < a.length; i += 1) {
    if (a[i] !== b[i]) return false;
  }
  return true;
}

const check = Deno.args.includes("--check");

for (const pair of pairs) {
  const source = await Deno.readFile(pair.source);
  JSON.parse(decoder.decode(source));
  for (const target of pair.targets) {
    let existing: Uint8Array | null = null;
    try {
      existing = await Deno.readFile(target);
    } catch (error) {
      if (!(error instanceof Deno.errors.NotFound)) throw error;
    }

    if (check) {
      if (existing === null || !equal(source, existing)) {
        fail(`grammar copy is missing or out of date: ${target.pathname}`);
      }
    } else {
      await Deno.mkdir(new URL(".", target), { recursive: true });
      await Deno.writeFile(target, source);
    }
  }
}

if (check) console.log("textmate grammar copies are in sync");