// Static check of the generated TypeScript optional fields under
// `strict` and `exactOptionalPropertyTypes`.
//
// Usage: optional_strict.ts TS_DIR
//
// The positive consumer must compile and narrow an optional property. The
// negative consumer must fail: `null` is not assignable to `field?: T`, and an
// optional field cannot be used without narrowing.

const tsDir = Deno.args[0];
if (!tsDir) {
  console.error("usage: optional_strict.ts TS_DIR");
  Deno.exit(2);
}

const config = {
  compilerOptions: {
    strict: true,
    exactOptionalPropertyTypes: true,
    noImplicitAny: true,
    target: "es2022",
    module: "esnext",
    moduleResolution: "bundler",
    allowImportingTsExtensions: true,
    noEmit: true,
  },
};

const positive = `
import { ReserveRequest } from "./orders.ts";

const text: string = ReserveRequest.toDrut({ ownerId: "o1", quantity: 2 });
const request: ReserveRequest = ReserveRequest.fromDrut(text);
const note: string | undefined = request.note;
if (note !== undefined) {
  const present: string = note;
  void present;
}
const withNote: string = ReserveRequest.toDrut({
  ownerId: "o1",
  quantity: 2,
  note: "hi",
});
void withNote;
`;

const negative = `
import { ReserveRequest } from "./orders.ts";

// Explicit null is not a valid optional field value.
const bad: string = ReserveRequest.toDrut({ ownerId: "o1", quantity: 2, note: null });
void bad;

// Explicit undefined is not assignable to an optional field under
// exactOptionalPropertyTypes; absence is the omitted property, not a value.
const badUndefined: string = ReserveRequest.toDrut({
  ownerId: "o1",
  quantity: 2,
  note: undefined,
});
void badUndefined;

// Reading an optional field without narrowing is a type error.
const request = ReserveRequest.fromDrut("[]");
const used: string = request.note;
void used;
`;

const positiveFile = `${tsDir}/optional_positive.ts`;
const negativeFile = `${tsDir}/optional_negative.ts`;
const configFile = `${tsDir}/optional_tsconfig.json`;
Deno.writeTextFileSync(positiveFile, positive);
Deno.writeTextFileSync(negativeFile, negative);
Deno.writeTextFileSync(configFile, JSON.stringify(config, null, 2));

async function check(file: string): Promise<number> {
  const command = new Deno.Command(Deno.execPath(), {
    args: ["check", "--config", configFile, file],
    stdout: "piped",
    stderr: "piped",
  });
  const output = await command.output();
  if (output.code !== 0) {
    console.error(new TextDecoder().decode(output.stderr));
  }
  return output.code;
}

let failures = 0;
const positiveCode = await check(positiveFile);
if (positiveCode !== 0) {
  failures += 1;
  console.error("FAIL: strict optional consumer with narrowing did not compile");
} else {
  console.log("PASS: strict optional consumer compiles and narrows");
}
const negativeCode = await check(negativeFile);
if (negativeCode === 0) {
  failures += 1;
  console.error("FAIL: negative optional usage compiled under exactOptionalPropertyTypes");
} else {
  console.log("PASS: null and un-narrowed optional usage rejected");
}

Deno.removeSync(positiveFile);
Deno.removeSync(negativeFile);
Deno.removeSync(configFile);

console.log(`optional strict: ${failures} failure(s)`);
if (failures > 0) Deno.exit(1);