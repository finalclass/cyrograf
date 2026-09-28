DUNE ?= dune
DUNE_FLAGS ?=
DENO ?= deno
GO ?= go
DART ?= dart
PYTHON ?= python3
MYPY ?= mypy
JAVAC ?= javac
JAVA ?= java
DOTNET ?= dotnet
RUST ?= cargo

TOOLCHAINS ?= $(HOME)/.cache/cyrograf-toolchains
export PATH := $(TOOLCHAINS)/python/venv/bin:$(TOOLCHAINS)/go/bin:$(TOOLCHAINS)/dart-sdk/bin:$(TOOLCHAINS)/java/current/bin:$(TOOLCHAINS)/dotnet/current:$(TOOLCHAINS)/rust/bin:$(TOOLCHAINS)/cargo/bin:$(PATH)
export CARGO_HOME := $(TOOLCHAINS)/cargo
export DOTNET_CLI_TELEMETRY_OPTOUT := 1
export DOTNET_NOLOGO := 1
export DOTNET_SKIP_FIRST_TIME_EXPERIENCE := 1
export NUGET_PACKAGES := $(TOOLCHAINS)/dotnet/nuget
export DOTNET_CLI_HOME := $(TOOLCHAINS)/dotnet/home

CONTRACT := _build/default/bin/contract_cli.exe
INTEROP := _build/default/test/interop_ocaml.exe
LANGUAGE := _build/default/test/language_test.exe
FORMAT := _build/default/test/format_test.exe
MIGRATE := _build/default/test/migrate_test.exe
ACCESS := _build/default/test/access_test.exe
FIXTURES := test/fixtures/orders
FORMAT_FIXTURES := test/fixtures/format/formatted
MESSAGES := test/fixtures/wire/messages.json
INVALID := test/fixtures/wire/invalid.json
OPTIONAL_CASES := test/fixtures/api/optional_cases.json
OPTIONAL := _build/default/test/optional_matrix.exe
WORK := _build/contract-work
TSDIR := $(WORK)/interop/typescript
GODIR := $(WORK)/all/go
DARTDIR := $(WORK)/all/dart
PYDIR := $(WORK)/all/python
JAVADIR := $(WORK)/all/java
JAVACLASSES := $(WORK)/java-classes
PYAPI := $(WORK)/api-python/python
CSTESTS := $(WORK)/csharp-tests
CSNEGATIVE := $(WORK)/csharp-negative
CSNULLABLE := $(WORK)/csharp-nullable
RUSTSRC := $(WORK)/rust-src
RUSTGEN := $(WORK)/rust/rust
RUSTRUNNER := $(WORK)/rust/runner
RUSTBIN := $(RUSTRUNNER)/target/debug/cyrograf_rust_tests
RUSTDRUT := $(WORK)/rust-drut
RUSTNEG := $(WORK)/rust

PREFIX ?= $(HOME)/.local
DESTDIR ?=
INSTALL_TREE := _build/install/default

.PHONY: build install check test test-all test-language test-format test-migrate test-access test-lsp test-editors test-drut test-ocaml-js test-optional-matrix test-api test-api-all test-python test-java test-csharp test-rust test-examples package test-release editors-tools clean lock

build:
	$(DUNE) build $(DUNE_FLAGS)

install:
	$(DUNE) build @install $(DUNE_FLAGS)
	mkdir -p "$(DESTDIR)$(PREFIX)"
	cp -RLf "$(INSTALL_TREE)/." "$(DESTDIR)$(PREFIX)/"
	chmod 755 "$(DESTDIR)$(PREFIX)/bin/cyrograf"

test-language: build
	$(LANGUAGE)

test-examples: build
	rm -rf $(WORK)/examples
	$(CONTRACT) check examples/orders
	$(CONTRACT) format --check examples/orders
	$(CONTRACT) build examples/orders --output $(WORK)/examples --targets ocaml,typescript,go,dart,python,java,csharp,rust
	$(DENO) check $(WORK)/examples/typescript/common.ts $(WORK)/examples/typescript/orders.ts $(WORK)/examples/typescript/wire.ts
	@if command -v $(MYPY) >/dev/null 2>&1; then \
	  $(MYPY) --strict --no-incremental --cache-dir=$(WORK)/mypy-cache \
	    $(WORK)/examples/python/generated_contracts || exit 1; \
	else \
	  echo "BLOCKED: mypy not found; the example Python target was not checked"; \
	  exit 1; \
	fi
	@if command -v $(GO) >/dev/null 2>&1; then \
	  ( cd $(WORK)/examples/go && go vet ./... ) || exit 1; \
	else \
	  echo "BLOCKED: go toolchain not found; the example Go target was not compiled"; \
	  exit 1; \
	fi
	@if command -v $(DART) >/dev/null 2>&1; then \
	  $(DART) analyze $(WORK)/examples/dart || exit 1; \
	else \
	  echo "BLOCKED: dart toolchain not found; the example Dart target was not analyzed"; \
	  exit 1; \
	fi
	@if command -v $(JAVAC) >/dev/null 2>&1; then \
	  $(JAVAC) --release 21 -d $(WORK)/examples/java-classes \
	    $(WORK)/examples/java/src/main/java/generated_contracts/*.java || exit 1; \
	else \
	  echo "BLOCKED: javac not found; the example Java target was not compiled"; \
	  exit 1; \
	fi
	@if command -v $(DOTNET) >/dev/null 2>&1; then \
	  $(DOTNET) build $(WORK)/examples/csharp/GeneratedContracts.csproj -v q || exit 1; \
	else \
	  echo "BLOCKED: dotnet not found; the example C# target was not compiled"; \
	  exit 1; \
	fi
	@if command -v $(RUST) >/dev/null 2>&1; then \
	  ( cd $(WORK)/examples/rust && $(RUST) check -q ) || exit 1; \
	else \
	  echo "BLOCKED: cargo not found; the example Rust target was not compiled"; \
	  exit 1; \
	fi

# Real js_of_ocaml 6.2.0 acceptance for the OCaml js profile: compile the
# generated Int->int64 library in an isolated workspace and exchange Drut
# messages with native OCaml and TypeScript. A missing js_of_ocaml is a
# blocking gap, not a silent pass.
test-ocaml-js: build
	PROJECT_ROOT=$(CURDIR) CONTRACT=$(abspath $(CONTRACT)) \
	INTEROP=$(abspath $(INTEROP)) FIXTURES=$(abspath $(FIXTURES)) \
	MESSAGES=$(abspath $(MESSAGES)) INVALID=$(abspath $(INVALID)) \
	WORK=$(abspath $(WORK))/ocaml-js TOOLCHAINS=$(abspath $(TOOLCHAINS)) \
	DUNE=$(DUNE) NODE=$${NODE:-node} DENO=$(DENO) \
	$(DENO) run --allow-run --allow-read --allow-write --allow-env \
	  scripts/ocaml_js_test.ts

test-format: build
	CYROGRAF_BIN=$(CONTRACT) $(FORMAT)

test-migrate: build
	$(MIGRATE)

test-access: build
	$(ACCESS)

test-lsp: build
	CYROGRAF_BIN=$(CONTRACT) $(DENO) run --allow-run --allow-read --allow-write --allow-env \
	  test/deno/lsp_test.ts

editors-tools:
	$(DENO) run --allow-net --allow-read --allow-write --allow-run --allow-env \
	  scripts/editors_tools.ts

test-editors: build
	CYROGRAF_BIN=$(CONTRACT) $(DENO) run --allow-run --allow-read --allow-write --allow-env \
	  test/deno/editors_test.ts

check: build
	$(CONTRACT) format --check $(FORMAT_FIXTURES) examples/orders
	rm -rf $(WORK)/tscheck
	$(CONTRACT) build $(FIXTURES) --output $(WORK)/tscheck --targets typescript
	$(DENO) check \
	  $(WORK)/tscheck/typescript/wire.ts \
	  $(WORK)/tscheck/typescript/orders.ts \
	  $(WORK)/tscheck/typescript/common.ts

test: check
	$(DUNE) runtest $(DUNE_FLAGS)
	$(ACCESS)
	rm -rf $(WORK)/interop
	$(CONTRACT) build $(FIXTURES) --output $(WORK)/interop --targets typescript
	$(DENO) run --allow-read --allow-write test/deno/interop.ts check \
	  $(TSDIR) $(MESSAGES) $(WORK)/ts_encoded.json
	$(INTEROP) check $(MESSAGES) $(WORK)/ocaml_encoded.json
	$(INTEROP) verify $(WORK)/ts_encoded.json
	$(DENO) run --allow-read test/deno/interop.ts verify \
	  $(TSDIR) $(WORK)/ocaml_encoded.json
	$(INTEROP) invalid $(INVALID)
	$(DENO) run --allow-read test/deno/interop.ts invalid \
	  $(TSDIR) $(INVALID)
	$(DENO) run --allow-read --allow-write --allow-run --allow-env \
	  test/deno/optional_strict.ts $(TSDIR)
	rm -rf $(WORK)/api-ts
	$(CONTRACT) build test/fixtures/api --output $(WORK)/api-ts --targets typescript
	$(DENO) run --allow-read --allow-write --allow-run \
	  test/deno/optional_runtime.ts $(TSDIR) $(WORK)/api-ts/typescript
	$(MAKE) test-api

# Full acceptance: compile and actually run the generated Go, Dart and Python
# consumers, reject invalid Wire, and exchange every language pair.
test-all: test test-python test-java test-csharp test-rust test-language test-format test-migrate test-lsp test-editors test-examples test-ocaml-js
	rm -rf $(WORK)/all
	$(CONTRACT) build $(FIXTURES) --output $(WORK)/all --targets go,dart,python,java,csharp,rust
	@if command -v $(GO) >/dev/null 2>&1; then \
	  mkdir -p $(GODIR)/cmd/interop $(GODIR)/cmd/wrong; \
	  cp test/go/interop/main.go $(GODIR)/cmd/interop/main.go; \
	  cp test/go/wrong/main.go $(GODIR)/cmd/wrong/main.go; \
	  ( cd $(GODIR) && go vet ./wire/... ./orders/... ./common/... ./cmd/interop ) || exit 1; \
	  ( cd $(GODIR) && go build -o ../../go_interop ./cmd/interop ) || exit 1; \
	  $(WORK)/go_interop check $(MESSAGES) $(WORK)/go_encoded.json || exit 1; \
	  $(WORK)/go_interop invalid $(INVALID) || exit 1; \
	  $(WORK)/go_interop optional || exit 1; \
	  if ( cd $(GODIR) && go build -o /dev/null ./cmd/wrong >/dev/null 2>&1 ); then \
	    echo "FAIL: wrong variant Value type compiled"; exit 1; \
	  else \
	    echo "go type safety: wrong variant Value type rejected at compile time"; \
	  fi; \
	else \
	  echo "BLOCKED: go toolchain not found; Go fixtures were not compiled or run"; \
	  exit 1; \
	fi
	@if command -v $(DART) >/dev/null 2>&1; then \
	  cp test/dart/interop.dart $(DARTDIR)/interop.dart; \
	  $(DART) analyze $(DARTDIR) || exit 1; \
	  $(DART) $(DARTDIR)/interop.dart check $(MESSAGES) $(WORK)/dart_encoded.json || exit 1; \
	  $(DART) $(DARTDIR)/interop.dart invalid $(INVALID) || exit 1; \
	  $(DART) $(DARTDIR)/interop.dart optional || exit 1; \
	else \
	  echo "BLOCKED: dart toolchain not found; Dart fixtures were not compiled or run"; \
	  exit 1; \
	fi
	@if command -v $(PYTHON) >/dev/null 2>&1; then \
	  CYROGRAF_PYTHON_PACKAGE=$(PYDIR) $(PYTHON) test/python/interop.py check \
	    $(MESSAGES) $(WORK)/python_encoded.json || exit 1; \
	  CYROGRAF_PYTHON_PACKAGE=$(PYDIR) $(PYTHON) test/python/interop.py invalid \
	    $(INVALID) || exit 1; \
	  CYROGRAF_PYTHON_PACKAGE=$(PYDIR) $(PYTHON) test/python/interop.py optional || exit 1; \
	else \
	  echo "BLOCKED: python interpreter not found; Python fixtures were not run"; \
	  exit 1; \
	fi
	@if command -v $(JAVAC) >/dev/null 2>&1; then \
	  cp test/java/Interop.java $(JAVADIR)/src/main/java/generated_contracts/Interop.java; \
	  $(JAVAC) --release 21 -d $(JAVACLASSES) \
	    $(JAVADIR)/src/main/java/generated_contracts/*.java || exit 1; \
	  $(JAVA) -cp $(JAVACLASSES) generated_contracts.Interop check $(MESSAGES) \
	    $(WORK)/java_encoded.json || exit 1; \
	  $(JAVA) -cp $(JAVACLASSES) generated_contracts.Interop invalid $(INVALID) || exit 1; \
	  $(JAVA) -cp $(JAVACLASSES) generated_contracts.Interop optional || exit 1; \
	else \
	  echo "BLOCKED: javac not found; Java fixtures were not compiled or run"; \
	  exit 1; \
	fi
	@echo "exchange matrix"
	@set -e; \
	CSDLL=$$(find $(CSTESTS)/bin -name 'CyrografCsharpTests.dll' | head -1); \
	for producer in typescript ocaml go dart python java csharp rust; do \
	  case $$producer in \
	    typescript) file=$(WORK)/ts_encoded.json;; \
	    ocaml) file=$(WORK)/ocaml_encoded.json;; \
	    go) file=$(WORK)/go_encoded.json;; \
	    dart) file=$(WORK)/dart_encoded.json;; \
	    python) file=$(WORK)/python_encoded.json;; \
	    java) file=$(WORK)/java_encoded.json;; \
	    csharp) file=$(WORK)/csharp_encoded.json;; \
	    rust) file=$(WORK)/rust_encoded.json;; \
	  esac; \
	  for consumer in typescript ocaml go dart python java csharp rust; do \
	    if [ "$$producer" != "$$consumer" ]; then \
	      echo "exchange $$producer -> $$consumer"; \
	      case $$consumer in \
	        typescript) $(DENO) run --allow-read test/deno/interop.ts verify $(TSDIR) $$file;; \
	        ocaml) $(INTEROP) verify $$file;; \
	        go) $(WORK)/go_interop verify $$file;; \
	        dart) $(DART) $(DARTDIR)/interop.dart verify $$file;; \
	        python) CYROGRAF_PYTHON_PACKAGE=$(PYDIR) $(PYTHON) test/python/interop.py verify $$file;; \
	        java) $(JAVA) -cp $(JAVACLASSES) generated_contracts.Interop verify $$file;; \
	        csharp) $(DOTNET) $$CSDLL interop verify $$file;; \
	        rust) $(RUSTBIN) interop verify $$file;; \
	      esac; \
	    fi; \
	  done; \
	done; \
	echo "exchange matrix: 56 directions"
	@echo "drut conformance corpus: root descriptors and byte inputs"
	$(MAKE) test-drut
	$(MAKE) test-api-all
	$(MAKE) test-optional-matrix

test-python: build
	rm -rf $(WORK)/pycheck
	$(CONTRACT) build $(FIXTURES) --output $(WORK)/pycheck --targets python
	@if command -v $(MYPY) >/dev/null 2>&1; then \
	  $(MYPY) --strict --no-incremental --cache-dir=$(WORK)/mypy-cache \
	    $(WORK)/pycheck/python/generated_contracts || exit 1; \
	else \
	  echo "BLOCKED: mypy not found; the generated Python package was not checked"; \
	  exit 1; \
	fi
	CYROGRAF_PYTHON_PACKAGE=$(WORK)/pycheck/python $(PYTHON) test/python/interop.py optional
	rm -rf $(WORK)/pymix
	$(CONTRACT) build test/fixtures/python --output $(WORK)/pymix --targets python
	CYROGRAF_PYTHON_PACKAGE=$(WORK)/pymix/python $(PYTHON) test/python/mix_check.py

# Dedicated target check: compile the generated Java with the JDK, run the
# public interop modes and a typed positive consumer outside the package.
test-java: build
	@if command -v $(JAVAC) >/dev/null 2>&1; then \
	  rm -rf $(WORK)/java $(WORK)/java-classes; \
	  $(CONTRACT) build $(FIXTURES) --output $(WORK)/java --targets java || exit 1; \
	  cp test/java/Interop.java $(WORK)/java/java/src/main/java/generated_contracts/Interop.java; \
	  $(JAVAC) --release 21 -d $(WORK)/java-classes \
	    $(WORK)/java/java/src/main/java/generated_contracts/*.java || exit 1; \
	  $(JAVA) -cp $(WORK)/java-classes generated_contracts.Interop check \
	    $(MESSAGES) $(WORK)/java_encoded.json || exit 1; \
	  $(JAVA) -cp $(WORK)/java-classes generated_contracts.Interop invalid $(INVALID) || exit 1; \
	  $(JAVA) -cp $(WORK)/java-classes generated_contracts.Interop optional || exit 1; \
	  $(JAVAC) --release 21 -cp $(WORK)/java-classes -d $(WORK)/java-classes \
	    test/java/ConsumerPositive.java || exit 1; \
	  $(JAVA) -cp $(WORK)/java-classes ConsumerPositive || exit 1; \
	  rm -rf $(WORK)/javamix $(WORK)/javamix-classes; \
	  $(CONTRACT) build test/fixtures/python --output $(WORK)/javamix --targets java || exit 1; \
	  cp test/java/MixCheck.java \
	    $(WORK)/javamix/java/src/main/java/generated_contracts/MixCheck.java; \
	  $(JAVAC) --release 21 -d $(WORK)/javamix-classes \
	    $(WORK)/javamix/java/src/main/java/generated_contracts/*.java || exit 1; \
	  $(JAVA) -cp $(WORK)/javamix-classes generated_contracts.MixCheck || exit 1; \
	else \
	  echo "BLOCKED: javac not found; the generated Java was not compiled"; \
	  exit 1; \
	fi

# Dedicated target check: compile the generated C# with the .NET SDK, run the
# public interop modes and a typed positive consumer, and reject the negative
# API and nullable consumers outside the generated assembly.
test-csharp: build
	@if command -v $(DOTNET) >/dev/null 2>&1; then \
	  rm -rf $(WORK)/csharp $(WORK)/csharp-api $(WORK)/csharp-python $(CSTESTS) $(CSNEGATIVE) $(CSNULLABLE); \
	  $(CONTRACT) build $(FIXTURES) --output $(WORK)/csharp --targets csharp || exit 1; \
	  $(DOTNET) build $(WORK)/csharp/csharp/GeneratedContracts.csproj -v q || exit 1; \
	  $(CONTRACT) build test/fixtures/api --output $(WORK)/csharp-api --targets csharp || exit 1; \
	  $(CONTRACT) build test/fixtures/python --output $(WORK)/csharp-python --targets csharp || exit 1; \
	  mkdir -p $(CSTESTS); \
	  cp $(WORK)/csharp/csharp/*.cs $(CSTESTS)/; \
	  cp $(WORK)/csharp-api/csharp/GeneratedContracts.Api.cs $(CSTESTS)/; \
	  cp $(WORK)/csharp-python/csharp/GeneratedContracts.Python.cs $(CSTESTS)/; \
	  cp test/csharp/Program.cs test/csharp/Interop.cs test/csharp/OptionalMatrix.cs test/csharp/MixCheck.cs test/csharp/ConsumerPositive.cs test/csharp/TestProject.csproj $(CSTESTS)/; \
	  ( cd $(CSTESTS) && $(DOTNET) build -v q ) || exit 1; \
	  DLL=$$(find $(CSTESTS)/bin -name 'CyrografCsharpTests.dll' | head -1); \
	  $(DOTNET) $$DLL interop check $(MESSAGES) $(WORK)/csharp_encoded.json || exit 1; \
	  $(DOTNET) $$DLL interop verify $(WORK)/csharp_encoded.json || exit 1; \
	  $(DOTNET) $$DLL interop invalid $(INVALID) || exit 1; \
	  $(DOTNET) $$DLL interop optional || exit 1; \
	  $(DOTNET) $$DLL consumer || exit 1; \
	  $(DOTNET) $$DLL mix || exit 1; \
	  $(DOTNET) $$DLL optional produce $(OPTIONAL_CASES) $(WORK)/csharp_optional.json || exit 1; \
	  $(DOTNET) $$DLL optional consume $(WORK)/csharp_optional.json || exit 1; \
	  mkdir -p $(CSNEGATIVE); \
	  cp $(WORK)/csharp/csharp/*.cs $(CSNEGATIVE)/; \
	  cp test/csharp/ConsumerNegative.cs test/csharp/NegativeProject.csproj $(CSNEGATIVE)/; \
	  if ( cd $(CSNEGATIVE) && $(DOTNET) build -v q ) > $(WORK)/csharp-negative.log 2>&1; then \
	    echo "FAIL: C# consumer using FromValue compiled"; cat $(WORK)/csharp-negative.log; exit 1; \
	  elif grep -q "FromValue" $(WORK)/csharp-negative.log; then \
	    echo "csharp missing conversion rejected"; \
	  else \
	    echo "FAIL: C# negative consumer failed for the wrong reason"; cat $(WORK)/csharp-negative.log; exit 1; \
	  fi; \
	  mkdir -p $(CSNULLABLE); \
	  cp $(WORK)/csharp/csharp/*.cs $(CSNULLABLE)/; \
	  cp test/csharp/ConsumerPositive.cs test/csharp/ConsumerNullableNegative.cs test/csharp/NegativeProject.csproj $(CSNULLABLE)/; \
	  if ( cd $(CSNULLABLE) && $(DOTNET) build -v q ) > $(WORK)/csharp-nullable.log 2>&1; then \
	    echo "FAIL: C# nullable misuse compiled"; cat $(WORK)/csharp-nullable.log; exit 1; \
	  elif grep -Eq "CS8600|CS8601|CS8602|CS8603|CS8604" $(WORK)/csharp-nullable.log; then \
	    echo "csharp nullable misuse rejected under warnings-as-errors"; \
	  else \
	    echo "FAIL: C# nullable negative failed for the wrong reason"; cat $(WORK)/csharp-nullable.log; exit 1; \
	  fi; \
	else \
	  echo "BLOCKED: dotnet not found; the generated C# was not compiled"; \
	  exit 1; \
	fi

# Dedicated target check: compile the generated Rust with cargo on the declared
# minimum, run a separate consumer crate for the public interop modes, the
# optional cases and the mixed fixture, and reject the negative surface and
# nullable consumers outside the generated crate.
test-rust: build
	@if command -v $(RUST) >/dev/null 2>&1; then \
	  rm -rf $(WORK)/rust $(WORK)/rust-src $(WORK)/rust-drut; \
	  mkdir -p $(RUSTSRC); \
	  cp test/fixtures/orders/*.toml test/fixtures/api/*.toml test/fixtures/python/*.toml $(RUSTSRC)/; \
	  $(CONTRACT) build $(RUSTSRC) --output $(WORK)/rust --targets rust || exit 1; \
	  cp -r test/rust/runner $(RUSTRUNNER); \
	  ( cd $(RUSTRUNNER) && $(RUST) build ) || exit 1; \
	  $(RUSTBIN) interop check $(MESSAGES) $(WORK)/rust_encoded.json || exit 1; \
	  $(RUSTBIN) interop verify $(WORK)/rust_encoded.json || exit 1; \
	  $(RUSTBIN) interop invalid $(INVALID) || exit 1; \
	  $(RUSTBIN) interop optional || exit 1; \
	  $(RUSTBIN) consumer || exit 1; \
	  $(RUSTBIN) mix || exit 1; \
	  $(RUSTBIN) optional produce $(OPTIONAL_CASES) $(WORK)/rust_optional.json || exit 1; \
	  $(RUSTBIN) optional consume $(WORK)/rust_optional.json || exit 1; \
	  mkdir -p $(RUSTNEG); \
	  for name in negative-helper negative-wire negative-serialize negative-option negative-payload; do \
	    cp -r test/rust/$$name $(RUSTNEG)/$$name; \
	    if ( cd $(RUSTNEG)/$$name && $(RUST) build ) > $(RUSTNEG)/$$name.log 2>&1; then \
	      echo "FAIL: Rust negative consumer $$name compiled"; cat $(RUSTNEG)/$$name.log; exit 1; \
	    fi; \
	  done; \
	  grep -q "encode_value" $(RUSTNEG)/negative-helper.log || { echo "FAIL: Rust encode_value was not rejected for the right reason"; exit 1; }; \
	  grep -q "wire" $(RUSTNEG)/negative-wire.log || { echo "FAIL: Rust wire module was not rejected for the right reason"; exit 1; }; \
	  grep -q "Serialize" $(RUSTNEG)/negative-serialize.log || { echo "FAIL: Rust Serialize was not rejected for the right reason"; exit 1; }; \
	  grep -q "Option" $(RUSTNEG)/negative-option.log || { echo "FAIL: Rust Option misuse was not rejected for the right reason"; exit 1; }; \
	  grep -q "ReserveResponse" $(RUSTNEG)/negative-payload.log || { echo "FAIL: Rust payload misuse was not rejected for the right reason"; exit 1; }; \
	  echo "rust negative consumers rejected"; \
	else \
	  echo "BLOCKED: cargo not found; the generated Rust was not compiled"; \
	  exit 1; \
	fi

test-api: build
	CYROGRAF_BIN=$(CONTRACT) SURFACE_TARGETS=ocaml,typescript $(DENO) run \
	  --allow-run --allow-read --allow-write --allow-env \
	  test/deno/api_surface.ts $(WORK)/api_surface $(FIXTURES)

test-api-all: build
	CYROGRAF_BIN=$(CONTRACT) SURFACE_TARGETS=ocaml,typescript,go,dart,python,java,csharp,rust \
	  CYROGRAF_PYTHON=$(PYTHON) CYROGRAF_MYPY=$(MYPY) \
	  CYROGRAF_JAVAC=$(JAVAC) CYROGRAF_JAVA=$(JAVA) CYROGRAF_DOTNET=$(DOTNET) \
	  CYROGRAF_RUST=$(RUST) $(DENO) run \
	  --allow-run --allow-read --allow-write --allow-env \
	  test/deno/api_surface.ts $(WORK)/api_surface_all $(FIXTURES)

# Full optional-field exchange: every ordered pair of the six delivered
# targets really encodes the shared canonical cases through the public
# conversion and the receiver decodes and checks the typed values (30
# directions). One runner per target keeps the matrix extensible.
test-optional-matrix: build test-csharp test-rust
	rm -rf $(WORK)/optional
	$(CONTRACT) build test/fixtures/api --output $(WORK)/optional --targets typescript,go,dart,python,java,csharp,rust
	$(OPTIONAL) produce $(OPTIONAL_CASES) $(WORK)/optional/ocaml.json
	$(DENO) run --allow-read --allow-write test/deno/optional_matrix.ts produce \
	  $(WORK)/optional/typescript $(OPTIONAL_CASES) $(WORK)/optional/typescript.json
	@if command -v $(GO) >/dev/null 2>&1; then \
	  mkdir -p $(WORK)/optional/go/cmd/optional_matrix; \
	  cp test/go/optional_matrix/main.go $(WORK)/optional/go/cmd/optional_matrix/main.go; \
	  ( cd $(WORK)/optional/go && go build -o ../../go_optional_matrix ./cmd/optional_matrix ) || exit 1; \
	  $(WORK)/go_optional_matrix produce $(OPTIONAL_CASES) $(WORK)/optional/go.json || exit 1; \
	else \
	  echo "BLOCKED: go toolchain not found; the optional exchange matrix needs Go"; \
	  exit 1; \
	fi
	@if command -v $(DART) >/dev/null 2>&1; then \
	  cp test/dart/optional_matrix.dart $(WORK)/optional/dart/optional_matrix.dart; \
	  $(DART) $(WORK)/optional/dart/optional_matrix.dart produce \
	    $(OPTIONAL_CASES) $(WORK)/optional/dart.json || exit 1; \
	else \
	  echo "BLOCKED: dart toolchain not found; the optional exchange matrix needs Dart"; \
	  exit 1; \
	fi
	CYROGRAF_PYTHON_PACKAGE=$(WORK)/optional/python $(PYTHON) \
	  test/python/optional_matrix.py produce $(OPTIONAL_CASES) $(WORK)/optional/python.json
	@if command -v $(JAVAC) >/dev/null 2>&1; then \
	  cp test/java/OptionalMatrix.java \
	    $(WORK)/optional/java/src/main/java/generated_contracts/OptionalMatrix.java; \
	  $(JAVAC) --release 21 -d $(WORK)/optional/java-classes \
	    $(WORK)/optional/java/src/main/java/generated_contracts/*.java || exit 1; \
	  $(JAVA) -cp $(WORK)/optional/java-classes generated_contracts.OptionalMatrix \
	    produce $(OPTIONAL_CASES) $(WORK)/optional/java.json || exit 1; \
	else \
	  echo "BLOCKED: javac not found; the optional exchange matrix needs Java"; \
	  exit 1; \
	fi
	@CSDLL=$$(find $(CSTESTS)/bin -name 'CyrografCsharpTests.dll' | head -1); \
	  $(DOTNET) $$CSDLL optional produce $(OPTIONAL_CASES) $(WORK)/optional/csharp.json
	$(RUSTBIN) optional produce $(OPTIONAL_CASES) $(WORK)/optional/rust.json
	@set -e; \
	CSDLL=$$(find $(CSTESTS)/bin -name 'CyrografCsharpTests.dll' | head -1); \
	for producer in ocaml typescript go dart python java csharp rust; do \
	  case $$producer in \
	    ocaml) file=$(WORK)/optional/ocaml.json;; \
	    typescript) file=$(WORK)/optional/typescript.json;; \
	    go) file=$(WORK)/optional/go.json;; \
	    dart) file=$(WORK)/optional/dart.json;; \
	    python) file=$(WORK)/optional/python.json;; \
	    java) file=$(WORK)/optional/java.json;; \
	    csharp) file=$(WORK)/optional/csharp.json;; \
	    rust) file=$(WORK)/optional/rust.json;; \
	  esac; \
	  for consumer in ocaml typescript go dart python java csharp rust; do \
	    if [ "$$producer" != "$$consumer" ]; then \
	      echo "optional exchange $$producer -> $$consumer"; \
	      case $$consumer in \
	        ocaml) $(OPTIONAL) consume $$file;; \
	        typescript) $(DENO) run --allow-read test/deno/optional_matrix.ts consume \
	          $(WORK)/optional/typescript $$file;; \
	        go) $(WORK)/go_optional_matrix consume $$file;; \
	        dart) $(DART) $(WORK)/optional/dart/optional_matrix.dart consume $$file;; \
	        python) CYROGRAF_PYTHON_PACKAGE=$(WORK)/optional/python $(PYTHON) \
	          test/python/optional_matrix.py consume $$file;; \
	        java) $(JAVA) -cp $(WORK)/optional/java-classes generated_contracts.OptionalMatrix \
	          consume $$file;; \
	        csharp) $(DOTNET) $$CSDLL optional consume $$file;; \
	        rust) $(RUSTBIN) optional consume $$file;; \
	      esac; \
	    fi; \
	  done; \
	done
	@echo "optional exchange matrix: 56 directions"

test-drut: build test-csharp
	@go version
	@$(DART) --version
	@$(JAVAC) -version
	@$(RUST) --version
	rm -rf $(WORK)/drut
	$(CONTRACT) build $(FIXTURES) --output $(WORK)/drut/ts --targets typescript
	$(CONTRACT) build $(FIXTURES) --output $(WORK)/drut/all --targets go,dart,python,java,csharp,rust
	mkdir -p $(WORK)/drut/all/go/cmd/interop
	cp test/go/interop/main.go $(WORK)/drut/all/go/cmd/interop/main.go
	( cd $(WORK)/drut/all/go && go vet ./wire/... ./orders/... ./common/... ./cmd/interop ) || exit 1
	( cd $(WORK)/drut/all/go && go build -o ../../go_interop ./cmd/interop ) || exit 1
	cp test/dart/interop.dart $(WORK)/drut/all/dart/interop.dart
	$(DART) analyze $(WORK)/drut/all/dart || exit 1
	$(DENO) run --allow-read --allow-write test/drut/adapter.ts \
	  $(WORK)/drut/valid.json $(WORK)/drut/invalid.json $(WORK)/drut/plan.json
	$(DENO) run --allow-read --allow-write test/deno/interop.ts drut \
	  $(WORK)/drut/ts/typescript $(WORK)/drut/valid.json $(WORK)/drut/invalid.json \
	  $(WORK)/drut/ts_results.json
	$(INTEROP) drut $(WORK)/drut/valid.json $(WORK)/drut/invalid.json \
	  $(WORK)/drut/ocaml_results.json
	$(WORK)/drut/go_interop drut $(WORK)/drut/valid.json $(WORK)/drut/invalid.json \
	  $(WORK)/drut/go_results.json
	$(DART) $(WORK)/drut/all/dart/interop.dart drut \
	  $(WORK)/drut/valid.json $(WORK)/drut/invalid.json $(WORK)/drut/dart_results.json
	CYROGRAF_PYTHON_PACKAGE=$(WORK)/drut/all/python $(PYTHON) test/python/interop.py drut \
	  $(WORK)/drut/valid.json $(WORK)/drut/invalid.json $(WORK)/drut/python_results.json
	cp test/java/Interop.java $(WORK)/drut/all/java/src/main/java/generated_contracts/Interop.java
	$(JAVAC) --release 21 -d $(WORK)/drut/java-classes \
	  $(WORK)/drut/all/java/src/main/java/generated_contracts/*.java || exit 1
	$(JAVA) -cp $(WORK)/drut/java-classes generated_contracts.Interop drut \
	  $(WORK)/drut/valid.json $(WORK)/drut/invalid.json $(WORK)/drut/java_results.json
	$(DOTNET) $$(find $(CSTESTS)/bin -name 'CyrografCsharpTests.dll' | head -1) interop drut \
	  $(WORK)/drut/valid.json $(WORK)/drut/invalid.json $(WORK)/drut/csharp_results.json
	rm -rf $(WORK)/drut/rusttest; cp -r $(WORK)/drut/all/rust $(WORK)/drut/rusttest; \
	cp test/rust/drut_tests.rs $(WORK)/drut/rusttest/src/drut_tests.rs; \
	printf '\n#[cfg(test)]\nmod drut_tests;\n' >> $(WORK)/drut/rusttest/src/lib.rs; \
	( cd $(WORK)/drut/rusttest && CYROGRAF_DRUT_VALID=$(abspath $(WORK)/drut/valid.json) \
	  CYROGRAF_DRUT_INVALID=$(abspath $(WORK)/drut/invalid.json) \
	  CYROGRAF_DRUT_OUT=$(abspath $(WORK)/drut/rust_results.json) $(RUST) test --release ) || exit 1
	$(DENO) run --allow-run --allow-read --allow-write --allow-env test/drut/schemas.ts \
	  $(CONTRACT) $(WORK)/drut/schemas_results.json
	$(DENO) run --allow-read --allow-write test/drut/report.ts \
	  $(WORK)/drut/plan.json $(WORK)/drut/ts_results.json $(WORK)/drut/ocaml_results.json \
	  $(WORK)/drut/go_results.json $(WORK)/drut/dart_results.json \
	  $(WORK)/drut/python_results.json $(WORK)/drut/java_results.json \
	  $(WORK)/drut/csharp_results.json $(WORK)/drut/rust_results.json \
	  $(WORK)/drut/schemas_results.json $(WORK)/drut_report.json

clean:
	$(DUNE) clean
	rm -rf $(WORK)

package: build
	$(DENO) run --allow-run --allow-read --allow-write --allow-env scripts/package.ts

test-release: package
	CYROGRAF_DUNE_FLAGS="$(DUNE_FLAGS)" PYTHON="$(PYTHON)" DOTNET="$(DOTNET)" RUST="$(RUST)" \
	  $(DENO) run --allow-run --allow-read --allow-write --allow-env scripts/test_release.ts

lock:
	$(DUNE) pkg lock