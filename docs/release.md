# Zakres i odbiór wydania 0.1 [impl]

## Produkt

Wydanie 0.1 dostarcza natywny język, zachowane wejście TOML i migrację,
osiem generatorów, ścisłe kodeki Drutu, formatter, LSP i integracje
Emacs/Vim/Neovim/VS Code/JetBrains oraz kolorowanie bloków Markdown
w zakresie [editors.md](editors.md). Target OCaml ma profile reprezentacji
`Int`: natywny (`int`) i js_of_ocaml (`int64`), zgodnie z [api.md](api.md).
Publiczne możliwości narzędzia mieszczą się w jednym programie według
[cli.md](cli.md). Odbiór określa [stp.md](stp.md).

Publiczne biblioteki noszą nazwy `cyrograf`, `cyrograf.compiler`,
`cyrograf.tooling` i `cyrograf.lsp`, z modułami `Cyrograf` i
`Cyrograf_compiler`. API konwersji jest ograniczone do operacji z [api.md](api.md).
Nie dostarczamy publicznych aliasów roboczych nazw Contract.
README i przykłady używają `.cyrograf`; TOML jest wejściem zgodności.
Drut pozostaje przypięty do rewizji wskazanej w [wire.md](wire.md).

## Dystrybucja

Jedno źródło wersji ustala `0.1.0` w metadanych pakietu, wyniku `--version`
i artefaktach. Kandydat jest opisany jako kandydat, dopóki odbiór nie jest
ukończony. Build nie wymaga Well, prywatnego cache autora ani lokalnych
ścieżek spoza repo. Standardowy cache pobranych zależności jest dozwolony;
toolchain i zależności są odtwarzalnie przypięte.

Artefakty: archiwum źródeł, archiwum programu Linux x86_64, pakiety edytorowe
(w tym `.vsix`) i sumy SHA-256. Binarka zawiera runtime OCaml i nie wymaga
kompilatorów, SDK ani interpreterów targetów, Dune lub Deno do swoich komend. Zależności
systemowe, minimalny system i architektura są podane i sprawdzone poza
katalogiem builda. Nie deklarujemy sprawdzonych binarek na platformy,
na których nic nie uruchomiono.

`make install` buduje i instaluje program `cyrograf` oraz publiczne biblioteki
OCaml ze źródeł. Domyślny `PREFIX` to `$(HOME)/.local`; użytkownik może podać
inny prefiks przez `make install PREFIX=/wybrany/katalog`. Program trafia do
`PREFIX/bin/cyrograf`, a biblioteki i metadane zachowują układ instalacyjny
Dune. `DESTDIR` jest opcjonalnym katalogiem stagingu dodanym przed `PREFIX`;
bez jego podania zapis następuje w samym prefiksie. Ścieżki mogą zawierać spacje.

Instalacja korzysta z aktualnych artefaktów publicznego pakietu, działa także
z zarządzaniem zależnościami Dune i nie wymaga ręcznego kopiowania drzewa
`_build/install`. Zainstalowane pliki nie są symlinkami do checkoutu lub `_build`.
Instalacja nie wymaga narzędzi do testów targetów lub edytorów; nie uruchamia
`sudo`, nie zmienia konfiguracji edytora ani `PATH` i nie usuwa obcych plików
w prefiksie. Błąd budowania lub zapisu daje niezerowy kod, bez komunikatu sukcesu.
Powtórzenie instalacji aktualizuje własne artefakty. README pokazuje zwykłą
instalację, własny prefiks i dodanie `PREFIX/bin` do `PATH`, jeżeli jest potrzebne.
Wygenerowany konsument OCaml korzysta z zainstalowanego `cyrograf`.
Generator nie kompiluje projektów odbiorców. Publikacja do opam i marketplace'ów
nie jest warunkiem przygotowania artefaktów.

`make package` tworzy artefakty w ignorowanym `_build/release/`, bez tagowania
lub publikacji. `make test-release` sprawdza instalację i komendy z wypakowanego
artefaktu w nowym katalogu, bez `dune exec`. Do archiwów nie trafiają `.git`,
`.local`, cache, logi pracy ani dane użytkownika.

## CI i dokumentacja użytkownika

CI GitHub uruchamia wymagane sprawdzenia z STP na czystym checkoutcie.
Każdy target rzeczywiście wykonuje testy; brak toolchainu nie jest zielonym skipem.
Wersje narzędzi i sposób pobrania są zapisane w konfiguracji. Pobierane
narzędzia mają zweryfikowane źródło i integralność; nie używamy `curl | sh`.
Nowe własne skrypty pomocnicze używają Deno.

README zawiera instalację, przykłady od kontraktu do wszystkich targetów,
mapę komend i odsyłacze do języka, edytorów, migracji i profilu Drutu.
Zachowuje maskotkę i tagline. Przykłady są wykonywane w testach.
Nie reklamuje pełnej zgodności Drutu na podstawie częściowego korpusu
ani testów prywatnego runtime'u. Pokazuje wyłącznie publiczną konwersję
z api.md, aktualną składnię i faktyczne gwarancje tekstowego API.

## Warunek gotowości

Gotowość wymaga przejścia obowiązkowych testów, sprawdzonych artefaktów
instalacyjnych i smoke testów wszystkich edytorów objętych wydaniem.
Niewykonane sprawdzenie pozostawia odbiór nieukończony; raport wskazuje konkretny brak.
Ograniczenia języka, np. ASCII w nazwach, stanowią jawny profil.

Raport po testach podaje wersje, komendy, kody wyjścia, rewizję Drutu,
zakres korpusu i wyniki instalacji. Nie zapisujemy przewidywanych sukcesów.
Utworzenie tagu, publicznego GitHub Release lub publikacja do rejestrów
wymaga odrębnego polecenia wydania. Przygotowanie kodu i artefaktów jest
objęte bieżącym zleceniem.
