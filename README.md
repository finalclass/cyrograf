# Cyrograf

**Contracts that are valid even beyond death.**

<p align="center">
  <img src="assets/cyrograf-mascot.png" width="128" alt="Cyrograf's angel mascot holding a quill and a sealed parchment contract." />
</p>

Cyrograf is a self-contained contract language and toolchain. Define messages,
tagged variants and descriptive RPC signatures once in `.cyrograf` files, then
generate native types and Drut codecs for OCaml, TypeScript, Go, Dart, Python,
Java, C# and Rust. Cyrograf is written in OCaml; the contract language and the data
format are language-independent. TOML remains a supported compatibility input.

**Cyrograf** names the language and tooling; **Drut** names the data encoding.
Drut uses JSON arrays for declared structures and tagged arrays for variants.
It is a schema-based encoding, not a compression algorithm. The format has a
standalone specification in [drut-spec](https://github.com/finalclass/drut-spec);
the pinned revision and the profile of this implementation are in
[the Drut reference](docs/wire.md).

One version, `0.1.0`, and one public program, `cyrograf`, cover check, build,
format, migrate and LSP. There is no separate formatter or LSP binary.

## Install

`make package` produces a program archive for Linux x86_64. It contains the
`cyrograf` binary and needs no OCaml, Dune, Go, Dart, Python, Java, .NET, Rust or Deno. It uses
the system C library and `libm` from a glibc-based x86_64 Linux; unpack it and
put `cyrograf` on `PATH`.

```sh
tar -xzf cyrograf-0.1.0-linux-x86_64.tar.gz
mkdir -p "$HOME/.local/bin"
install cyrograf-0.1.0-linux-x86_64/cyrograf "$HOME/.local/bin/cyrograf"
export PATH="$HOME/.local/bin:$PATH"
cyrograf --version
```

To install from [the GitHub repository](https://github.com/finalclass/cyrograf),
you need Git, Make and Dune with package management (tested with Dune 3.24.2).
Dune obtains the OCaml compiler and dependencies from `dune.lock` on the first
build. `make install` installs the `cyrograf` program and the OCaml libraries:

```sh
mkdir -p "$HOME/.local/share"
git clone https://github.com/finalclass/cyrograf.git "$HOME/.local/share/cyrograf"
cd "$HOME/.local/share/cyrograf"
make install
export PATH="$HOME/.local/bin:$PATH"
cyrograf --version
```

If you already have a checkout, run `make install` there instead of cloning
again. The [editor instructions](editors/README.md) use the checkout location
above. The default `PREFIX` is `$(HOME)/.local`; alternatively, choose another
prefix or stage the install with `DESTDIR`:

```sh
make install PREFIX=/opt/cyrograf
make install PREFIX=/usr/local DESTDIR=/tmp/stage
```

The program lands in `PREFIX/bin/cyrograf`; the libraries keep the Dune install
layout under `PREFIX/lib/cyrograf`. Prefix and `DESTDIR` paths may contain
spaces, and a repeated install updates the package files. `make install` builds
from source, works with Dune package management, copies the Dune install tree so
no manual `cp` of `_build/install` is needed, never runs `sudo` and does not
modify editor configuration, `PATH` or foreign files in the prefix. Add
`PREFIX/bin` to `PATH` if it is not there yet:

```sh
export PATH="$HOME/.local/bin:$PATH"
```

The `cyrograf` library (module `Cyrograf`) is the runtime; `cyrograf.compiler`
(module `Cyrograf_compiler`) is the strict frontend and the eight generators.
`cyrograf.tooling` and `cyrograf.lsp` back the command-line and editor
integrations. Generated OCaml code depends on `cyrograf` and ships its own
private Drut runtime helper.

## Quick start

`examples/orders` is a two-module native contract that references a message
across modules and declares one descriptive RPC.

```cyrograf
struct ReserveRequest {
  owner_id: String
  quantity: Int
  note?: String
}

variant ReserveResponse {
  Reserved(Reservation)
  Rejected(Problem)
  Unavailable
}

rpc reserve(ReserveRequest) -> ReserveResponse
```

Check the project and generate the delivered targets:

```sh
cyrograf check examples/orders
cyrograf build examples/orders --output _build/orders \
  --targets ocaml,typescript,go,dart,python,java,csharp,rust
```

Build writes `ocaml/`, `typescript/`, `go/`, `dart/`, `python/`, `java/`,
`csharp/` and `rust/` directories,
the `schema.json` descriptor of the model and the `manifest.json` list of
generated paths. Results are deterministic; a failure leaves the previous output
intact.

Each generated message exposes exactly two public text conversions. For example,
the request above:

```ocaml
let request =
  Orders.ReserveRequest.make ~owner_id:"o1" ~quantity:2 ~note:"hi" ()

match Orders.ReserveRequest.to_drut request with
| Ok text -> print_endline text
| Error error -> prerr_endline error.Cyrograf.Error.message
```

```ts
import { ReserveRequest } from "./orders.ts";

const text = ReserveRequest.toDrut({ ownerId: "o1", quantity: 2, note: "hi" });
const request = ReserveRequest.fromDrut(text);
```

```go
request := orders.ReserveRequest{OwnerID: "o1", Quantity: 2}
text, err := orders.ReserveRequestToDrut(request)
```

```dart
final request = ReserveRequest(ownerId: 'o1', quantity: 2);
final text = request.toDrut();
```

```python
from generated_contracts.orders import ReserveRequest

text = ReserveRequest(owner_id="o1", quantity=2, note="hi").to_drut()
request = ReserveRequest.from_drut(text)
```

```java
import generated_contracts.Orders;
import java.util.Optional;

var request = new Orders.ReserveRequest("o1", 2, Optional.of("hi"));
String text = request.toDrut();
Orders.ReserveRequest decoded = Orders.ReserveRequest.fromDrut(text);
```

```csharp
using GeneratedContracts.Orders;

var request = new ReserveRequest("o1", 2, "hi");
string text = request.ToDrut();
ReserveRequest decoded = ReserveRequest.FromDrut(text);
```

```rust
use generated_contracts::orders::ReserveRequest;

let request = ReserveRequest { owner_id: "o1".to_string(), quantity: 2, note: Some("hi".to_string()) };
let text = request.to_drut()?;
let decoded = ReserveRequest::from_drut(&text)?;
```

The variants follow the same pattern: OCaml uses an algebraic sum, TypeScript a
tagged union, Go an interface with one type per case, Dart a sealed class with
typed constructors, Python a base class with one dataclass per case, Java a
sealed interface with nested record cases, C# an abstract record with nested
sealed record cases, and Rust an enum with typed payload cases. The two
conversions always take and return Drut text; the private runtime validates the
whole text, including UTF-8 in OCaml and Go. TypeScript, Dart, Python, Java, C#
and Rust have no public byte entry point: a consumer that receives bytes converts them
strictly to text before calling `fromDrut`/`from_drut`/`toDrut`/`ToDrut`/`from_drut`.

## Commands

| Command | Role |
|---|---|
| `cyrograf check SOURCE_DIR [--targets …]` | Validate the language rules and target name collisions; write nothing. |
| `cyrograf build SOURCE_DIR --output DIR [--targets …] [--go-module PATH]` | Check, generate the selected targets and publish the result. |
| `cyrograf format [PATH …] [--check]` | Give native `.cyrograf` files the canonical layout. |
| `cyrograf format --stdin --filename NAME.cyrograf` | Format exactly one document from standard input to standard output. |
| `cyrograf migrate SOURCE_DIR --output DIR` | Convert a TOML project to native `.cyrograf` sources. |
| `cyrograf lsp [--stdio]` | Serve the language protocol on standard input and output. |
| `cyrograf help [COMMAND]`, `cyrograf --version` | Help and version. |

`cyrograf` without arguments prints help and exits 0. Unknown commands, flags or
targets print the help of the command to stderr and exit 2; a source, validation
or I/O error exits 1.

## Language and inputs

The declarations, lexical rules and diagnostics are specified in
[the language reference](docs/language.md). Sources are `.cyrograf` files in one
directory, read without recursion; `check`, `build` and `migrate` also accept
`.toml`. Conversion rules are in [the TOML input reference](docs/toml.md);
`cyrograf migrate` writes a native project without modifying the input.

## Editor integrations

`editors/` provides Emacs, Vim, Neovim, VS Code and JetBrains integrations, each
recognizing `.cyrograf`, highlighting the syntax and connecting to an installed
`cyrograf lsp`. Emacs, Vim, Neovim and VS Code also color `cyrograf` fenced
blocks in Markdown; the VS Code extension colors the built-in preview as well.
External renderers such as GitHub.com need their own registration. The clients
hold no validator, formatter copy or generator; the command and its arguments
are always passed as a list, never through a shell. See
[the editors guide](editors/README.md) and
[the editor specification](docs/editors.md).

## Verification status

Checked on 2026-09-29 with OCaml 5.4.1, Dune 3.24.2, Deno 2.9.5, Go 1.23.6,
Dart 3.13.4, Python 3.11, mypy 1.13.0, Java 21.0.12.1 (Temurin), .NET SDK
10.0.401, Rust 1.85.0 (edition 2024) and Node 22.22.0:

- `make test-all` passes: OCaml build and tests, canonical formatting, native
  language and TOML equivalence, migration, the LSP protocol against the real
  process, and the packaged editor integrations. Emacs, Vim, Neovim and the
  VS Code Extension Host run their checks, including the Markdown block tokens
  and preview HTML; the JetBrains TextMate bundle and LSP4IJ configuration are
  validated as artifacts.
- The small API is enforced per target: an isolated positive consumer compiles
  and uses only `to_drut`/`from_drut` (plus their target spellings), while a
  negative neighbour referring to the removed or internal value codec
  (`encode_value`, `wireEncode*`, `Encode*Value`, `fromValue`, `from_value`)
  fails to compile for that reason. Rust additionally rejects the `pub(crate)`
  value helper, the private `wire` runtime and a `serde` `Serialize`
  implementation outside the generated crate, and an un-narrowed `Option`. OCaml additionally rejects `Cyrograf.Codec`,
  `Cyrograf.Wire` and the old `Contract` module; the generated message
  interfaces hide the internal value codec. TypeScript is checked with `strict`
  and `exactOptionalPropertyTypes`, including rejected `null`, un-narrowed
  optional reads, the absence of an own property after decoding, and equal
  encodings for absence and `undefined`. Python is checked with mypy in strict
  mode: the positive consumer uses only the two conversions, while the negative
  one fails on a missing third conversion, a wrongly typed variant payload and
  an un-narrowed optional read; `__all__` lists models without helpers and the
  runtime rejects `bool` where `Int`/`Float` is expected. Java is compiled with
  `javac --release 21`: the positive consumer uses only the two conversions, the
  negative one fails on a missing third conversion, and the package-private
  `Wire` runtime is unreachable outside its package. C# is compiled with the
  .NET SDK for `net10.0`: the positive consumer runs with nullable enabled and
  warnings-as-errors, the negative one fails on a missing third conversion, a
  separate assembly cannot reach the internal `Wire` runtime, and nullable
  misuse is rejected under warnings-as-errors. Rust is compiled by `cargo` on
  the declared 1.85 minimum with edition 2024: the positive consumer uses only
  the two conversions, the generated messages do not implement a public
  `Serialize`/`Deserialize`, and bad payloads or un-narrowed `Option` values do
  not compile. `owner_id` maps to
  `ownerId` in TypeScript/Dart/Java, `OwnerId` in C#, `OwnerID` in Go and stays
  `owner_id` in Python and Rust (Rust also takes the keyword suffix); reserved
  words take their target suffix, and collisions
  after mapping, including a Python, Java, C# or Rust member that shadows a
  conversion, are rejected by `check`;
  the canonical descriptor and Drut tags keep the source name.
- Optional String, Int, Bool, List and variant fields distinguish absence from
  an empty string, zero, false and an empty list in all eight targets (OCaml
  `None`/`Some`, TypeScript optional properties, Go pointers including a nil
  pointer versus a pointer to a nil/empty slice, Dart nullable, Python `None`,
  Java `Optional`, C# nullable, Rust `Option`). The shared optional matrix runs
  every ordered sender–receiver pair of the eight targets, 56 directions, and
  each receiver checks the typed field states.
- The pinned Drut corpus (`0d4b4e1e`) runs through all eight generated runtimes
  with the result category reported per ID and target: the public text
  conversions, the private runtime for primitive/list roots, and vectors that a
  text-only public API cannot express. 70 valid vectors are in the corpus; 69
  are expressible in this frontend and execute in OCaml, TypeScript, Go, Dart,
  Python, Java, C# and Rust (26 through the public conversions and 43 through the
  private runtime). The `variant_unicode_tag` vector uses a constructor name
  outside the ASCII profile and is reported separately with its ID, not treated
  as an invalid message. Of the 75 invalid vectors, TypeScript, Dart, Python,
  Java, C# and Rust mark the five invalid-UTF-8 byte vectors as inexpressible through
  their text API instead of counting an adapter rejection as a public `fromDrut`
  success;
  the remaining public and runtime cases are rejected in each language. 12 of 13
  invalid schemas are rejected by the compiler (the last is a malformed test
  notation, not a language rule).
- Exact integers, UTF-8 validation, the BOM policy and surrogate handling are
  exercised at the byte level, including nested positions and the documented
  regressions. The Python runtime reasons about the original number lexeme, so
  `1.0000000000000001` in an integer position is rejected although binary64
  would round it.
- `make package` builds the source archive, the Linux x86_64 program archive,
  the editor packages including the `.vsix`, and a SHA-256 manifest.
  `make test-release` unpacks them outside the repository, verifies the sums,
  exercises every command, runs a minimal LSP session, runs `make install`
  into a temporary prefix with spaces, checks staging with `DESTDIR`, repeated
  installs, foreign files and write errors, runs the installed binary outside
  the repository and compiles a separate OCaml consumer against the installed
  `cyrograf` libraries, installs the generated Python package into an isolated
  virtual environment to run its consumer, compiles and runs a separate Java
  consumer with `javac --release 21`, compiles and runs a separate C#
  consumer against the generated `net10.0` project, and compiles and runs a
  separate Rust consumer against the generated crate outside the repository.

This is the `0.1.0` candidate. The corpus above is partial relative to the whole
Drut specification; no claim of full Drut conformance is made. Byte-level and
corpus coverage is reported per case, per language, and is not a substitute for
a complete conformance suite.

## Build and verify

```
make build         # compile the OCaml libraries, the CLI and the fixture codecs
make check         # OCaml types, generated TypeScript, canonical native formatting
make test          # OCaml tests, generated OCaml tests, OCaml/TypeScript exchange
make test-api        # positive/negative public API surface for OCaml and TypeScript
make test-python     # mypy strict on the generated Python package and optional checks
make test-java       # javac release 21, public interop modes and a typed consumer
make test-csharp     # .NET SDK, public interop modes, typed consumer and negative surfaces
make test-rust       # Rust 1.85, separate consumer crate, optional cases and negative surfaces
make test-language # native language and TOML equivalence, shared analysis
make editors-tools # fetch the pinned Neovim and markdown-mode test tools into the cache
make test-editors  # Emacs, Vim, Neovim and VS Code integration checks
make test-all      # the full automatic verification, including Go, Dart, Python, Java, C# and Rust
make install       # build and install the program and libraries (PREFIX, DESTDIR)
make package       # release artifacts in _build/release/
make test-release  # verify the packaged artifacts outside the repository
```

`make test-editors` uses the pinned Neovim and `markdown-mode` versions; run
`make editors-tools` once (or set them up on `PATH`) before running it on a
clean checkout.

OCaml dependencies are managed by Dune's package management through `dune.lock`;
no Well checkout or local opam switch is required. Deno runs the auxiliary
scripts; Editor integrations use their own languages. Go and Dart can be taken
from their official distributions and put on `PATH`. Python 3.11 and a pinned
mypy are test tools, never runtime dependencies of the generated package, which
uses only the standard library. Java 21 (Temurin) is the minimum consumer
version; the generated project needs only the JDK, never a JSON library. The
.NET SDK 10 is the minimum C# consumer; the generated `net10.0` project needs
only the platform's `System.Text.Json`, never a NuGet package. Rust 1.85 with
edition 2024 is the minimum Rust consumer; the generated crate pins
`serde`/`serde_json` and exposes no alternative `Serialize`/`Deserialize`
conversion. When a
toolchain is missing, `make test-all`
reports a blocking gap instead of a success. GitHub CI runs `make build`,
`make check`, `make test-all` and `make test-release` with pinned tool
versions.

License: MIT. See [provenance](docs/extraction.md) for the Well source revision.
