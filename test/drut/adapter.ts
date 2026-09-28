// Adapter from the pinned Drut conformance corpus to Cyrograf test cases.
//
// The corpus schema notation is not a Cyrograf compiler input. This adapter
// maps each case to a root type descriptor that the shared language runners
// interpret through the public runtime: named declarations become references
// to the generated fixtures, while primitive, list and record roots are
// exercised directly. Byte-level (wire_hex) vectors keep their original bytes.
// Only declaration names outside the ASCII contract grammar stay unsupported.

interface CorpusCase {
  id: string;
  type: unknown;
  wire?: string;
  wire_hex?: string;
  value?: unknown;
  reason?: string;
}

interface ValidCase {
  id: string;
  type: string;
  wire: string;
  value: unknown;
}

interface Descriptor {
  id: string;
  type: unknown;
  category: "public" | "runtime";
  utf8_invalid?: boolean;
  wire?: string;
  wire_hex?: string;
  value?: unknown;
}

interface Unsuitable {
  id: string;
  type: string;
  reason: string;
}

const declared: Record<string, string> = {
  ReserveRequest: "Orders.ReserveRequest",
  Reservation: "Orders.Reservation",
  Problem: "Orders.Problem",
  ReserveResponse: "Orders.ReserveResponse",
  ReservationBatch: "Orders.ReservationBatch",
  ListBox: "Orders.ListBox",
  ResponseBox: "Orders.ResponseBox",
  Guard: "Orders.Guard",
  Scalars: "Orders.Scalars",
  Empty: "Common.Empty",
  VoidBox: "Common.VoidBox",
  UserCtx: "Common.UserCtx",
  Wrapper: "Common.Wrapper",
  Blob: "Common.Blob",
};

const primitives = new Set([
  "void",
  "int",
  "float",
  "bool",
  "string",
  "date",
  "record",
]);

function readJson(path: string): unknown {
  return JSON.parse(Deno.readTextFileSync(path));
}

function typeLabel(type: unknown): string {
  return typeof type === "string" ? type : JSON.stringify(type);
}

function descriptor(type: unknown): { desc: unknown } | { reason: string } {
  if (typeof type === "string") {
    if (primitives.has(type)) return { desc: type };
    const qualified = declared[type];
    if (qualified !== undefined) return { desc: qualified };
    if (/^[A-Z]/.test(type)) {
      return {
        reason: "frontend: declaration name is outside the ASCII contract grammar",
      };
    }
    return { reason: `frontend: unknown primitive root type ${type}` };
  }
  if (type !== null && typeof type === "object" && "list" in (type as object)) {
    const inner = (type as { list: unknown }).list;
    const mapped = descriptor(inner);
    if ("reason" in mapped) return mapped;
    return { desc: { list: mapped.desc } };
  }
  return { reason: `frontend: unsupported root type expression ${typeLabel(type)}` };
}

function hexBytes(hex: string): Uint8Array {
  const bytes = new Uint8Array(hex.length / 2);
  for (let index = 0; index < bytes.length; index++) {
    bytes[index] = parseInt(hex.slice(index * 2, index * 2 + 2), 16);
  }
  return bytes;
}

function isUtf8Text(hex: string): boolean {
  try {
    new TextDecoder("utf-8", { fatal: true, ignoreBOM: true }).decode(hexBytes(hex));
    return true;
  } catch {
    return false;
  }
}

function namedDescriptor(type: unknown): boolean {
  return typeof type === "string" && !primitives.has(type);
}

function classify(item: CorpusCase): Descriptor | Unsuitable {
  const mapped = descriptor(item.type);
  if ("reason" in mapped) {
    return { id: item.id, type: typeLabel(item.type), reason: mapped.reason };
  }
  const category: "public" | "runtime" = namedDescriptor(item.type)
    ? "public"
    : "runtime";
  const result: Descriptor = { id: item.id, type: mapped.desc, category };
  if (item.wire !== undefined) result.wire = item.wire;
  if (item.wire_hex !== undefined) {
    result.wire_hex = item.wire_hex;
    if (!isUtf8Text(item.wire_hex)) result.utf8_invalid = true;
  }
  if (item.value !== undefined) result.value = item.value;
  return result;
}

function partition(cases: CorpusCase[]) {
  const mapped: Descriptor[] = [];
  const unsupported: Unsuitable[] = [];
  for (const item of cases) {
    const result = classify(item);
    if ("reason" in result) unsupported.push(result);
    else mapped.push(result);
  }
  return { mapped, unsupported };
}

const [validOut, invalidOut, reportOut] = Deno.args;
const here = new URL(".", import.meta.url).pathname;
const valid = readJson(`${here}/../fixtures/drut/valid.json`) as ValidCase[];
const invalid = readJson(`${here}/../fixtures/drut/invalid.json`) as CorpusCase[];
const invalidSchemas = readJson(
  `${here}/../fixtures/drut/invalid-schemas.json`,
) as CorpusCase[];
const regressions = readJson(`${here}/../fixtures/drut/regressions.json`) as {
  valid: ValidCase[];
  invalid: CorpusCase[];
};

const validPart = partition([...valid, ...regressions.valid]);
const invalidPart = partition([...invalid, ...regressions.invalid]);

function emit(path: string, cases: Descriptor[]) {
  Deno.writeTextFileSync(path, JSON.stringify(cases, null, 2));
}

emit(validOut, validPart.mapped);
emit(invalidOut, invalidPart.mapped);

const report = {
  revision: "0d4b4e1e7ef3d7fffe095bfa9b2d88b564e9da8a",
  valid: {
    corpus: valid.length,
    regressions: regressions.valid.length,
    total: validPart.mapped.length,
    supported: validPart.mapped.length,
    unsupported: validPart.unsupported,
  },
  invalid: {
    corpus: invalid.length,
    regressions: regressions.invalid.length,
    total: invalidPart.mapped.length,
    supported: invalidPart.mapped.length,
    unsupported: invalidPart.unsupported,
  },
  invalid_schemas: {
    total: invalidSchemas.length,
    ids: invalidSchemas.map((item) => item.id),
  },
};
if (reportOut) Deno.writeTextFileSync(reportOut, JSON.stringify(report, null, 2));
console.log(
  `drut adapter: valid ${validPart.mapped.length} ` +
    `(corpus ${valid.length} + regressions ${regressions.valid.length}), ` +
    `invalid ${invalidPart.mapped.length} ` +
    `(corpus ${invalid.length} + regressions ${regressions.invalid.length}), ` +
    `invalid-schemas ${invalidSchemas.length} for compiler validation`,
);
for (const [label, part] of [
  ["valid", validPart.unsupported],
  ["invalid", invalidPart.unsupported],
] as const) {
  const groups = new Map<string, string[]>();
  for (const item of part) {
    const ids = groups.get(item.reason) ?? [];
    ids.push(item.id);
    groups.set(item.reason, ids);
  }
  for (const [reason, ids] of groups) {
    console.log(`  ${label} unsupported (${ids.length}): ${reason} [${ids.join(", ")}]`);
  }
}