// Map the pinned invalid-schemas corpus onto real compiler validation.
//
// The corpus notation is not a Cyrograf input. Each expressible defect is
// rewritten as a native .cyrograf project and run through `cyrograf check`,
// which must reject it. A case whose defect lives only in the test notation is
// reported as not expressible, never as a pass.

interface SchemaCase {
  id: string;
  schema: unknown;
  type: string;
  reason: string;
}

interface Expresssible {
  files: Record<string, string>;
}

const expressible: Record<string, Expresssible> = {
  schema_optional_void: { files: { "Bad.cyrograf": "struct Bad {\n  value?: Void\n}\n" } },
  schema_empty_variant: { files: { "Bad.cyrograf": "variant Bad {\n}\n" } },
  schema_duplicate_field: {
    files: { "Bad.cyrograf": "struct Bad {\n  x: Int\n  x: String\n}\n" },
  },
  schema_duplicate_tag: {
    files: { "Bad.cyrograf": "variant Bad {\n  Same(Int)\n  Same(String)\n}\n" },
  },
  schema_unresolved_reference: {
    files: { "Bad.cyrograf": "struct Bad {\n  x: Missing\n}\n" },
  },
  schema_unresolved_root: {
    files: { "Bad.cyrograf": "struct Bad {\n  x: Missing\n}\n" },
  },
  schema_recursive_list: {
    files: { "Bad.cyrograf": "struct Bad {\n  children: List<Bad>\n}\n" },
  },
  schema_mutual_cycle: {
    files: {
      "A.cyrograf": "struct A {\n  b: B\n}\n",
      "B.cyrograf": "variant B {\n  Again(A)\n}\n",
    },
  },
  schema_optional_variant_payload: {
    files: { "Bad.cyrograf": "variant Bad {\n  Maybe(String?)\n}\n" },
  },
  schema_nested_optional: {
    files: { "Bad.cyrograf": "struct Bad {\n  x: Int??\n}\n" },
  },
  schema_optional_list_element: {
    files: { "Bad.cyrograf": "struct Bad {\n  x: List<Int?>\n}\n" },
  },
  schema_two_kinds: {
    files: { "Bad.cyrograf": "struct Bad {\n}\nvariant Bad {\n  Empty\n}\n" },
  },
};

const unexpressible: Record<string, string> = {
  schema_optional_not_boolean:
    "fixture notation: the defect is a non-boolean JSON flag, not a contract declaration",
};

const [cyrograf, resultOut] = Deno.args;
if (!cyrograf || !resultOut) {
  console.error("usage: schemas.ts CYROGRAF_BIN OUT_JSON");
  Deno.exit(2);
}

const here = new URL(".", import.meta.url).pathname;
const cases = JSON.parse(
  Deno.readTextFileSync(`${here}/../fixtures/drut/invalid-schemas.json`),
) as SchemaCase[];

const results: { id: string; status: string; detail?: string }[] = [];

for (const item of cases) {
  if (!(item.id in expressible)) {
    results.push({
      id: item.id,
      status: "unsupported",
      detail: unexpressible[item.id] ?? "no native mapping",
    });
    continue;
  }
  const directory = Deno.makeTempDirSync({ prefix: "cyrograf-schema-" });
  try {
    for (const [name, contents] of Object.entries(expressible[item.id].files)) {
      Deno.writeTextFileSync(`${directory}/${name}`, contents);
    }
    const command = new Deno.Command(cyrograf, {
      args: ["check", directory],
      stdout: "null",
      stderr: "null",
    });
    const output = command.outputSync();
    if (output.code === 0) {
      results.push({
        id: item.id,
        status: "failed",
        detail: "compiler accepted an invalid schema",
      });
    } else {
      results.push({ id: item.id, status: "rejected" });
    }
  } finally {
    Deno.removeSync(directory, { recursive: true });
  }
}

Deno.writeTextFileSync(resultOut, JSON.stringify(results, null, 2));
const rejected = results.filter((item) => item.status === "rejected").length;
const unsupported = results.filter((item) => item.status === "unsupported").length;
const failed = results.filter((item) => item.status === "failed").length;
console.log(
  `drut invalid-schemas: ${rejected} rejected by the compiler, ` +
    `${unsupported} not expressible, ${failed} wrongly accepted`,
);
for (const item of results) {
  if (item.status !== "rejected") {
    console.log(`  ${item.status} ${item.id}: ${item.detail}`);
  }
}
if (failed > 0) Deno.exit(1);