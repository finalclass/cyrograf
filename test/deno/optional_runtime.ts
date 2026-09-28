// Runtime optional-field checks for the generated TypeScript.
//
// Usage: optional_runtime.ts TS_DIR API_TS_DIR
//
// TS_DIR holds the generated orders/common/wire modules; API_TS_DIR holds the
// generated api module of test/fixtures/api. The script runs a consumer that
// checks absence is not a present empty value, that a decoded absent optional
// has no own property, that `undefined` and absence encode identically, and
// that explicit `null` is rejected.

const tsDir = Deno.args[0];
const apiDir = Deno.args[1];
if (!tsDir || !apiDir) {
  console.error("usage: optional_runtime.ts TS_DIR API_TS_DIR");
  Deno.exit(2);
}

Deno.copyFileSync(`${apiDir}/api.ts`, `${tsDir}/api_optional.ts`);

const consumer = `
import { ReserveRequest } from "./orders.ts";
import { OptionalBox, Choice } from "./api_optional.ts";

function assert(condition: boolean, message: string): void {
  if (!condition) throw new Error(message);
}

const absent = ReserveRequest.fromDrut('["o1",2,null]');
assert(!Object.prototype.hasOwnProperty.call(absent, "note"), "absent optional has an own property");

const fromAbsent = ReserveRequest.toDrut({ ownerId: "o1", quantity: 2 });
const fromUndefined = ReserveRequest.toDrut({ ownerId: "o1", quantity: 2, note: undefined });
assert(fromAbsent === fromUndefined, "undefined and absence must encode identically");

const present = ReserveRequest.toDrut({ ownerId: "o1", quantity: 2, note: "" });
assert(present === '["o1",2,""]', "present empty string must stay present");

let rejected = false;
try {
  ReserveRequest.toDrut({ ownerId: "o1", quantity: 2, note: null as unknown as string });
} catch {
  rejected = true;
}
assert(rejected, "explicit null must be rejected");

const allAbsent = OptionalBox.fromDrut('["o1",null,null,null,null,null]');
assert(!Object.prototype.hasOwnProperty.call(allAbsent, "text"), "text absent");
assert(!Object.prototype.hasOwnProperty.call(allAbsent, "count"), "count absent");
assert(!Object.prototype.hasOwnProperty.call(allAbsent, "flag"), "flag absent");
assert(!Object.prototype.hasOwnProperty.call(allAbsent, "items"), "items absent");
assert(!Object.prototype.hasOwnProperty.call(allAbsent, "choice"), "choice absent");

const emptyPresent = OptionalBox.toDrut({
  ownerId: "o1",
  text: "",
  count: 0,
  flag: false,
  items: [],
  choice: { tag: "Empty" },
});
assert(emptyPresent === '["o1","",0,false,[],["Empty",null]]', "empty values stay present");

const payload = OptionalBox.toDrut({
  ownerId: "o1",
  choice: { tag: "Text", value: "x" },
});
assert(payload === '["o1",null,null,null,null,["Text","x"]]', "variant payload");

const roundtrip = OptionalBox.fromDrut(emptyPresent);
assert(roundtrip.text === "", "empty string survives roundtrip");
assert(roundtrip.count === 0, "zero survives roundtrip");
assert(roundtrip.flag === false, "false survives roundtrip");
assert(Array.isArray(roundtrip.items) && roundtrip.items.length === 0, "empty list survives roundtrip");
assert(roundtrip.choice?.tag === "Empty", "void variant survives roundtrip");
void Choice;

console.log("optional runtime ok");
`;

const consumerFile = `${tsDir}/optional_runtime_consumer.ts`;
Deno.writeTextFileSync(consumerFile, consumer);

const output = new Deno.Command(Deno.execPath(), {
  args: ["run", consumerFile],
  stdout: "piped",
  stderr: "piped",
}).outputSync();

const stderr = new TextDecoder().decode(output.stderr);
if (output.code !== 0 || !new TextDecoder().decode(output.stdout).includes("optional runtime ok")) {
  console.error(stderr);
  console.error("FAIL: optional runtime consumer failed");
  Deno.exit(1);
}
console.log("PASS: optional runtime consumer");
try {
  Deno.removeSync(consumerFile);
} catch {
  // already removed
}