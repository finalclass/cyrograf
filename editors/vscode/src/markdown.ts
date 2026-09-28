import {
  INITIAL,
  Registry,
  type IGrammar,
  type IRawGrammar,
} from "vscode-textmate";
import { loadWASM, OnigScanner, OnigString } from "vscode-oniguruma";

export interface MarkdownItLike {
  utils: { escapeHtml(text: string): string };
  renderer: {
    rules: Record<string, unknown>;
  };
  renderToken(tokens: unknown[], idx: number, options: unknown): string;
  use(plugin: unknown): MarkdownItLike;
}

let oniguruma: Promise<void> | undefined;

async function ensureOniguruma(wasm: ArrayBuffer): Promise<void> {
  if (!oniguruma) oniguruma = loadWASM(wasm);
  await oniguruma;
}

function parseGrammar(source: string): IRawGrammar {
  return JSON.parse(source) as IRawGrammar;
}

function createRegistry(
  grammars: Record<string, IRawGrammar>,
  injections: Record<string, string[]> = {},
): Registry {
  return new Registry({
    onigLib: Promise.resolve({
      createOnigScanner: (patterns: string[]) => new OnigScanner(patterns),
      createOnigString: (text: string) => new OnigString(text),
    }),
    loadGrammar: (scopeName: string) => {
      const grammar = grammars[scopeName];
      return Promise.resolve(grammar ?? null);
    },
    getInjections: (scopeName: string) => injections[scopeName],
  });
}

function tokenClass(scopes: string[]): string | null {
  for (let i = scopes.length - 1; i >= 0; i -= 1) {
    const head = scopes[i].split(".")[0];
    if (head !== "source") return `cy-${head}`;
  }
  return null;
}

export interface PreviewHighlighter {
  render(content: string, escape: (text: string) => string): string;
}

export async function createPreviewHighlighter(
  source: string,
  wasm: ArrayBuffer,
): Promise<PreviewHighlighter> {
  await ensureOniguruma(wasm);
  const grammar = parseGrammar(source);
  const registry = createRegistry({ [grammar.scopeName]: grammar });
  const loaded = await registry.loadGrammar(grammar.scopeName);
  if (!loaded) throw new Error("cannot load the Cyrograf TextMate grammar");
  return new TextMateHighlighter(loaded);
}

export async function createInjectionTokenizer(
  nativeSource: string,
  injectionSource: string,
  markdownSource: string,
  markdownScope: string,
  wasm: ArrayBuffer,
): Promise<IGrammar> {
  await ensureOniguruma(wasm);
  const native = parseGrammar(nativeSource);
  const injection = parseGrammar(injectionSource);
  const markdown = parseGrammar(markdownSource);
  const registry = createRegistry(
    {
      [native.scopeName]: native,
      [injection.scopeName]: injection,
      [markdownScope]: markdown,
    },
    { [markdownScope]: [injection.scopeName] },
  );
  const loaded = await registry.loadGrammar(markdownScope);
  if (!loaded) throw new Error(`cannot load the ${markdownScope} grammar`);
  return loaded;
}

class TextMateHighlighter implements PreviewHighlighter {
  constructor(private readonly grammar: IGrammar) {}

  render(content: string, escape: (text: string) => string): string {
    const lines = content.replace(/\r\n?/g, "\n").split("\n");
    let stack = INITIAL;
    const rows: string[] = [];
    for (const line of lines) {
      const result = this.grammar.tokenizeLine(line, stack);
      stack = result.ruleStack;
      let row = "";
      for (const token of result.tokens) {
        const text = line.slice(token.startIndex, token.endIndex);
        const className = tokenClass(token.scopes);
        row += className ? `<span class="${className}">${escape(text)}</span>` : escape(text);
      }
      rows.push(row);
    }
    return rows.join("\n");
  }
}

export function cyrografFencePlugin(
  highlighter: PreviewHighlighter,
): (md: MarkdownItLike) => MarkdownItLike {
  return (md: MarkdownItLike): MarkdownItLike => {
    const previous = md.renderer.rules.fence as
      | ((tokens: unknown[], idx: number, options: unknown, env: unknown, self: MarkdownItLike) => string)
      | undefined;
    md.renderer.rules.fence = (
      tokens: unknown[],
      idx: number,
      options: unknown,
      env: unknown,
      self: unknown,
    ): string => {
      const token = tokens[idx] as { info?: string; content?: string };
      const language = (token.info ?? "").trim().split(/\s+/)[0];
      if (language !== "cyrograf") {
        return previous
          ? previous(tokens, idx, options, env, self as MarkdownItLike)
          : (self as MarkdownItLike).renderToken(tokens, idx, options);
      }
      const html = highlighter.render(token.content ?? "", (text) => md.utils.escapeHtml(text));
      return `<pre class="cyrograf"><code class="language-cyrograf">${html}\n</code></pre>`;
    };
    return md;
  };
}