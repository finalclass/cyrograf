# Język Cyrograf [impl]

## Zakres i moduły

Natywne źródło ma rozszerzenie `.cyrograf`, kodowanie UTF-8 i nazwę modułu
pochodzącą z nazwy pliku: `Orders.cyrograf` definiuje `Orders`. Obsługiwane
deklaracje to `struct`, `variant` i `rpc`. Pusty plik jest poprawnym pustym
modułem; pusty zbiór źródeł jest błędem. Katalog może zawierać tylko wiadomości.
Alternatywne wejście zgodności opisuje [toml.md](toml.md).

Kanoniczny identyfikator języka w ogrodzeniu Markdown to `cyrograf`.
Rozszerzenie źródeł pozostaje `.cyrograf`; nie ma aliasów `.cg` ani `.cyro`.
Zakres kolorowania bloków i zależności edytorów opisuje [editors.md](editors.md).

Kolejność pól i konstruktorów jest częścią schematu. Kolejność dostarczenia
plików nie wpływa na wynik. Referencje do późniejszych deklaracji są dozwolone.
Wszystkie moduły jednego projektu są dostarczane razem; nazwa kwalifikowana
nie pobiera pliku ani pakietu z sieci. Odkrywanie źródeł opisuje [cli.md](cli.md).

```cyrograf
struct ReserveRequest {
  owner_id: String
  quantity: Int
  note?: String
}

struct Reservation {
  id: String
}

struct Problem {
  code: String
  message: String
}

variant ReserveResponse {
  Reserved(Reservation)
  Rejected(Problem)
  Unavailable
}

struct ReservationBatch {
  items: List<Reservation>
}

rpc reserve(ReserveRequest) -> ReserveResponse
```

## Reguły leksykalne

Nazwy modułów, wiadomości i konstruktorów: `[A-Z][A-Za-z0-9_]*`.
Nazwy pól i metod są małymi literami w snake_case:
`[a-z][a-z0-9]*(_[a-z0-9]+)*`. Wielkie litery, początkowy/końcowy `_`
i puste segmenty między `_` są niedozwolone. Referencja kwalifikowana ma
dokładnie dwie części `Module.Message`. Identyfikatory są rozróżniane wielkością liter.
ASCII w nazwach jest świadomym profilem tego języka; komentarze mogą zawierać
dowolne poprawne Unicode. Niepoprawne UTF-8 daje błąd źródła.

Słowa `struct`, `variant`, `rpc` są kontekstowe: rozpoczynają deklarację na
poziomie dokumentu, ale mogą być nazwą pola lub metody. Nazwy typów wbudowanych
`String`, `Int`, `Float`, `Bool`, `Void`, `Date`, `Record` oraz `List` są
zastrzeżone jako nazwy typów: nie wolno nimi nazwać struktury lub wariantu.
Wariant może mieć tak nazwany konstruktor, ponieważ jest to odrębna przestrzeń nazw.
Reguły języka docelowego nie zmieniają nazw kanonicznych schematu ani tagów
Drutu; odwzorowanie pól i metod określa [api.md](api.md).

`//` rozpoczyna komentarz do końca wiersza. Nie ma komentarzy blokowych,
literałów wartości, makr, importów wykonywalnych ani wyrażeń. LF i CRLF są
akceptowane. Jedno początkowe UTF-8 BOM jest akceptowane i pomijane przy
formatowaniu. Spacje i tabulatory poza komentarzami nie mają znaczenia.

## Gramatyka

Poniższa gramatyka używa `{ X }` dla powtórzenia, `[ X ]` dla opcjonalności;
znaki w cudzysłowach są tokenami źródła.

```text
document = { separator | declaration } ;
declaration = structure | variant | method ;
structure = "struct" upper "{" { separator | field end_member } "}" ;
variant = "variant" upper "{" { separator | case end_member } "}" ;
field = lower [ "?" ] ":" type ;
case = upper [ "(" type ")" ] ;
method = "rpc" lower "(" reference ")" "->" reference end_method ;
type = primitive | reference | "List" "<" type ">" ;
reference = upper [ "." upper ] ;
primitive = "String" | "Int" | "Float" | "Bool" | "Void" | "Date" | "Record" ;
separator = newline | ";" ;
```

`lower` oznacza nazwę pola/metody zgodną z regułą snake_case, a `upper`
nazwę rozpoczynającą się wielką literą. Prymitywy są rozpoznawane przed
referencją. Nierozwiązana poprawna składniowo nazwa typu daje
`UnresolvedReference`. `List` wymaga dokładnie jednego argumentu typu.
`List<>`, `List<A, B>` i zastosowanie innego typu jako `Box<A>` dają
`InvalidSyntax`; definicje generyków i parametrów typu nie są obsługiwane.
Składnia `<...>` pozostawia miejsce na późniejsze rozszerzenie, bez
niejawnego rozpoznawania nieznanych typów jako parametrów.

Natywny frontend nie przyjmuje aliasów małymi literami, zapisu list `[T]`
ani `?` za typem. Wejście TOML zachowuje notację opisaną w [toml.md](toml.md).

`end_member` oznacza co najmniej jeden separator albo bezpośrednio następujące
zamknięcie `}` bez jego konsumowania. `end_method` oznacza separator albo EOF.
Po deklaracji zakończonej `}` separator jest opcjonalny. W nawiasach `< >` i
`()` nowe wiersze są białymi znakami; średniki nadal są niedozwolone wewnątrz
typu. Nowa linia kończąca komentarz działa jak zwykła nowa linia. Nie wolno
zapisać dwóch pól lub przypadków w jednym wierszu bez średnika.

## Znaczenie typów i deklaracji

- `struct` ma uporządkowane pola; pusty `struct` jest dozwolony.
- `variant` ma co najmniej jeden unikalny przypadek. `Unavailable` oznacza
  payload `Void`; `Unavailable(Void)` ma to samo znaczenie.
- Lista `List<T>` może być zagnieżdżona, np. `List<List<String>>`.
- `?` występuje wyłącznie po nazwie pola `struct`, przed `:`:
  `note?: String`, `items?: List<Reservation>`. Oznacza możliwość braku
  całego pola. Pusta lista jest wartością obecną, odrębną od braku.
  Opcjonalne elementy list, opcjonalne payloady wariantów, podwójne `?`
  i opcjonalne `Void` są błędami. Nie ma wbudowanego typu Optional/Option.
  Reprezentację w językach docelowych określa [api.md](api.md).
- Nazwane wiadomości są strukturami albo wariantami. Nie ma aliasów typów,
  generyków, dziedziczenia, wartości domyślnych ani definicji rekurencyjnych.
- Końce `rpc` wskazują nazwane wiadomości lokalne lub kwalifikowane. Sygnatura
  jest metadanymi, bez automatycznej implementacji lub transportu.

Prymitywy odwzorowują odpowiednio `string`, `int`, `float`, `bool`, `void`,
`date` i `record` w [Drucie](wire.md); zmiana pisowni języka nie zmienia danych.
`Date` nie dodaje walidacji kalendarza, a `Record` oznacza dynamiczny obiekt
JSON. Zwykłe pole `Void` jest dozwolone. `Ctx` daje `UnsupportedFrameworkType`;
nie jest ukrytym kontekstem aplikacji. Rozszerzenia aktorowe nie należą do języka tego wydania.

## Walidacja i diagnostyka

`Analysis.Semantics` wspólnie dla obu frontendów wykrywa niepoprawne nazwy,
duplikaty, nierozwiązane referencje, cykle, puste warianty, niedozwoloną
opcjonalność i nieprawidłowe końce metod. Duplikat modułu jest błędem także
w parze `Orders.toml` / `Orders.cyrograf`; nie ma preferowania jednego pliku.
Osobno sprawdza się kolizje nazw po przekształceniu na wybrane targety.

Każdy błąd natywnego źródła ma kod, komunikat, plik, zakres źródła i, gdy da się
ją wyznaczyć, ścieżkę deklaracji. Błąd EOF ma pusty zakres na końcu dokumentu.
Zakres wskazuje błędny token lub deklarację, nie zawsze cały plik. Błąd
duplikatu wskazuje drugą definicję i lokalizację pierwszej jako powiązaną.
Nowe kody składni to `InvalidSyntax`, `InvalidSourceEncoding` i
`UnsupportedSourceFormat`; istniejące kody semantyczne zachowują znaczenie.

Analiza edytorowa może odzyskać kolejne deklaracje po błędzie i zwrócić
częściowy indeks. Nie może przedstawić częściowego schematu jako poprawnego
wyniku `compile` ani wygenerować kodu z błędnego projektu.
