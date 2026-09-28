// Merge the pinned Drut adapter plan with the per-target runner results into a
// single report that distinguishes executed cases, rejected invalid cases and
// the declared ASCII limitation per ID and per target.

interface Plan {
  revision: string;
  valid: {
    corpus: number;
    regressions: number;
    total: number;
    supported: number;
    unsupported: { id: string; reason: string }[];
  };
  invalid: {
    corpus: number;
    regressions: number;
    total: number;
    supported: number;
    unsupported: { id: string; reason: string }[];
  };
  invalid_schemas: { total: number; ids: string[] };
}

interface Result {
  id: string;
  status: string;
}

const [
  planPath,
  tsPath,
  ocamlPath,
  goPath,
  dartPath,
  pythonPath,
  javaPath,
  csharpPath,
  rustPath,
  schemaPath,
  outPath,
] = Deno.args;

function read<T>(path: string): T {
  return JSON.parse(Deno.readTextFileSync(path)) as T;
}

const plan = read<Plan>(planPath);
const targets: Record<string, Result[]> = {
  typescript: read<Result[]>(tsPath),
  ocaml: read<Result[]>(ocamlPath),
  go: read<Result[]>(goPath),
  dart: read<Result[]>(dartPath),
  python: read<Result[]>(pythonPath),
  java: read<Result[]>(javaPath),
  csharp: read<Result[]>(csharpPath),
  rust: read<Result[]>(rustPath),
};
const schemas = read<{ id: string; status: string; detail?: string }[]>(schemaPath);

const perTarget: Record<string, Record<string, string>> = {};
const summary: Record<
  string,
  {
    public_executed: number;
    runtime_executed: number;
    public_rejected: number;
    runtime_rejected: number;
    inexpressible: number;
  }
> = {};
for (const [target, results] of Object.entries(targets)) {
  perTarget[target] = {};
  const counts = {
    public_executed: 0,
    runtime_executed: 0,
    public_rejected: 0,
    runtime_rejected: 0,
    inexpressible: 0,
  };
  for (const item of results) {
    perTarget[target][item.id] = item.status;
    switch (item.status) {
      case "executed":
        counts.public_executed++;
        break;
      case "executed-runtime":
        counts.runtime_executed++;
        break;
      case "rejected":
        counts.public_rejected++;
        break;
      case "rejected-runtime":
        counts.runtime_rejected++;
        break;
      case "inexpressible":
        counts.inexpressible++;
        break;
      default:
        console.error(`drut report: ${target} has an unknown status ${item.status}`);
        Deno.exit(1);
    }
  }
  summary[target] = counts;
}

const perId: Record<string, Record<string, string>> = {};
for (const item of plan.valid.unsupported) {
  perId[item.id] = { status: "unsupported-ascii" };
}
for (const target of Object.keys(targets)) {
  for (const [id, status] of Object.entries(perTarget[target])) {
    perId[id] = perId[id] ?? {};
    perId[id][target] = status;
  }
}

const report = {
  revision: plan.revision,
  valid_cases: plan.valid.total + plan.valid.unsupported.length,
  invalid_cases: plan.invalid.total + plan.invalid.unsupported.length,
  targets: summary,
  valid_unsupported: plan.valid.unsupported,
  invalid_unsupported: plan.invalid.unsupported,
  invalid_schemas: schemas,
  per_id: perId,
};
Deno.writeTextFileSync(outPath, JSON.stringify(report, null, 2));

console.log(
  `drut report: valid ${plan.valid.total} cases, invalid ${plan.invalid.total} cases`,
);
for (const [target, counts] of Object.entries(summary)) {
  console.log(
    `  ${target}: public ${counts.public_executed} executed/${counts.public_rejected} rejected, ` +
      `runtime ${counts.runtime_executed} executed/${counts.runtime_rejected} rejected, ` +
      `inexpressible ${counts.inexpressible}`,
  );
}
for (const target of Object.keys(summary)) {
  const counts = summary[target];
  const validAccounted = counts.public_executed + counts.runtime_executed;
  const invalidAccounted =
    counts.public_rejected + counts.runtime_rejected + counts.inexpressible;
  if (validAccounted !== plan.valid.total) {
    console.error(`drut report: ${target} valid cases are not fully accounted for`);
    Deno.exit(1);
  }
  if (invalidAccounted !== plan.invalid.total) {
    console.error(`drut report: ${target} invalid cases are not fully accounted for`);
    Deno.exit(1);
  }
}
const schemaRejected = schemas.filter((item) => item.status === "rejected").length;
if (schemaRejected + schemas.filter((item) => item.status === "unsupported").length !== schemas.length) {
  console.error("drut report: invalid-schemas not fully accounted for");
  Deno.exit(1);
}