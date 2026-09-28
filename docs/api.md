# API i generowanie [impl]

## Publiczna konwersja wiadomości

Jedynymi publicznymi operacjami konwersji wygenerowanej wiadomości są
`to_drut` i `from_drut`, z pisownią zgodną z językiem docelowym.
Konwersja dotyczy tekstu Drutu. Nie ma osobnych wejść `Bytes`, `Text`,
wartości już sparsowanej ani wyboru kodeka. Nie wystawiamy `Codec`, `Wire`,
`encode`/`decode`, `to_wire`/`of_wire` ani aliasów tych operacji.

Typy wiadomości, ich zwykłe konstruktory i diagnostyka pozostają dostępne.
Wewnętrzne skanery i pomocnicze funkcje generowanego kodu nie stanowią
dodatkowej publicznej powierzchni konwersji. Ich współdzielenie nie może
wymagać od użytkownika importowania runtime'u kodeka lub podawania deskryptora.
Kontrola widoczności korzysta z mechanizmów danego języka; publiczne moduły
wiadomości nie re-eksportują wewnętrznych wejść konwersji.

| Target | Do tekstu Drutu | Z tekstu Drutu |
|---|---|---|
| OCaml | `Name.to_drut value` | `Name.from_drut text` |
| TypeScript | `Name.toDrut(value)` | `Name.fromDrut(text)` |
| Go | `NameToDrut(value)` | `NameFromDrut(text)` |
| Dart | `value.toDrut()` | `Name.fromDrut(text)` |
| Python | `value.to_drut()` | `Name.from_drut(text)` |
| Java | `value.toDrut()` | `Name.fromDrut(text)` |
| C# | `value.ToDrut()` | `Name.FromDrut(text)` |
| Rust | `value.to_drut()` | `Name::from_drut(text)` |

W Go dwie funkcje pakietowe dotyczą zarówno struktur, jak i wariantów;
prefiks typu zastępuje niedostępny wspólny namespace typu i obiektu.
Nie dodajemy równolegle metod kodowania lub ogólnej refleksyjnej konwersji.

`to_drut` waliduje wartość i zwraca jeden poprawny tekst Drutu.
`from_drut` waliduje cały dostarczony tekst i zwraca wiadomość o zadeklarowanym
typie albo jawny błąd. Nie zastępuje wadliwych danych wartościami domyślnymi.
Zakres walidacji tekstu oraz różnicę między tekstem a surowymi bajtami określa
[wire.md](wire.md). Kolejność pól, tagi i zapis Drutu nie zależą od nazw
wygenerowanego API.

## Biblioteki i diagnostyka

Publiczna nazwa biblioteki wykonawczej OCaml to `cyrograf`, a jej modułu
`Cyrograf`. `Cyrograf.Error` definiuje diagnostykę schematu i konwersji.
Błąd zawiera `code`, `message`, `path` i opcjonalne `source`; path wskazuje
deklarację lub wartość przy użyciu nazw ze schematu źródłowego.
`Cyrograf.Schema` udostępnia opis wiadomości i sygnatur potrzebny narzędziom;
nie jest drugim wejściem serializacji danych użytkownika.
Publiczny moduł `Cyrograf.Codec` ani `Cyrograf.Wire` nie istnieje.

Biblioteka kompilatora to `cyrograf.compiler`, moduł `Cyrograf_compiler`.
Fasada kompilatora i narzędzi jest odrębna od API konwersji wiadomości;
nie wymaga jej importowania wygenerowany konsument. Zachowuje czyste
operacje analizy i generowania:

```ocaml
type source = { name : string; text : string }
type target = Ocaml | Typescript | Go | Dart | Python | Java | Csharp | Rust
type ocaml_profile = Native | Js
type artifact = { path : string; contents : string }
val compile :
  sources:source list ->
  (Cyrograf.Schema.t, Cyrograf.Error.t list) result
val generate :
  ?ocaml_profile:ocaml_profile -> ?ocaml_library:string ->
  targets:target list -> schema:Cyrograf.Schema.t -> unit ->
  (artifact list, Cyrograf.Error.t list) result
```

Jedynym formatem generowania jest przypięty Drut; fasada nie wymaga argumentu
wyboru formatu. Nie utrzymujemy publicznych aliasów `Contract`,
`Contract_compiler` ani pakietów `contract.*`.

`name` jest nazwą pliku `.cyrograf` lub `.toml` bez katalogu; `path` artefaktu
jest względny, bez `..` i bez katalogu źródłowego. Zbiory źródeł i targetów
muszą być niepuste, bez duplikatów. Wyniki mają deterministyczną kolejność.
Błąd jednego targetu unieważnia cały wynik. Funkcje nie wykonują I/O.
Poszerzona fasada analizy, zapytań edytorowych, formatowania i migracji jest
określona w [tooling.md](tooling.md).

## Generowane wiadomości

Targety to OCaml, TypeScript, Go, Dart, Python, Java, C# i Rust.
Generatory zachowują struktury,
listy, opcjonalność oraz warianty z payloadami.

OCaml udostępnia w module każdej wiadomości:

```ocaml
type t
val to_drut : t -> (string, Cyrograf.Error.t) result
val from_drut : string -> (t, Cyrograf.Error.t) result
```

`t` jest publicznym rekordem, wariantem albo unit zgodnie z deklaracją,
nie faktycznie abstrakcyjnym typem powyższego skrótu. Rekordy zachowują
konstruktor `make`. OCaml używa algebraicznych wariantów i wyniku `result`.
`string` może zawierać dowolne bajty, dlatego `from_drut` sprawdza UTF-8.
Pole zadeklarowane jako `Int` ma typ `int` w profilu `native` i `int64`
w profilu `js`; pozostałe typy są wspólne dla profili.

TypeScript eksportuje typ wiadomości i wartość pod tą samą nazwą:
obiekt ma wyłącznie `toDrut(value: Name): string` oraz
`fromDrut(text: string): Name`. Wiadomości pozostają zwykłymi obiektami,
bez konieczności tworzenia instancji klasy. Wariant jest rozłączną unią
z tagiem. Błąd konwersji jest wyjątkiem `CyrografError` z kodem,
komunikatem i ścieżką. Przykład:

```ts
import { ReserveRequest } from "./orders.ts";

const text = ReserveRequest.toDrut({ ownerId: "o1", quantity: 2, note: "hi" });
const request = ReserveRequest.fromDrut(text);
```

Go zachowuje dla wariantu wspólny interfejs i osobny typ każdego przypadku
`<Wariant><Konstruktor>`, np. `ReserveResponseReserved`. Payload jest
typowanym polem `Value`; przypadek Void jest pustą strukturą.
Interfejs ma nieeksportowaną metodę znacznika `is<Wariant>`, bez `ToWire`.
Dwie funkcje konwersji mają sygnatury `NameToDrut(value Name) (string, error)`
i `NameFromDrut(text string) (Name, error)`. Nie używają panic.
Dla wariantu odrzucają `nil`, interfejs zawierający nil pointer i nieobsługiwane
implementacje. Typowane przypadki i zwykły `type switch` pozostają sposobem
tworzenia i odczytu wariantu; Go nie gwarantuje kompletności tego switcha.
String Go jest bajtowy, więc dekoder sprawdza UTF-8.

Dart zachowuje generowane klasy i konstruktory przypadków.
Instancyjne `String toDrut()` i fabryka `Name.fromDrut(String text)`
są jedynymi wejściami konwersji. Błędy są wyjątkami `CyrografException`
z kodem, komunikatem i ścieżką. Nie ma publicznych operacji na `List<int>`.

## Opcjonalne pola

Opcjonalność dotyczy pola struktury według [language.md](language.md).
Brak wartości jest odrębny od pustego napisu, zera, false i pustej listy.
Błąd konwersji nie oznacza braku. Reprezentacje są następujące:

- OCaml: `'a option`; `None` oznacza brak, `Some value` obecność.
- TypeScript: `field?: T`, bez `null` i bez generowanego wariantu opcjonalności.
  `fromDrut` pomija nieobecną właściwość, zamiast wpisywać `undefined`.
  `toDrut` przyjmuje jej brak albo `undefined` jako jeden stan braku;
  jawne `null` odrzuca. Odczyt pola ma typ `T | undefined`.
- Go: `*T`; nil pointer oznacza brak, niezerowy pointer obecność.
  Lista opcjonalna ma postać `*[]T`, żeby odróżnić brak od pustej listy.
  Nil slice oznacza pustą listę; nie zastępuje nil pointera opcjonalnego pola.
- Dart: `T?`; `null` oznacza brak. Lista pusta pozostaje wartością obecną.
- Python/Java/C#/Rust: reprezentacje określają profile poniżej.

Publiczne dekodowanie i kodowanie zachowuje zapis braku na pozycji pola
w Drucie według wire.md. Nieobecność nie usuwa pozycji tablicy struktury.
Pole wymagane przyjmuje wyłącznie swój typ; reguła ta nie zakazuje
zadeklarowanego Void ani wartości null wewnątrz dynamicznego Record.

Przykłady i testy TS używają `strict: true` i `exactOptionalPropertyTypes: true`.
Gwarancja statycznego sprawdzenia braku zależy od ustawień konsumenta;
dekoder waliduje wejście niezależnie od nich. Nie generujemy osobnych typów
lub helperów Optional/Option.

## Nazwy w językach docelowych

Nazwy kanoniczne schematu pochodzą ze źródła. Pola i metody OCaml pozostają
w snake_case, TypeScriptu i Darta używają lowerCamelCase, a eksportowane pola
i nazwy metod Go używają UpperCamelCase. Konwersja dzieli nazwę po `_`
i zachowuje cyfry; w Go segment `id` ma pisownię `ID`.
Przykład `owner_id`: OCaml `owner_id`, TS/Dart `ownerId`, Go `OwnerID`.
Te same reguły dotyczą nazw metod w generowanych deklaracjach sygnatur.
Nie zmieniamy tagów konstruktorów ani nazw w deskryptorze.

Konflikt ze słowem zastrzeżonym targetu rozwiązuje końcowy `_`.
Jeżeli wynik koliduje z inną deklaracją albo wymaganym członem API,
`check`/analiza targetu odrzuca kolizję; generator nie dopisuje losowych
sufiksów i nie tworzy błędnego kodu. Nazwy przypadków wariantu i konstruktorów
wartości pozostają zgodne z powyższymi regułami reprezentacji targetu.

Wersja 1 OCaml natywnego celuje w platformy 64-bitowe.
Generowany TS działa w Deno i w przeglądarce bez Node.js, fetch i stanu transportu.
OCaml ma dwa profile reprezentacji `Int`: natywny (`int`, 64-bitowy host) i
js_of_ocaml (`int64`). Profil zmienia wyłącznie reprezentację `Int` w
wygenerowanym kodzie OCaml, nie format Drutu ani API konwersji. Wybór profilu
i minimalny kontrakt informacji kompilatora dla adapterów określa sekcja
„Profil OCaml i informacja dla adapterów". Well nie utrzymuje kopii kodeka.

## Profil OCaml i informacja dla adapterów

### Profil reprezentacji `Int`

Target OCaml ma dwa profile reprezentacji `Int`:

- `native`: `Int → int`, jak dotychczas, dla platform 64-bitowych;
- `js`: `Int → int64`, dla js_of_ocaml 6.2.0 (32-bitowy `int`).

Profil dotyczy tylko wygenerowanego kodu OCaml i jego prywatnego runtime'u
Drutu. Format danych, kolejność pól, tagi i tekst Drutu są identyczne dla obu
profili. Zmiana profilu nie jest zmianą schematu ani wersji formatu.

Profil `js` sprawdza pełny zakres Drutu `[-9007199254740991, 9007199254740991]`
na `int64`. Nie wolno obcinać dużych wartości, zawężać całego Drutu do 32 bitów
ani udawać pełnego wsparcia testami tylko na małych liczbach. Ułamkowy lub
wykładniczy tekst niebędący dokładną liczbą całkowitą w tym zakresie jest
odrzucany tak samo jak w profilu natywnym. Unicode, `Record`, typy zagnieżdżone
i ścisłość parsera obowiązują identycznie.

Wybór profilu jest jawnym parametrem generowania; brak wyboru oznacza `native`.
Generowanie profilu `js` nie wymaga js_of_ocaml w środowisku kompilatora —
powstaje zwykły kod OCaml używający `int64`; kompilację do JS wykonuje
konsument. Publikacja obu profili w jednym workspace używa odrębnych katalogów
artefaktów i odrębnych nazw bibliotek danych OCaml (opcja nazwy biblioteki).

### Minimalna informacja kompilatora dla adapterów

Integrator (np. Well) buduje adaptery wiążące schemat z wygenerowanymi
symbolami i artefaktami. Wystarcza do tego publiczny `Cyrograf.Schema` oraz
publiczna projekcja nazw i ścieżek; nie wymaga importowania prywatnego
`Naming` ani kopiowania jego logiki.

Publiczny kontrakt informacji kompilatora obejmuje dla danego targetu:

- kanoniczną nazwę modułu, wiadomości i metody ze schematu
  (`Cyrograf.Schema` — już istnieje);
- nazwę symbolu wygenerowanego w języku docelowym dla modułu i wiadomości;
- względną ścieżkę artefaktu danych modułu;
- reguła normalizacji nazw pól i metod, wskazana w „Nazwy w językach docelowych".

Dokładny kształt tej projekcji (nazwy funkcji i typów abstrakcyjnych) należy do
implementacji W1, ale musi ona być czysta, bez I/O, i nie może rozszerzać
publicznego API konwersji wiadomości poza `to_drut`/`from_drut`. Adapter używa
wyłącznie tych dwóch operacji do kodowania i dekodowania wiadomości.

Nazwa biblioteki danych OCaml jest parametrem generowania (domyślnie
`generated_contracts`). Pozwala ona umieścić profile natywny i `js` jako dwie
biblioteki w jednym workspace bez kolizji nazw Dune.

## Python, Java, C# i Rust

Wszystkie cztery targety realizują te same reguły języka i Drutu co pozostałe.
Nie dodają konstrukcji źródłowych, transportu ani drugiego formatu.
Sygnatury rpc pozostają metadanymi deskryptora; nie wymagają generowania
klienta lub serwera. Poniższe profile określają minimalne wersje konsumenta;
wersje narzędzi odbioru są przypięte w CI.

| Typ źródłowy | Python 3.11 | Java 21 | C# / .NET 10 | Rust 1.85, edition 2024 |
|---|---|---|---|---|
| String, Date | str | String | string | String |
| Int | int | long | long | i64 |
| Float | float | double | double | f64 |
| Bool | bool | boolean | bool | bool |
| Void | None | java.lang.Void (null) | CyrografUnit | () |
| List<T> | list[T] | java.util.List<T> | List<T> | Vec<T> |
| Record | dict[str, object] | Map<String, Object> | Dictionary<string, JsonElement> | serde_json::Map<String, serde_json::Value> |
| opcjonalne pole T | T \| None | Optional<T> | T? | Option<T> |

Nazwy z bibliotek standardowych są w tabeli skrótami kwalifikowanych nazw.
Generyki Javy używają boxed Long/Double/Boolean dla prymitywów.
CyrografUnit jest pustym typem wartościowym, którego jedyna wartość oznacza
Void; nie jest kodekiem. Record ma korzeń obiektowy, wartości ograniczone
rekurencyjnie do JSON oraz reguły liczb z wire.md. JsonElement z dekodera
pozostaje ważny po zwróceniu wiadomości; Undefined jest błędem kodowania.

Szerszy rodzimy zakres int nie rozszerza zakresu Drutu. Liczby całkowite
są sprawdzane przed zaokrągleniem, również w listach i referencjach.
Float ma semantykę skończonego binary64. Date pozostaje tekstem, bez
niejawnej konwersji na typ daty. Wymagane referencje, listy i teksty
nie przyjmują null/None; wyjątki to jawny Void i wartości wewnątrz Record.

### Python

Wygenerowany pakiet to `generated_contracts`; moduł Orders jest plikiem
`generated_contracts/orders.py`. Struktura jest dataclass z adnotacjami
typów i argumentami keyword-only; opcjonalne pola mają domyślne None.
Nie generuje się domyślnych wartości dla wymaganych pól.
Wariant jest klasą bazową Name i odrębnymi dataclass `NameCase`;
payload to typowane pole `value`, przypadek Void nie ma payloadu.
Dekoder wariantu zwraca właściwy podtyp, który można rozpoznać przez
isinstance lub match. Nie obiecujemy zamkniętej hierarchii klas Pythona;
nieobsługiwany podtyp jest błędem kodowania.

Wiadomość ma `value.to_drut() -> str` oraz
`Name.from_drut(text: str) -> Name` (metoda klasowa dla deklarowanego typu).
Błąd to CyrografError z code, message i path.
Runtime sprawdza wartości niezależnie od adnotacji; bool nie jest Int
ani Float tylko dlatego, że w Pythonie dziedziczy po int.
Prywatne moduły/helpery mają początkowy `_`, nie są w `__all__` ani
re-eksportowane jako publiczne konwersje. Python nie zapewnia izolacji
prywatności przez kompilator; ta konwencja jest jawną granicą pakietu.
Publiczne modele mają pełne adnotacje oraz `py.typed`.
Runtime używa wyłącznie biblioteki standardowej, bez Pydantic.

### Java

Pakiet to `generated_contracts`. Każdy moduł źródła jest publiczną klasą
zewnętrzną, np. Orders; typy wiadomości są zagnieżdżone:
`Orders.ReserveRequest`. Struktura jest record, wariant sealed interface
z własnymi zagnieżdżonymi record przypadków, np.
`Orders.ReserveResponse.Reserved(Reservation value)`.
Przypadek Void jest record bez komponentów.
Rekordy/payloady mają rzeczywiste typy, bez Object w miejsce znanych typów.

Każda wiadomość udostępnia `String toDrut()` i statyczne
`Name fromDrut(String text)`. Błąd konwersji to CyrografException
dziedziczący po RuntimeException, z kodem, komunikatem i ścieżką.
Optional.empty() oznacza brak; sam null zamiast Optional jest błędem.
Helpery są private lub package-private; nie tworzą publicznego API konwersji.
Kod wymaga JDK 21, bez preview i bez bibliotek zewnętrznych.

### C#

Namespace to `GeneratedContracts.<Module>`, np. GeneratedContracts.Orders.
Struktura jest sealed record z typowanymi właściwościami; wariant abstract
record Name z zagnieżdżonymi sealed record przypadków, np. Name.Reserved,
z typowanym `Value`. Void nie tworzy pola payloadu.
Generator nie obiecuje sprawdzania kompletności pattern matching przez C#;
nieobsługiwany podtyp wariantu jest błędem kodowania.

Konwersje to instancyjne `string ToDrut()` oraz statyczne
`Name FromDrut(string text)`; błąd to CyrografException z Code, Message
i Path. Nullable jest włączone. Brak to null, oddzielny od false, zera
i pustej listy; to samo dotyczy typów referencyjnych i wartościowych.
Runtime odrzuca null w wymaganej wartości niezależnie od ostrzeżeń kompilatora.
Helpery są private/internal, bez publicznego ToValue/FromValue.
Target to net10.0; wystarcza .NET i System.Text.Json, bez pakietów NuGet.

### Rust

Crate to `generated_contracts`; moduł Orders staje się `orders`.
Struktura to struct z publicznymi typowanymi polami, wariant to enum
z typowanym payloadem i pustymi przypadkami dla Void.
Opcjonalność używa Option<T>, lista Vec<T>. Użytkownik tworzy wartości
zwykłym literałem struct lub konstruktorem enum; nie musi podawać deskryptora.

Wiadomość ma `pub fn to_drut(&self) -> Result<String, CyrografError>` i
`pub fn from_drut(text: &str) -> Result<Self, CyrografError>`.
CyrografError udostępnia code, message i path oraz implementuje Display/Error.
Błędne wejście nie wywołuje panic. Helpery nie są publiczne poza crate.
Dopuszczalne zależności runtime to serde i serde_json; wygenerowane
wiadomości nie implementują publicznych Serialize/Deserialize jako
alternatywnego API konwersji. Rodzime typy JSON dla Record są danymi.
Samo serde_json::Value nie zwalnia z wykrywania duplikatów kluczy
i zachowania dokładnych lexemów liczb przed walidacją Int.

### Nazwy, organizacja i zależności nowych targetów

Pola i metody Python/Rust zachowują snake_case, Java używa lowerCamelCase,
C# PascalCase: owner_id → owner_id / ownerId / OwnerId.
Typy wiadomości zachowują nazwy ze schematu; nazwy modułów Python/Rust
są konwertowane do snake_case, np. OrderItems → order_items.
Reguła słów kluczowych i kolizji z sekcji nazw obowiązuje także tutaj.
Nazwy pomocnicze, nazwy klas zewnętrznych oraz generowane człony rekordów
również nie mogą przesłonić wiadomości lub jej pól bez diagnostyki.

Output jest samodzielnym projektem konsumenta:

- `python/`: pakiet generated_contracts, py.typed i pyproject.toml;
- `java/`: źródła pakietu generated_contracts pod src/main/java oraz
  pom.xml z poziomem Java 21; kod można skompilować również samym javac;
- `csharp/`: GeneratedContracts.csproj dla net10.0 i źródła;
- `rust/`: Cargo.toml z edition 2024, rust-version 1.85 i src/lib.rs.

Pliki publiczne jawnie pokazują dwa wejścia konwersji oraz typy danych.
Nazwy pomocnicze nie pojawiają się jako alternatywne konwersje w README
i publicznych eksportach. Importy między modułami działają poza checkoutem
Cyrografu. Narzędzie generuje te projekty bez wywoływania ich toolchainów
i bez pobierania pakietów z sieci.

## Artefakty kompilacji

Komendy, wybór źródeł i diagnostykę terminala określa [cli.md](cli.md).

Wynik: podkatalogi `ocaml/`, `typescript/`, `go/`, `dart/`, `python/`,
`java/`, `csharp/`, `rust/` wybranych targetów,
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
nie kolidować z biblioteką wykonawczą `cyrograf`. Go importuje moduły według
parametru CLI `--go-module MODULE_PATH`, domyślnie `generated_contracts`;
odpowiadający temu `go.mod` jest częścią outputu Go. TS używa importów względnych
z rozszerzeniem `.ts`; metadane Darta i Dune pozwalają kompilować sam output
w niezależnym konsumencie.

Wynik generowania jest deterministyczny: nie zawiera zegara, losowych danych
ani absolutnej ścieżki źródła. Własność, bezpieczeństwo ścieżek i publikację
całego wyniku określa `ArtifactAccess` w [tooling.md](tooling.md).

## Zależności wygenerowanych artefaktów

- OCaml: `cyrograf` i jego zależność JSON, bez `well.core`, Eio i Otoml.
  Profil `js` zakłada obsługę `int64` przez js_of_ocaml; nie dodaje zależności
  od Well ani od js_of_ocaml w bibliotece danych natywnych.
- TS: samowystarczalny kod lub mały lokalny helper; bez zależności npm.
- Go: standardowa biblioteka, w tym JSON; bez bibliotek HTTP lub gRPC.
- Dart: standardowe biblioteki, w tym `dart:convert`; bez `package:http`.
- Python/Java/C#/Rust: zależności i wersje wskazane w profilach powyżej.

W output nie ma Proxy, Rpc.post, globalnych rejestrów usług, make_spec,
inicjalizacji serwera, endpointów `/rpc/`, nagłówków CSRF ani automatycznego ctx.
Wyjątki i helpery dekodowania nie mogą importować frameworka.
