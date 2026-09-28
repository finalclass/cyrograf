# Serwer językowy [impl]

## Granica i protokół

`cyrograf lsp` jest lokalnym adapterem do wspólnego `Tooling`.
Nie otwiera TCP, HTTP ani usługi w tle. Implementuje podzbiór
[LSP 3.17](https://github.com/microsoft/language-server-protocol/blob/gh-pages/_specifications/lsp/3.17/specification.md)
wymieniony poniżej, przez JSON-RPC na stdin/stdout. `Content-Length` liczy
bajty UTF-8. Odczyt obsługuje niepełną ramkę oraz kilka ramek w jednym odczycie.
Logi trafiają wyłącznie na stderr.

Cykl życia obejmuje `initialize`, `initialized`, `shutdown`, `exit`.
`exit` po `shutdown` kończy się 0, bez wcześniejszego `shutdown` kodem 1.
EOF kończy proces bez pętli oczekiwania. Żądania przed inicjalizacją i po
zamknięciu otrzymują błędy protokołu. Nieznane żądanie daje MethodNotFound,
a nieznane powiadomienie jest ignorowane. Nie ogłasza się niezaimplementowanych
capabilities. `$/cancelRequest` nie może uszkodzić sesji; anulowany wynik nie
zastępuje nowszego stanu. Analiza może być początkowo synchroniczna.

Serwer ogłasza `positionEncoding = "utf-16"`. Wiersze i kolumny LSP liczone
są od 0. Konwersja z zakresów analizy uwzględnia znaki spoza BMP i CRLF;
offset bajtowy nie jest kolumną LSP.

## Projekt i aktualność tekstu

Dokument ma `languageId = "cyrograf"`. Wydanie obsługuje URI `file:`.
Projekt dokumentu stanowią pliki kontraktów bezpośrednio w jego katalogu,
tak jak w CLI. Projekty w różnych katalogach nie łączą automatycznie modułów.
Można odwołać się do źródła TOML z tego samego katalogu. Inny schemat URI daje
czytelny komunikat, bez próby potraktowania go jak ścieżki.

Synchronizacja to `TextDocumentSyncKind.Full`: `didOpen`, `didChange`,
`didSave`, `didClose`. Niezapisany pełny tekst z edytora ma pierwszeństwo przed
dyskiem. Nowy plik z `file:`, jeszcze nieistniejący na dysku, uczestniczy
w projekcie. Po zamknięciu obowiązuje bieżąca wersja dyskowa albo brak pliku.

Zmiana deklaracji odświeża także diagnostykę zależnych plików. Każde zdarzenie
dokumentu i żądanie funkcji językowej odświeża zamknięte źródła z dysku.
`workspace/didChangeWatchedFiles` odświeża odpowiednie otwarte projekty;
serwer nie wymaga od klienta watchera. Zmiana na dysku staje się widoczna
najpóźniej przy następnym takim zdarzeniu lub żądaniu.

Wynik jest związany ze snapshotem. Starsza/powtórzona wersja `didChange`
nie zastępuje nowszej. Reguły overlay i rewizji są w [tooling.md](tooling.md).

## Funkcje wydania

| Metoda | Zachowanie |
|---|---|
| `textDocument/publishDiagnostics` | błędy składni, semantyki i kolizji wszystkich targetów z api.md, zgodne z domyślnym `check`; kod i zakres |
| `textDocument/formatting` | wynik wspólnego formatera, jako edycja całego dokumentu lub brak edycji |
| `textDocument/hover` | nazwa i typ symbolu albo brak wyniku |
| `textDocument/definition` | definicja referencji lokalnej lub kwalifikowanej, także w drugim pliku |
| `textDocument/documentSymbol` | struktury, warianty, pola, konstruktory i metody z zakresami |
| `textDocument/completion` | słowa deklaracji, prymitywy i typy odpowiednie do miejsca; po `Module.` wiadomości tego modułu |

Prezentacja typów i completion używa aktualnej notacji language.md:
`String`, `List<T>` i opcjonalności pola. Wewnątrz argumentu `List<...>`
działają completion oraz definicja referencji, także kwalifikowanej.
Wbudowany `List` nie jest odwołaniem do pliku użytkownika.

Diagnostyka jest wypychana po zmianach. Usunięcie błędu publikuje pustą listę
właściwego dokumentu. Zamknięcie czyści jego diagnostykę edytorową i aktualizuje
pozostałe otwarte dokumenty. Jeśli klient obsługuje wersję diagnostyki,
serwer ją podaje. Nieznana pozycja błędu TOML może być pustym zakresem na
początku pliku; nie jest reklamowana jako dokładna lokalizacja.

Formatowanie dokumentu z błędem składni zwraca błąd żądania z wyjaśnieniem,
bez częściowych edycji i zapisu. Nierozwiązana referencja nie blokuje
formatowania. Brak symbolu pod kursorem daje `null` lub pustą listę zgodnie
z metodą, nie wyjątek procesu.

Rename, semantic tokens, code actions, źródła zdalne i przyrostowe cache
nie są wymaganiami tego wydania. Podstawowe kolorowanie zapewniają
[pakiety edytorów](editors.md), bez drugiego walidatora semantycznego.
