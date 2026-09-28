# Kontrakty narzędziowe [impl]

## Źródła i lokalizacje

`source` pozostaje parą `name`, `text` według [api.md](api.md). Nazwa zawiera
rozszerzenie wybierające frontend. Wewnątrz analizy źródło ma niezmienny tekst,
tożsamość i indeks początków wierszy. Pozycja wewnętrzna jest offsetem bajtowym
UTF-8; zakres jest półotwarty `[start_byte, end_byte)`. Nie przechowujemy w nim
kolumn UTF-16 ani numerów ekranowych zależnych od tabulatorów.

`Diagnostic` zawiera `Cyrograf.Error.t`, opcjonalny zakres oraz
powiązane lokalizacje z komunikatem. Zakres odnosi się do źródła wskazanego
w błędzie; reguły jego obecności są w [language.md](language.md) i
[toml.md](toml.md). Stare API `compile` zwraca `Error.t` z początkiem lokalizacji
przeliczonym na wiersz/kolumnę. Nowe API analizy udostępnia cały zakres.
Kod i ścieżka pozostają niezależne od prezentacji terminala lub JSON-RPC.

## Analysis

Rola: z dostarczonych tekstów wyprowadzić znaczenie kontraktu i miejsca
deklaracji, również gdy dokument jest chwilowo niekompletny.

| Operacja | Wejście | Obietnica wyniku |
|---|---|---|
| `analyze` | niezmienna lista źródeł | dokumenty składniowe, diagnostyka i indeks symboli; poprawny schemat tylko przy braku błędów |
| `schema` | wynik analizy | pełny poprawny schemat albo lista błędów; nigdy częściowy schemat |
| `symbols` | wynik i nazwa pliku | symbole dokumentu z rodzajem, zakresem deklaracji i zakresem nazwy |
| `definition` | wynik, plik, offset | definicja referencji pod kursorem albo brak; lokalne i kwalifikowane odwołania |
| `describe` | wynik, plik, offset | nazwa i typ wskazanego symbolu albo brak, bez HTML i formatowania LSP |
| `complete` | wynik, plik, offset | propozycje poprawnych w danym miejscu nazw/typów/słów kluczowych bez domyślnego dopisywania szablonów |

Są to fasety jednego modelu analizy, nie sześć usług. Składnia natywna i TOML
tworzą wspólny model deklaracji; wiązanie nazw i walidacja nie są powielone.
Indeks zachowuje użycia typów, lokalizacje pól, konstruktorów i metod.
Wyniki zapytań nie zgadują definicji w innym projekcie. Błąd składni w jednym
miejscu nie usuwa poprawnie rozpoznanych, niezależnych deklaracji z indeksu.

`Emission.validate` dodaje błędy wybranych targetów do wyniku narzędziowego.
Nie jest częścią parsowania. Nie wywołuje generatora tylko po to, by przeczytać
jego tekst. Przy braku błędów `check` i `build` z tymi samymi targetami zgadzają
się co do poprawności projektu.

Publiczna fasada `Cyrograf_compiler` udostępnia `compile` i `generate`,
analizę z powyższymi zapytaniami, formatowanie pojedynczego źródła
i migrację listy źródeł. Dokładne typy abstrakcyjne w `.mli` mogą ukrywać drzewa,
ale muszą udostępniać opisane wyniki i lokalizacje. Te funkcje są czyste: brak
odczytów plików, procesów, globalnego workspace i zależności od edytora.

## Layout

Rola: nadać tekstowi ustalony układ bez zmiany znaczenia ani zgubienia komentarzy.
`format_document` otrzymuje poprawny składniowo dokument natywny i zwraca tekst.
`print_declarations` otrzymuje deklaracje oraz komentarze do migracji i zwraca
natywny tekst. Błędy semantyczne, np. brakująca referencja, nie blokują pierwszej
operacji; błędy składni ją blokują i nie powstaje częściowy wynik.

Styl wydania:

- LF, brak BOM i końcowych spacji; jeden końcowy LF w niepustym dokumencie,
  pusty dokument bez komentarzy jest pustym stringiem.
- Dwie spacje wcięcia, jedna deklaracja pola/przypadku na wiersz, bez średników.
- Jedna spacja po `:` i wokół `->`, jedna przed otwierającą klamrą;
  bez spacji wewnątrz `List<T>`, `Module.Type` i nawiasów payloadu.
  Opcjonalne pole ma postać `name?: T`; `?` przylega do nazwy i `:`.
- Niepuste klamry są wielowierszowe; pusta struktura to `struct Name {}`.
- Między deklaracjami najwyższego poziomu jest jeden pusty wiersz; wewnątrz
  deklaracji zachowuje się najwyżej jeden zastany pusty wiersz.
- Kolejność deklaracji, pól i konstruktorów nie zmienia się. Nie sortujemy
  pól ani nie przepisujemy referencji lokalnej na kwalifikowaną.
- Treść i kolejność komentarzy są zachowane. Komentarz za elementem pozostaje
  przy nim, oddzielony jedną spacją; osobny komentarz dostaje wcięcie miejsca,
  do którego należy. Komentarze wewnątrz wielowierszowego typu nie giną;
  taki typ może pozostać wielowierszowy. Treść komentarza po `//` nie jest
  zawijana ani poprawiana, poza usunięciem końcowych spacji.
- Zapis jawnego `(Void)` może pozostać jawny; formatter nie normalizuje
  semantycznych synonimów, jeśli utrudniłoby to zachowanie komentarzy.

Pierwsze wydanie ma jeden styl bez pliku konfiguracji. Wynik jest
deterministyczny, idempotentny i semantycznie równoważny wejściu. LSP i CLI
używają identycznego `Layout`; parametry wcięcia przesłane przez edytor nie
zmieniają ustalonego stylu projektu.

## WorkspaceAccess

Rola: udostępniać tekst i rewizję źródeł oraz bezpiecznie zapisywać zmiany źródeł.

- `capture`: ustala zbiór źródeł zgodnie z [CLI](cli.md) lub [LSP](lsp.md)
  i zwraca niezmienny snapshot; późniejsza analiza nie odczytuje dysku.
- `apply_overlay`: przyjmuje pełny tekst i rosnącą wersję otwartego dokumentu;
  starsza lub powtórzona wersja nie zastępuje nowszej.
- `close_overlay`: usuwa wersję edytora i przywraca odczyt aktualnego pliku,
  albo brak źródła, jeśli plik nie istnieje.
- `replace_sources`: dostaje przygotowane teksty i rewizje wejściowe; przed
  zapisem sprawdza, czy pliki nie zmieniły się od odczytu, a konflikt zgłasza
  jako `SourceChanged`, bez nadpisania nowszego tekstu.

Snapshot nie jest transakcją całego filesystemu. Rewizja to numer otwartego
bufora albo tożsamość odczytanych bajtów pliku, nie sam czas modyfikacji.
Zapis formatera przygotowuje wyniki dla wszystkich plików przed pierwszą
podmianą, zachowuje prawa pliku i używa pliku tymczasowego w tym samym
filesystemie. Nie obiecuje atomowej wieloplikowej transakcji przy awarii procesu.
Żaden automatyczny zapis LSP nie omija mechanizmu edycji klienta.

## ArtifactAccess

Rola: publikować kompletny wynik będący własnością jednego polecenia.
`publish` przyjmuje katalog docelowy i listę przygotowanych artefaktów;
zwraca listę opublikowanych ścieżek albo błąd.

Ścieżki artefaktów i manifestu są względne, unikalne, bez segmentów `..`,
ścieżek absolutnych i przechodzenia przez symlinki. Manifest musi być poprawną
listą stringów. Obcy plik lub niepoprawny manifest blokuje publikację.
Wejście, wynik i ich podkatalogi nie mogą na siebie nachodzić; sprawdzenie
uwzględnia rzeczywiste ścieżki, nie wyłącznie ich tekstową pisownię.

Cały wynik jest przygotowywany w katalogu tymczasowym przed zmianą poprzedniego
wyniku. Błąd walidacji, generowania lub przygotowania zapisu pozostawia stary
wynik nietknięty. Przy błędzie podmiany zachowuje się poprzednie dane i zgłasza
ich lokalizację, jeśli automatyczne odtworzenie nie jest możliwe. Sukces usuwa
tylko poprzednie własne artefakty, których nie ma już w nowym manifeście.
Nie obiecujemy odporności transakcji wielu plików na utratę zasilania.

## Tooling

Rola: realizować pracę na jednym obrazie projektu i decydować, kiedy wolno
udostępnić lub zapisać wynik. Komendy są kompozycjami tych samych komponentów.

- Sprawdzenie: snapshot, wspólna analiza, walidacja wybranych targetów,
  uporządkowana diagnostyka.
- Build: sprawdzenie, emisja wszystkich wybranych targetów, publikacja dopiero
  po sukcesie całości. Nie uruchamia kompilatorów języków docelowych u użytkownika.
- Format: rozpoznanie składni każdego pliku, układ, przygotowanie wszystkich
  zmian, zwrot edycji lub zapis według trybu CLI. Nie wymaga pełnego projektu.
- Migracja: analiza wejścia, wydruk źródeł zgodnie z [toml.md](toml.md),
  analiza całego wyniku, porównanie schematów i publikacja dopiero przy zgodności.
- Obsługa edytora: analiza aktualnego snapshotu i zapytania do indeksu;
  wynik oznaczony rewizją. Wynik starej rewizji nie zastępuje nowszego.

Zmiana procedury nie może wprowadzić parsera lub walidatora w adapterze.
Warunki błędów oraz powierzchnia komend należą do [cli.md](cli.md), a protokół
edytora do [lsp.md](lsp.md).
