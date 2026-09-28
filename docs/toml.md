# Wejście TOML i konwersja [impl]

## Obsługiwane deklaracje

Pliki `.toml` pozostają obsługiwanym wejściem zgodności w tym wydaniu.
Nazwa pliku bez rozszerzenia jest nazwą modułu. Wspólne reguły nazw, typów,
referencji, kolejności i sygnatur definiuje [language.md](language.md).

Notacja TOML zachowuje małe litery prymitywów (`string`, `int`, `float`,
`bool`, `void`, `date`, `record`), tabelę `type = "list"` i flagę `optional`.
Frontend odwzorowuje je na te same typy co `String`, `List<T>` oraz `field?: T`
w języku natywnym. Wspólne reguły snake_case dla pól/metod obowiązują także
w TOML; niezgodna nazwa jest błędem, nie niejawną zmianą identyfikatora.

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

Obsługiwany podzbiór to `[msg.Name.struct]`, `[msg.Name.variant]` oraz
opcjonalne `[service.rpc]`. Typem jest string z nazwą prymitywu/referencji
albo tabela inline z `type`. Lista ma `type = "list"` i `of` będące stringiem
z nazwą prymitywu/referencji. Modyfikator pola to `optional = true` lub `false`.
`of` w typie innym niż list jest błędem. Ta składnia zgodności nie wprowadza
nowego zapisu zagnieżdżonych list; natywny język może je wyrazić.

Frontend odrzuca nieznane klucze, brak `of`, zły typ `optional`, równoczesne
struct/variant i wadliwy string sygnatury. `[actor]` daje
`UnsupportedExtension`. Nie pomija nieznanych metod ani tabel. Błąd gramatyki
TOML zachowuje kod `InvalidToml`.

Diagnostyka zawsze zawiera plik i ścieżkę deklaracji. Zakres, którego parser
TOML nie potrafi wiarygodnie wyznaczyć, jest jawnie nieobecny; nie zgadujemy
lokalizacji wyszukiwaniem pierwszego podobnego stringa. Natywne pliki mają
obowiązkowe zakresy według [language.md](language.md).

## Migracja

Komenda i zasady zapisu należą do [cli.md](cli.md). Konwersja zachowuje nazwy
modułów, wiadomości, pól, konstruktorów i metod, ich znaczenie, kolejność pól
i konstruktorów oraz kwalifikowane referencje. Nie zmienia Drutu ani
reprezentacji wygenerowanych języków.

Wynik TOML używa `List<T>`, wielkich liter typów i `?` po nazwie pola,
drukowanych przez `Layout`. Komentarze zachowuje
się w kolejności jako komentarze `//` na początku odpowiadającego pliku,
z zachowaniem tekstu po znaku `#`; konwerter jawnie informuje, że położenie
komentarzy zostało przeniesione. Nie obiecuje identycznego przypisania do pól.
`#` wewnątrz stringa TOML nie jest komentarzem. Natywne pliki zastane w tym
samym projekcie są kopiowane bez zmiany ich bajtów.

Przed publikacją całe wyjście musi przejść ponowną analizę i dać schemat równy
wejściowemu, z uwzględnieniem kolejności. Wyniki generowania dla tych samych
targetów także pozostają równoważne. Konwerter nie używa generatorów do
odtwarzania deklaracji i nie nadpisuje źródeł.
