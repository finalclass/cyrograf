# Jedna komenda Cyrograf [impl]

## Odkrywanie możliwości

Publiczny program nazywa się wyłącznie `cyrograf`. Bez argumentów wypisuje
czytelną pomoc na stdout i kończy się kodem 0. Pomoc wymienia komendy, ich rolę,
krótkie przykłady oraz wskazuje `cyrograf help COMMAND`. Działają też `--help`,
`-h`, `help`, `help COMMAND` i `COMMAND --help`. Każda pomoc kończy się kodem 0.
`--version` wypisuje wersję wydania. Nie ma osobnej binarki formatera lub LSP.

```text
cyrograf check SOURCE_DIR [--targets ocaml,typescript,go,dart,python,java,csharp,rust]
cyrograf build SOURCE_DIR --output OUTPUT_DIR \
  [--targets ocaml,typescript,go,dart,python,java,csharp,rust] [--go-module MODULE_PATH]
cyrograf format [PATH ...] [--check]
cyrograf format --stdin --filename NAME.cyrograf
cyrograf migrate SOURCE_DIR --output OUTPUT_DIR
cyrograf lsp [--stdio]
cyrograf help [COMMAND]
cyrograf --version
```

Wszystkie komendy obsługują ścieżki ze spacjami i `--` kończące parsowanie
opcji. Nieznana komenda, flaga, target, brak wymaganej wartości lub niedozwolone
połączenie flag daje pomoc właściwej komendy na stderr i exit 2. Błąd źródła,
walidacji, I/O lub brak zgodności z `format --check` daje exit 1. Sukces daje 0.
Nie ma niejawnego pobierania narzędzi ani kontaktu z siecią.

Informacje i błędy są po angielsku, ze stabilnymi kodami błędów. Diagnostyka
źródła w terminalu ma postać `path:line:column: CODE: message`, z numeracją
od 1 i kolumną liczoną w skalarach Unicode. Przy braku pozycji pokazuje się
plik i ścieżkę deklaracji. Kolejność błędów jest deterministyczna.

## Źródła projektu

`check`, `build` i `migrate` czytają jeden wskazany katalog bez rekursji,
wybierając zwykłe pliki `.cyrograf` i `.toml`. Rozszerzenia są rozróżniane
wielkością liter. Symlinki źródeł są odrzucane czytelnym błędem, nie śledzone.
Inne pliki nie są źródłami. Pusty zbiór źródeł daje `EmptySources`.
Wszystkie wybrane moduły tworzą jeden projekt; duplikaty modułów są błędem
według [języka](language.md). Katalog ani nazwy plików nie są wykonywane.

## Check i build

Targety mają identyfikatory z przykładu CLI powyżej; C# to `csharp`.
Domyślne targety obu komend to wszystkie osiem języków; jawna lista nie może
być pusta ani zawierać duplikatów. `check` obejmuje reguły języka i kolizje
nazw wybranych targetów. Nie zapisuje artefaktów. `build` publikuje wynik
określony w [API](api.md); opcja `--go-module` zachowuje istniejące znaczenie.
Kodowania i generowanie Proxy nie są wybierane dodatkowymi, nieopisanymi flagami.

## Format

Bez `PATH` wybierany jest bieżący katalog. Ścieżka może oznaczać natywny plik
albo katalog, z którego wybierane są `.cyrograf` bez rekursji. Powtórzone pliki
po normalizacji ścieżki przetwarza się raz. Jawnie wskazany plik TOML daje błąd
`UnsupportedSourceFormat`; TOML we wskazanym katalogu nie podlega formatowaniu.
Brak natywnych plików daje czytelny błąd. Nie podążamy za symlinkami.

Domyślny tryb zapisuje zmienione pliki. `--check` niczego nie zapisuje;
wypisuje wymagające formatowania ścieżki i zwraca 1, gdy choć jeden plik
różni się od wyniku. Błąd składni któregokolwiek wejścia uniemożliwia zapis
całego zestawu. Błąd semantyki nie blokuje poprawienia układu źródła.
Zasady stylu i zapisu określa [tooling.md](tooling.md).

`--stdin` czyta dokładnie jeden dokument z wejścia standardowego i wypisuje
wyłącznie wynik formatowania na stdout. Wymaga `--filename` z natywnym
rozszerzeniem; nazwa służy diagnostyce i nigdy nie jest odczytywana z dysku.
Nie łączy się z `PATH` ani `--check`. Błędy trafiają wyłącznie na stderr.

## Migrate

Konwertuje `.toml` na `.cyrograf` w odrębnym katalogu; zastane pliki natywne
kopiuje zgodnie z [toml.md](toml.md). Nie usuwa wejścia. Poprawny projekt
zawierający wyłącznie pliki natywne może być skopiowany w ten sam sposób.
Wynik obejmuje tylko źródła kontraktów i `manifest.json`, bez przypadkowych
plików katalogu. Katalog wyjściowy podlega tym samym regułom własności
i przygotowania co wynik builda; nie ma flagi wymuszającej usuwanie obcych plików.

Po sukcesie komunikat wskazuje katalog wyniku i komendę jego sprawdzenia.
Jeśli przeniesiono komentarze TOML, komunikat mówi o zmianie ich położenia.
Błędne wejście lub niezgodny po konwersji schemat nie daje częściowego wyniku.

## LSP

`lsp` oraz `lsp --stdio` uruchamiają ten sam tryb opisany w [lsp.md](lsp.md).
Po uruchomieniu stdout zawiera wyłącznie ramki protokołu. Nie wypisuje się
pomocy, banera, kolorowych komunikatów ani informacji o wersji na stdout.
Sama pomoc `cyrograf lsp --help` nie uruchamia serwera.
