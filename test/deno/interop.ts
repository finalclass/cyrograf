// Cross-language Drut exchange test driven by Deno.
//
// check  TS_DIR MESSAGES_JSON OUT_JSON : TS decodes canonical fixtures and
//        re-encodes them through the two public conversions; writes its own
//        encodings for the OCaml side.
// verify TS_DIR IN_JSON : TS decodes encodings produced by the OCaml side and
//        re-encodes them, checking every value.
// drut   TS_DIR VALID_JSON INVALID_JSON OUT_JSON : descriptor-driven conformance
//        corpus. Named roots go through the public text conversions; primitive
//        and list roots go through the generated private runtime.

interface Registry {
  toDrut: (value: unknown) => string;
  fromDrut: (text: string) => unknown;
}

interface Entry {
  id: string;
  type: string;
  wire: string;
  semantic?: boolean;
}

interface DrutCase {
  id: string;
  type: unknown;
  category?: "public" | "runtime";
  utf8_invalid?: boolean;
  wire?: string;
  wire_hex?: string;
  value?: unknown;
}

function toFileUrl(path: string): string {
  const absolute = path.startsWith("/") ? path : `${Deno.cwd()}/${path}`;
  return new URL(`file://${absolute}`).href;
}

const [mode, tsDir, inFile, outFile] = Deno.args;

const Orders = await import(toFileUrl(`${tsDir}/orders.ts`));
const Common = await import(toFileUrl(`${tsDir}/common.ts`));
const Wire = await import(toFileUrl(`${tsDir}/wire.ts`));

const registry: Record<string, Registry> = {
  "Orders.ReserveRequest": Orders.ReserveRequest,
  "Orders.Reservation": Orders.Reservation,
  "Orders.Problem": Orders.Problem,
  "Orders.ReserveResponse": Orders.ReserveResponse,
  "Orders.ReservationBatch": Orders.ReservationBatch,
  "Orders.Guard": Orders.Guard,
  "Orders.ListBox": Orders.ListBox,
  "Orders.ResponseBox": Orders.ResponseBox,
  "Orders.Scalars": Orders.Scalars,
  "Common.UserCtx": Common.UserCtx,
  "Common.Wrapper": Common.Wrapper,
  "Common.Blob": Common.Blob,
  "Common.Empty": Common.Empty,
  "Common.VoidBox": Common.VoidBox,
};

const primitives = new Set(["void", "int", "float", "bool", "string", "date", "record"]);

function sameValue(left: string, right: string): boolean {
  return JSON.stringify(JSON.parse(left)) === JSON.stringify(JSON.parse(right));
}

function readJson(path: string): unknown {
  return JSON.parse(Deno.readTextFileSync(path));
}

function assertEntry(entry: Entry): string {
  const ops = registry[entry.type];
  if (!ops) throw new Error(`unknown type ${entry.type}`);
  const decoded = ops.fromDrut(entry.wire);
  const reencoded = ops.toDrut(decoded);
  const matches = entry.semantic
    ? sameValue(reencoded, entry.wire)
    : reencoded === entry.wire;
  if (!matches) {
    throw new Error(
      `${entry.id} (${entry.type}): ${reencoded} !== ${entry.wire}`,
    );
  }
  return reencoded;
}

function jsonEqual(left: unknown, right: unknown): boolean {
  if (Array.isArray(left) && Array.isArray(right)) {
    if (left.length !== right.length) return false;
    return left.every((item, index) => jsonEqual(item, right[index]));
  }
  if (
    left !== null && right !== null &&
    typeof left === "object" && typeof right === "object"
  ) {
    const leftKeys = Object.keys(left as object).sort();
    const rightKeys = Object.keys(right as object).sort();
    if (leftKeys.length !== rightKeys.length) return false;
    return leftKeys.every((key, index) =>
      key === rightKeys[index] &&
      jsonEqual(
        (left as Record<string, unknown>)[key],
        (right as Record<string, unknown>)[key],
      )
    );
  }
  if (typeof left === "number" && typeof right === "number") return left === right;
  return left === right;
}

function hexToBytes(hex: string): Uint8Array {
  const bytes = new Uint8Array(hex.length / 2);
  for (let index = 0; index < bytes.length; index++) {
    bytes[index] = parseInt(hex.slice(index * 2, index * 2 + 2), 16);
  }
  return bytes;
}

function bytesToText(bytes: Uint8Array): string {
  const decoder = new TextDecoder("utf-8", { fatal: true, ignoreBOM: true });
  return decoder.decode(bytes);
}

function decodePrimitive(desc: string, value: unknown): unknown {
  switch (desc) {
    case "void":
      Wire.asNull(value, "");
      return null;
    case "int":
      return Wire.asInt(value, "");
    case "float":
      return Wire.asFloat(value, "");
    case "bool":
      return Wire.asBool(value, "");
    case "string":
    case "date":
      return Wire.asString(value, "");
    case "record":
      return Wire.asRecord(value, "");
    default:
      throw new Error(`unknown primitive ${desc}`);
  }
}

function decodeDesc(desc: unknown, value: unknown): unknown {
  if (typeof desc === "string") return decodePrimitive(desc, value);
  const inner = (desc as { list: unknown }).list;
  const items = Wire.asArray(value, "");
  return items.map((item) => decodeDesc(inner, item));
}

function bytesOf(entry: DrutCase): Uint8Array {
  if (entry.wire_hex !== undefined) return hexToBytes(entry.wire_hex);
  if (entry.wire !== undefined) return new TextEncoder().encode(entry.wire);
  throw new Error(`${entry.id}: case has neither wire nor wire_hex`);
}

const named = (desc: unknown) => typeof desc === "string" && !primitives.has(desc);

// Runs one corpus case and returns the produced JSON value. Named roots use the
// public text conversion on the original text; primitive/list roots use the
// generated private runtime. The adapter decodes raw bytes to text itself; a
// wire_hex case that is not valid UTF-8 is reported as an adapter limitation.
function runCase(entry: DrutCase): unknown {
  const text = bytesToText(bytesOf(entry));
  if (named(entry.type)) {
    const ops = registry[entry.type as string];
    if (!ops) throw new Error(`unknown type ${String(entry.type)}`);
    return JSON.parse(ops.toDrut(ops.fromDrut(text)));
  }
  const value = Wire.parseStrictText(text);
  return JSON.parse(Wire.stringifyWire(decodeDesc(entry.type, value)));
}

function runDrut(validFile: string, invalidFile: string, resultFile: string) {
  const valid = readJson(validFile) as DrutCase[];
  const invalid = readJson(invalidFile) as DrutCase[];
  const results: { id: string; status: string }[] = [];
  const categoryOf = (entry: DrutCase) =>
    entry.category ?? (named(entry.type) ? "public" : "runtime");
  for (const entry of valid) {
    if (entry.utf8_invalid) {
      // The text-only public API cannot represent invalid UTF-8 bytes.
      results.push({ id: entry.id, status: "inexpressible" });
      continue;
    }
    const produced = runCase(entry);
    const expected = named(entry.type)
      ? JSON.parse(entry.wire as string)
      : entry.value;
    if (!jsonEqual(produced, expected)) {
      throw new Error(`${entry.id}: produced value does not match the expected value`);
    }
    results.push({
      id: entry.id,
      status: categoryOf(entry) === "public" ? "executed" : "executed-runtime",
    });
  }
  for (const entry of invalid) {
    if (entry.utf8_invalid) {
      results.push({ id: entry.id, status: "inexpressible" });
      continue;
    }
    let rejected = false;
    try {
      runCase(entry);
    } catch {
      rejected = true;
    }
    if (!rejected) throw new Error(`${entry.id}: invalid wire accepted`);
    results.push({
      id: entry.id,
      status: categoryOf(entry) === "public" ? "rejected" : "rejected-runtime",
    });
  }
  Deno.writeTextFileSync(resultFile, JSON.stringify(results, null, 2));
  console.log(`typescript drut: ${valid.length} executed, ${invalid.length} rejected`);
}

if (mode === "drut") {
  runDrut(inFile, outFile, Deno.args[4]);
} else {
  const entries = readJson(inFile) as Entry[];
  if (mode === "check") {
    const results = entries.map((entry) => ({
      id: entry.id,
      type: entry.type,
      wire: assertEntry(entry),
      semantic: entry.semantic ?? false,
    }));
    Deno.writeTextFileSync(outFile, JSON.stringify(results, null, 2));
    console.log(`typescript verified ${entries.length} fixture(s)`);
  } else if (mode === "verify") {
    for (const entry of entries) assertEntry(entry);
    console.log(`typescript decoded ${entries.length} message(s) from peer`);
  } else if (mode === "invalid") {
    for (const entry of entries) {
      const ops = registry[entry.type];
      if (!ops) throw new Error(`unknown type ${entry.type}`);
      let rejected = false;
      try {
        ops.fromDrut(entry.wire);
      } catch {
        rejected = true;
      }
      if (!rejected) throw new Error(`${entry.id}: invalid wire accepted`);
    }
    console.log(`typescript rejected ${entries.length} invalid message(s)`);
  } else {
    throw new Error(`unknown mode ${mode}`);
  }
}