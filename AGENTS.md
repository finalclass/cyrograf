# Cyrograf (ocaml-contract checkout)

Read `docs/main.md`, then the linked specification for the work being performed.
The public module is `Cyrograf`; the compiler module is `Cyrograf_compiler`.

The user explicitly requested this initial specification and delegated the initial
implementation by copying the relevant parts of Well. That initial implementation
is authorized; it does not require another approval or a separate sync keyword.
This authorization does not authorize changing Well or broadening this library.

Use the installed `idesign-architecture` and `axe` skills when available. Review
specifications directly in Git/T3. This is an OCaml library, not a Well app:
Markdown documents own the API and the language specification; `.mli` files
are derived from them. TOML examples under documentation describe input to the
compiler, not a generated Well service projection.

The user request dated 2026-09-28 authorizes the release scope in docs/main.md:
write the specification and delegate implementation to cyrograf:mechanik.
That task includes native language, tooling, editors and release preparation;
do not request a second sync approval for this explicitly delegated work.
The user approved the API/language decisions and explicitly delegated their
implementation on 2026-09-29. The same session explicitly delegates Python,
Java, C# and Rust generators, including their specification and acceptance.
Their binding rules are merged into docs/api.md,
docs/language.md and docs/stp.md; no further sync approval is required.
The initial Git history remains one root commit as requested by the user;
authorized commits amend it and pushes use an explicit force-with-lease.

The initial extraction has no previous implementation or Axe freeze. Implement
the bootstrap specification; do not treat creation of a first snapshot as a reason
to skip the requested implementation. After successful checks, record the first
verified baseline. Later work follows the selected spec-first workflow.

Keep source code and commit messages in English; specification prose in Polish.
Do not add explanatory source comments. Preserve the MIT license and provenance.
Use Deno/TypeScript for new auxiliary scripts. OCaml remains the product language.

Work only in this repository. Read Well as the donor; never change its checkout.
Do not copy `.git`, credentials, application data, environment configuration,
framework runtime, or existing build directories. Do not add Protobuf or gRPC.

Do not create a branch, commit implementation, push, publish a release, or edit
the specification unless explicitly requested in the task. Report an actual
specification contradiction rather than silently changing the requirements.

The implementation must provide the Make targets defined in `docs/stp.md`.
Use dependency-managed builds; do not rely on a local Well build or checkout.
