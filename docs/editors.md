# Integracje edytorów [impl]

## Wspólna granica

Wydanie obejmuje Emacs, Vim, Neovim, VS Code i JetBrains. Każda integracja
rozpoznaje `.cyrograf`, koloruje składnię i łączy się z zainstalowanym `cyrograf lsp`.
Można wskazać ścieżkę programu ze spacjami. Program i argumenty przekazuje się
jako listę, bez składania polecenia shellowego. Brak programu daje czytelny
błąd i instrukcję instalacji, nie uruchamia automatycznego pobierania.

Klienci nie zawierają walidatora typów, kopii formatera ani generatora.
Kolorowanie odróżnia deklaracje, prymitywy, nazwy typów, pola/metody,
komentarze i znaki składni. Niekompletny tekst nie wyłącza kolorowania reszty
pliku; typy w komentarzu pozostają komentarzem. Nie przejmujemy plików TOML.

Reguły kolorowania obejmują wielkie litery typów wbudowanych, `List<T>`,
zagnieżdżone nawiasy `< >`, pole `name?: T` oraz nazwy snake_case.
Te same reguły obowiązują dla samodzielnych źródeł i bloków Markdown.

## Emacs

`editors/emacs/cyrograf-mode.el` udostępnia `cyrograf-mode`, rozpoznanie
rozszerzenia, font-lock, komentarz `//` i podstawowe wcięcia.
Integracja z [Eglot](https://www.gnu.org/software/emacs/manual/html_node/eglot/)
rejestruje `cyrograf lsp` dla diagnostyki, nawigacji i formatowania. Ścieżka
programu jest zmienną użytkownika. Załadowanie pakietu samo nie uruchamia serwera.
Instrukcja obejmuje Emacs i Doom Emacs; nie edytujemy konfiguracji autora.
Doom deklaruje `package!` w `packages.el`, z recepturą GitHub
`finalclass/cyrograf` wybierającą `editors/emacs/cyrograf-mode.el`;
`use-package!` trafia do `config.el`. Po dodaniu pakietu instrukcja wskazuje
`doom sync` i ponowne uruchomienie Emacsa. Program `cyrograf` instaluje się osobno.
Baza to Emacs 29 lub nowszy z Eglot; rzeczywiście sprawdzona wersja jest
w raporcie wydania.

## Vim

`editors/vim/` zawiera `ftdetect`, `syntax`, `ftplugin` i `indent`.
Dokumentacja pokazuje konfigurację [yegappan/lsp](https://github.com/yegappan/lsp)
w Vim9 dla `cyrograf lsp`. Kolorowanie i wcięcia działają bez klienta LSP.
Nie utożsamiamy Vima z Neovimem i nie wymagamy zmiany edytora.

## Neovim

`editors/neovim/` dostarcza konfigurację wbudowanego klienta LSP dla Neovim
0.11 lub nowszego oraz instrukcję instalacji. Uruchamia `cyrograf lsp`
przez listę programu i argumentów; ścieżka programu jest konfigurowalna.
Rozpoznanie pliku, kolorowanie i wcięcia korzystają ze wspólnych zasobów
Vima, bez drugiej ręcznie utrzymywanej składni. Instrukcja opisuje działanie
z klasycznym mechanizmem `syntax`; pakiet nie wymaga parsera Tree-sitter.
Otwarcie `.cyrograf` z włączoną integracją uruchamia obsługę diagnostyki,
przejścia do definicji i formatowania. Testy używają osobnej konfiguracji;
instalacja nie edytuje istniejących plików użytkownika.

## VS Code

`editors/vscode/` rejestruje język, rozszerzenie,
[gramatykę TextMate](https://code.visualstudio.com/api/language-extensions/syntax-highlight-guide),
nawiasy/komentarze i klienta LSP aktywowanego dla dokumentu Cyrografu.
Ustawienie `cyrograf.path` domyślnie wynosi `cyrograf`. Dezaktywacja zatrzymuje
klienta. Format Document używa LSP. Zależności klienta są dołączone do `.vsix`;
użytkownik nie potrzebuje osobnego Node.js ani Deno. API hosta VS Code jest
uzasadnionym wyjątkiem od Deno dla skryptów pomocniczych.

## JetBrains

`editors/jetbrains/` dostarcza importowalny pakiet
[TextMate](https://www.jetbrains.com/help/idea/textmate.html) i gotową
konfigurację serwera oraz mapowania rozszerzenia dla
[LSP4IJ](https://github.com/redhat-developer/lsp4ij). Gramatyka jest wspólnym
artefaktem z VS Code, bez dwóch ręcznie utrzymywanych kopii. Konfiguracja
wskazuje program `cyrograf` i argument `lsp`.
Nie wymagamy własnego PSI ani konkretnej płatnej edycji IDE. Instrukcja
wymienia sprawdzone wersje IDE i LSP4IJ, sposób instalacji, włączenia
kolorowania, diagnostyki i formatowania.

## Bloki kodu w Markdownie

Identyfikator języka bloku kodu to `cyrograf`, zgodnie z [language.md](language.md).
Kolorowanie bloku korzysta z tych samych reguł prezentacji co samodzielny
plik. Nie wymaga kompletnego modułu, poprawnej semantyki ani procesu LSP.
Nie wysyła całego Markdowna do kompilatora i nie zmienia jego treści.

Gwarantowany zakres obejmuje:

- Emacs: bloki w `markdown-mode` i `gfm-mode`, z rejestracją `cyrograf-mode`
  i udokumentowanym włączeniem natywnego kolorowania bloków. `markdown-mode`
  jest opcjonalną zależnością tej funkcji, nie samodzielnych plików Cyrografu.
- Vim i Neovim: bloki w dostarczonym przez edytor trybie składni Markdown,
  z udokumentowaną rejestracją języka. Nie nadpisujemy rejestracji innych
  języków. Wariant z Tree-sitter wymaga osobnej integracji i nie jest
  domyślną obietnicą tego pakietu.
- VS Code: kolorowanie w edytowanym Markdownie oraz w jego wbudowanym
  podglądzie. Adapter bloku osadza wspólną gramatykę `source.cyrograf`;
  podgląd renderuje tokeny bez wykonywania treści kodu i bez pobierania
  zasobów. Reguły tokenów nie są drugim walidatorem języka. Artefakty
  potrzebne podglądowi są dołączone do `.vsix`.

Obsługiwane są bloki otwierane co najmniej trzema backtickami i zamykane
poprawnym ogrodzeniem Markdown; krótszy ciąg wewnątrz bloku go nie zamyka.
Kilka bloków w dokumencie działa niezależnie. Komentarz lub niekompletny
Cyrograf nie przenosi kolorowania na prozę po końcu bloku. Bloki innego
języka oraz bez identyfikatora zachowują zachowanie edytora.

`editors/README.md` rozróżnia edycję Markdowna i renderowanie podglądu.
Zewnętrzne renderery, w tym GitHub.com, wymagają własnej rejestracji języka;
lokalna integracja jej nie zastępuje. W JetBrains sprawdzamy możliwość
kolorowania bloku przez zainstalowany TextMate i zapisujemy faktyczny wynik
oraz wersję; gwarancja Markdowna tego wydania obejmuje powyższe integracje.
Nie deklarujemy wsparcia nieprzetestowanych rendererów ani eksportu HTML.

## Dostarczanie i odbiór

`editors/README.md` ma tabelę instalacji oraz scenariusz: otworzyć dostarczony
przykład, zobaczyć kolory, wprowadzić nieznany typ, naprawić błąd, przejść do
definicji i sformatować plik. Osobny przykład Markdowna zawiera blok
`cyrograf` i instrukcję włączenia kolorowania. Przykłady nie wymagają Well.
Pakiety mogą dzielić dane tokenów i fixture'y; źródłem reguł języka pozostaje kompilator.
Testy określa [stp.md](stp.md). Poprawny plik konfiguracyjny lub archiwum nie
stanowi samodzielnie dowodu działania w edytorze.
