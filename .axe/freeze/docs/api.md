# API i generowanie [impl]

## Biblioteka

`Contract.Schema` udostępnia model zadeklarowanych wiadomości i sygnatur oraz
kwalifikowane nazwy i uporządkowane pola. Nie zawiera wykonania usług.
`Contract.Error` definiuje diagnostykę schematu i kodowania wraz ze ścieżką.
Dokładne reprezentacje wewnętrzne mogą być prywatne; publiczne `.mli` muszą
umożliwiać adapterowi odczyt całego opisu bez odczytywania TOML ponownie.

`Contract.Codec` ma następującą minimalną powierzchnię:

```ocaml
type 'a t
val make :
  id:string ->
  encode:('a -> (string, Contract.Error.t) result) ->
  decode:(string -> ('a, Contract.Error.t) result) ->
  'a t
val id : 'a t -> string
val encode : 'a t -> 'a -> (string, Contract.Error.t) result
val decode : 'a t -> string -> ('a, Contract.Error.t) result
```

Są to sygnatury widoczne z klienta; implementacja modułów wewnątrz `Contract`
używa odpowiednich lokalnych ścieżek. `string` oznacza niezmienny bufor bajtów.
Codec nie określa adresu odbiorcy ani sposobu wysłania bufora.

`Contract_compiler` udostępnia:

```ocaml
type source = { name : string; text : string }
type target = Ocaml | Typescript | Go | Dart
type format = Wire_v1
type artifact = { path : string; contents : string }
val compile :
  sources:source list ->
  (Contract.Schema.t, Contract.Error.t list) result
val generate :
  targets:target list -> format:format -> schema:Contract.Schema.t ->
  (artifact list, Contract.Error.t list) result
```

`name` jest nazwą pliku TOML bez katalogu; `path` jest względną ścieżką wyniku
bez `..` i bez prefiksu katalogu źródłowego. `Error.t` zawiera `code`, `message`,
`path` oraz opcjonalne `source`; path jest ścieżką deklaracji lub wartości.
Katalog źródeł i lista targetów muszą być niepuste, bez duplikatów.
Lista modułów w Schema oraz lista artefaktów mają deterministyczną kolejność.
Operacje nie czytają ani nie zapisują plików; taki klient może działać w buildzie,
edytorze lub w CLI. Błędy jednego targetu unieważniają cały wynik generowania.

## Generowane wiadomości

Targety wersji 1: `ocaml`, `typescript`, `go`, `dart`.
Generatory zachowują struktury, listy, opcjonalność oraz warianty z payloadami.
W OCaml wariant jest algebraicznym typem sumy; TS używa rozłącznej unii z tagiem.
Dart może zachować reprezentację wariantu istniejącą w Well wraz z konstruktorami
i walidacją legalnej pary tag/payload.

Go generuje dla wariantu wspólny interfejs oraz osobny typ dla każdego przypadku.
Typ przypadku to `<Wariant><Konstruktor>`, np. `ReserveResponseReserved`; przypadki
pozostają różnymi typami również wtedy, gdy mają ten sam typ payloadu. Przypadek
z payloadem ma typowane pole `Value`, a przypadek void jest pustą strukturą.
Interfejs zawiera nieeksportowaną metodę znacznika `is<Wariant>` oraz
`ToWire() (any, error)`. Publiczne wejścia kodeka to `<Wariant>ToWire`,
`<Wariant>FromWire`, `<Wariant>ToWireText` i `<Wariant>FromWireText`; odrzucają
`nil` oraz nieobsługiwane implementacje. Interfejs nie jest zamkniętym sum type,
a Go nie sprawdza kompletności `type switch`. Przykład użycia:

```go
var response orders.ReserveResponse =
    orders.ReserveResponseReserved{Value: reservation}

switch result := response.(type) {
case orders.ReserveResponseReserved:
    fmt.Println(result.Value.Id)
case orders.ReserveResponseRejected:
    fmt.Println(result.Value.Message)
case orders.ReserveResponseUnavailable:
    fmt.Println("Brak dostępności")
default:
    return fmt.Errorf("nieobsługiwana odpowiedź")
}
```

Generowane OCaml udostępnia dla każdej wiadomości:

```ocaml
type t
val to_wire : t -> (Contract.Wire.value, Contract.Error.t) result
val of_wire : Contract.Wire.value -> (t, Contract.Error.t) result
val codec : t Contract.Codec.t
```

Typ `t` jest publicznym rekordem, wariantem albo unit zgodnie z deklaracją,
nie faktycznie abstrakcyjnym typem powyższego skrótu. Rekordy mają wygodną
funkcję `make`. Wyniki `result` świadomie odróżniają nową powierzchnię od
tolerancyjnego RPC Well i pozwalają bezpiecznie obsłużyć błędne dane.

TS eksportuje typy oraz `encodeName` i `decodeName`; błędne dane powodują
udokumentowany wyjątek kodowania z kodem i ścieżką. Go udostępnia `ToWire`
i `NameFromWire` zwracające również `error`, a dla wariantu funkcję
`<Wariant>ToWire`; nie używa panic do zgłaszania błędu wejścia. Dart udostępnia
`toWire` i `fromWire`, ze zdefiniowanym wyjątkiem błędu kodowania. Dla każdego targetu istnieją także funkcje przejścia
między wiadomością a tekstem Wire, które sprawdzają reguły [Wire](wire.md).
Szczegółowa pisownia helperów poza wskazanymi nazwami należy do projektu `.mli`
i dokumentacji wygenerowanej biblioteki, bez zmiany semantyki powyższych operacji.

Wersja 1 OCaml natywnego celuje w platformy 64-bitowe. Generowany TS działa
w Deno i w przeglądarce bez Node.js, fetch i globalnego stanu transportu.
Nie kopiujemy osobnego targetu `ocaml_browser` razem z jego Proxy; ewentualna
obsługa zakresów int w js_of_ocaml pozostaje osobnym rozszerzeniem.

## CLI

```text
cyrograf check SOURCE_DIR
cyrograf build SOURCE_DIR --output OUTPUT_DIR --targets ocaml,typescript,go,dart
```

`check` kompiluje schemat i wypisuje diagnostykę; sukces daje exit 0, błąd 1.
`build` domyślnie wybiera wszystkie cztery targety. Nieznana flaga, format lub
target daje exit 2. Nie ma trybu generowania Proxy.
`SOURCE_DIR` zawiera pliki `.toml` jednego katalogu, bez rekursywnego skanowania.
Obsługujemy ścieżki ze spacjami. Pusty katalog daje czytelny błąd.

Wynik: podkatalogi `ocaml/`, `typescript/`, `go/`, `dart/` wybranych targetów,
plik modelu `schema.json` z jawną wersją formatu deskryptora `1`, oraz manifest
względnych ścieżek wygenerowanych plików. Deskryptor odwzorowuje Schema, nie
odsyła do procesu kompilatora ani runtime'u aplikacji.

Deskryptor ma korzeń `{ "format": 1, "modules": [...] }`. Każdy moduł ma `name`,
`messages` i `methods`. Wiadomość ma `name`, `kind` (`struct` albo `variant`)
oraz odpowiednio uporządkowane `fields` lub `constructors`; każdy element tych
tablic ma `name` i `type`. Metoda ma `name`, `request` i `response`, z w pełni
kwalifikowanymi referencjami. Typ jest obiektem: `primitive` z `name`, `reference`
z kwalifikowanym `name`, albo `list`/`optional` z `element`; dyskryminatorem
każdego z nich jest `kind`. Nazwy modułów i wiadomości są sortowane, ale kolejność
pól i konstruktorów pochodzi ze źródła. Manifest jest tablicą ścieżek artefaktów
w pliku `manifest.json`; nie obejmuje samego siebie.

Wygenerowana biblioteka OCaml domyślnie nazywa się `generated_contracts`, aby
nie kolidować z biblioteką wykonawczą `contract`. Go importuje moduły według
parametru CLI `--go-module MODULE_PATH`, domyślnie `generated_contracts`;
odpowiadający temu `go.mod` jest częścią outputu Go. TS używa importów względnych
z rozszerzeniem `.ts`; metadane Darta i Dune pozwalają kompilować sam output
w niezależnym konsumencie.

Wynik generowania jest deterministyczny: nie zawiera zegara, losowych danych
ani absolutnej ścieżki źródła. Całość jest przygotowana przed podmianą outputu.
Źródła i output muszą być odrębne. Istniejące obce pliki w output powodują błąd;
generator nie usuwa ich. Kolejny build własnego katalogu usuwa nieaktualne
artefakty z poprzedniego manifestu. Błąd parsowania, walidacji lub generowania
zachowuje poprzedni poprawny output. Nie obiecujemy transakcji odpornej na utratę
zasilania przy publikowaniu wielu plików.

## Zależności wygenerowanych artefaktów

- OCaml: `contract` i jego zależność JSON, bez `well.core`, Eio i Otoml.
- TS: samowystarczalny kod lub mały lokalny helper; bez zależności npm.
- Go: standardowa biblioteka, w tym JSON; bez bibliotek HTTP lub gRPC.
- Dart: standardowe biblioteki, w tym `dart:convert`; bez `package:http`.

W output nie ma Proxy, Rpc.post, globalnych rejestrów usług, make_spec,
inicjalizacji serwera, endpointów `/rpc/`, nagłówków CSRF ani automatycznego ctx.
Wyjątki i helpery dekodowania nie mogą importować frameworka.
