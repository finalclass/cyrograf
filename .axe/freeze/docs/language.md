# Język kontraktów [impl]

## Zakres

Wejściem jest zbiór nazwanych plików TOML. Nazwa modułu pochodzi z nazwy pliku
bez rozszerzenia, np. `Orders.toml` definiuje moduł `Orders`. Kolejność deklaracji
pól w źródle jest częścią schematu; nie zastępuje jej sortowanie alfabetyczne.
Kolejność dostarczenia plików nie wpływa na wynik kompilacji.

Obsługiwany podzbiór Well obejmuje `[msg.Name.struct]`, `[msg.Name.variant]`
oraz opcjonalne `[service.rpc]`. Sam katalog wiadomości bez usług jest poprawny.
Puste struct jest dozwolone; pusty variant jest błędem.

```toml
[service.rpc]
reserve = "ReserveRequest -> ReserveResponse"

[msg.ReserveRequest.struct]
owner_id = "string"
quantity = "int"
note = { type = "string", optional = true }

[msg.Reservation.struct]
id = "string"

[msg.Problem.struct]
code = "string"
message = "string"

[msg.ReserveResponse.variant]
Reserved = "Reservation"
Rejected = "Problem"
Unavailable = "void"

[msg.ReservationBatch.struct]
items = { type = "list", of = "Reservation" }
```

## Typy

- Prymitywy: `string`, `int`, `float`, `bool`, `void`, `date`, `record`.
- Referencja lokalna `Reservation` lub kwalifikowana `Orders.Reservation`.
- Lista: `{ type = "list", of = "Reservation" }`.
- Pole opcjonalne: `{ type = "Reservation", optional = true }`.
- Lista opcjonalna: `{ type = "list", of = "Reservation", optional = true }`.

Typy wiadomości są nazwanymi struct albo variant. Nie ma anonimowych nowych
rodzajów deklaracji ani rekurencyjnych definicji w pierwszym wydaniu.
`optional` jest modyfikatorem pola struct, nie znacznikiem konstruktora wariantu.
Nie obsługujemy zagnieżdżonego optional ani optional void, ponieważ Wire v1
nie rozróżniłby ich wszystkich wartości. W zwykłym polu void wartością jest null.

Znaczenie wartości prymitywnych oraz ich reprezentacja są zdefiniowane
w [Wire](wire.md). Date pozostaje stringiem; nie dodajemy walidacji kalendarza.
Record oznacza obiekt JSON o dynamicznych kluczach, a nie dowolny korzeń JSON.

## Sygnatury

`[service.rpc]` mapuje nazwę metody na `Request -> Response`; oba końce wskazują
nazwane wiadomości lokalne albo kwalifikowane. Informacja trafia do Schema.
Sama deklaracja nie generuje klienta, handlera, routingu ani kodu wywołania.

`ctx` nie jest prymitywem tej biblioteki. Zastosowanie go powoduje diagnostykę
`UnsupportedFrameworkType`, ze wskazaniem konieczności jawnej deklaracji danych
kontekstu lub zastosowania adaptera Well. Nie kopiujemy `RpcCtx` pod nową nazwą.
Tabele `[actor]` należą do przyszłego adaptera Cell; wersja 1 zwraca dla nich
`UnsupportedExtension`, zamiast bezgłośnie odrzucać ich znaczenie.

## Nazwy i diagnostyka

Nazwy modułów, wiadomości i konstruktorów: `[A-Z][A-Za-z0-9_]*`.
Nazwy pól i metod: `[a-z][A-Za-z0-9_]*`. Kwalifikowana referencja ma dokładnie
dwie części `Module.Message`. Słowa kluczowe języka docelowego są escapowane
wyłącznie w wygenerowanym kodzie; nazwy w schemacie i tagi Wire pozostają te same.

Kompilator odrzuca: błędny TOML, nieznane typy i klucze, brak `of` w liście,
nieprawidłowy typ wartości `optional`, duplikaty, nierozwiązane referencje,
cykle, struct i variant jednocześnie, nieprawidłową sygnaturę metody oraz kolizje
nazw po normalizacji w wybranym języku docelowym.
Nie zastępuje błędnej deklaracji przez string ani nie pomija błędnej metody.

Diagnostyka zawiera kod, nazwę pliku, ścieżkę deklaracji i komunikat.
Pozycja wiersza/kolumny jest dodawana, kiedy udostępnia ją parser TOML.
Cały katalog jest sprawdzany przed wytworzeniem artefaktów.
