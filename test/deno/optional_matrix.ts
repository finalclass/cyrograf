// One endpoint of the cross-language optional-field exchange for TypeScript.
//
//   produce API_DIR CASES_JSON OUT_JSON : encode each canonical optional case
//       through the public `toDrut` and write the encodings.
//   consume API_DIR PEER_JSON           : decode a peer's encodings through the
//       public `fromDrut`, check the typed field states and re-encode them.

interface ChoiceValue {
  tag: string;
  value?: string;
}

interface Box {
  ownerId: string;
  text?: string;
  count?: number;
  flag?: boolean;
  items?: string[];
  choice?: ChoiceValue;
}

interface Registry {
  toDrut: (value: Box) => string;
  fromDrut: (text: string) => Box;
}

interface Case {
  id: string;
  wire: string;
}

function toFileUrl(path: string): string {
  const absolute = path.startsWith("/") ? path : `${Deno.cwd()}/${path}`;
  return new URL(`file://${absolute}`).href;
}

function fail(message: string): never {
  console.error(`FAIL: ${message}`);
  Deno.exit(1);
}

const cases: { id: string; value: Box }[] = [
  { id: "absent", value: { ownerId: "o1" } },
  { id: "empty_string", value: { ownerId: "o1", text: "" } },
  { id: "zero", value: { ownerId: "o1", count: 0 } },
  { id: "false", value: { ownerId: "o1", flag: false } },
  { id: "empty_list", value: { ownerId: "o1", items: [] } },
  { id: "variant_text", value: { ownerId: "o1", choice: { tag: "Text", value: "x" } } },
  { id: "variant_void", value: { ownerId: "o1", choice: { tag: "Empty" } } },
  {
    id: "all_present",
    value: { ownerId: "o1", text: "", count: 0, flag: false, items: [], choice: { tag: "Empty" } },
  },
];

function absent(value: unknown): boolean {
  return value === undefined;
}

function checkSemantics(id: string, value: Box): void {
  const expected = (() => {
    switch (id) {
      case "absent":
        return absent(value.text) && absent(value.count) && absent(value.flag) &&
          absent(value.items) && absent(value.choice);
      case "empty_string":
        return value.text === "" && absent(value.count) && absent(value.flag) &&
          absent(value.items) && absent(value.choice);
      case "zero":
        return absent(value.text) && value.count === 0 && absent(value.flag) &&
          absent(value.items) && absent(value.choice);
      case "false":
        return absent(value.text) && absent(value.count) && value.flag === false &&
          absent(value.items) && absent(value.choice);
      case "empty_list":
        return absent(value.text) && absent(value.count) && absent(value.flag) &&
          Array.isArray(value.items) && value.items.length === 0 && absent(value.choice);
      case "variant_text":
        return absent(value.text) && absent(value.count) && absent(value.flag) &&
          absent(value.items) && value.choice?.tag === "Text" &&
          value.choice.value === "x";
      case "variant_void":
        return absent(value.text) && absent(value.count) && absent(value.flag) &&
          absent(value.items) && value.choice?.tag === "Empty";
      case "all_present":
        return value.text === "" && value.count === 0 && value.flag === false &&
          Array.isArray(value.items) && value.items.length === 0 &&
          value.choice?.tag === "Empty";
      default:
        return fail(`unknown case ${id}`);
    }
  })();
  if (!expected) fail(`case ${id} decoded to the wrong typed value`);
  if (value.ownerId !== "o1") fail(`case ${id} lost the required field`);
}

const [mode, apiDir, arg, out] = Deno.args;
if (!mode || !apiDir) fail("usage: optional_matrix.ts <produce|consume> API_DIR ARG [OUT]");

const api = await import(toFileUrl(`${apiDir}/api.ts`));
const ops = api.OptionalBox as Registry;
const entries = JSON.parse(Deno.readTextFileSync(arg)) as Case[];

if (mode === "produce") {
  if (!out) fail("produce needs OUT_JSON");
  const expected = new Map(entries.map((entry) => [entry.id, entry.wire]));
  const produced = cases.map((entry) => {
    const wire = ops.toDrut(entry.value);
    const want = expected.get(entry.id);
    if (want === undefined) fail(`no canonical wire for case ${entry.id}`);
    if (want !== wire) fail(`case ${entry.id} encoded ${wire}, expected ${want}`);
    return { id: entry.id, wire };
  });
  Deno.writeTextFileSync(out, JSON.stringify(produced, null, 2));
  console.log(`typescript produced ${produced.length} optional case(s)`);
} else if (mode === "consume") {
  for (const entry of entries) {
    const value = ops.fromDrut(entry.wire);
    checkSemantics(entry.id, value);
    const reencoded = ops.toDrut(value);
    if (reencoded !== entry.wire) {
      fail(`case ${entry.id} re-encoded ${reencoded}, received ${entry.wire}`);
    }
  }
  console.log(`typescript consumed ${entries.length} optional case(s)`);
} else {
  fail(`unknown mode ${mode}`);
}