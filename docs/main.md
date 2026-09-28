# Mapa specyfikacji

## Cel i decyzja

`Cyrograf` jest samodzielną biblioteką opisu kontraktów i generowania
typów oraz kodeków, dostępną niezależnie od Well i od przyszłego `ocaml-cell`.
Implementacja wywodzi się z ekstrakcji Well; integracja Well z nową biblioteką
jest osobnym, późniejszym zadaniem. Zakres produktu do wydania definiuje
[release.md](release.md).

Nazwa języka i narzędzi: `Cyrograf`. Nazwa formatu danych: `Drut`.
Checkout nosi nazwę `ocaml-contract`; publiczny moduł OCaml to `Cyrograf`.
Konwersja wiadomości ma wyłącznie `to_drut`/`from_drut` według [api.md](api.md).
Przypięta specyfikacja Drutu i profil tej implementacji są wskazane w
[odniesieniu do formatu](wire.md). Natywne kontrakty zapisuje się w plikach
`.cyrograf`; TOML pozostaje wejściem zgodności i źródłem migracji.

Użytkownik 2026-09-27 zlecił utworzenie projektu, zapisanie specyfikacji oraz
delegowanie implementacji przez skopiowanie odpowiednich fragmentów Well.
Użytkownik 2026-09-28 zlecił dokończenie produktu: własny język, jeden program
z komendami, LSP, formatter, migrację oraz edytory. Polecenie obejmuje
specyfikację i implementację delegowaną do `cyrograf:mechanik`, bez ponownego
oczekiwania na słowo sync. Zatwierdzenie z 2026-09-29 obejmuje małe API
Drutu, nazwę Cyrograf, `List<T>`, wielkie litery typów, snake_case pól/metod
oraz `?` po nazwie pola; implementację użytkownik zlecił temu samemu operatorowi.
Delegowanie obejmuje również generatory Python, Java, C# i Rust według api.md
oraz ich pełny odbiór ze wszystkimi targetami według stp.md.
Wydanie nie obejmuje Protobuf, gRPC ani Proxy.

## Etykiety

- `[impl]`: wiążąca specyfikacja implementacji.
- `[test]`: wiążący plan weryfikacji.

## Artefakty

- [Architektura](arch.md) `[impl]`: zmienności, granice, zależności.
- [Język kontraktów](language.md) `[impl]`: deklaracje, nazwy, diagnostyka.
- [Wejście TOML](toml.md) `[impl]`: zgodność i reguły konwersji.
- [Drut](wire.md) `[impl]`: przypięta specyfikacja formatu i profil implementacji.
- [API i generowanie](api.md) `[impl]`: interfejs biblioteki i artefakty.
- [Kontrakty narzędziowe](tooling.md) `[impl]`: analiza, układ, snapshoty i publikacja.
- [CLI](cli.md) `[impl]`: komendy, pomoc, argumenty i kody wyjścia.
- [LSP](lsp.md) `[impl]`: protokół, dokumenty i funkcje edytorowe.
- [Edytory](editors.md) `[impl]`: integracje edytorów i kolorowanie Markdowna.
- [Wydanie](release.md) `[impl]`: dystrybucja i warunek gotowości.
- [Plan testów](stp.md) `[test]`: sprawdzalne kryteria odbioru.
- [Ekstrakcja](extraction.md) `[impl]`: źródła i zakres kopiowania.
- [Notatka o alternatywach](research.md): kontekst decyzji, nie wymagania.
- [Uzgodnienia API i notacji](design-notes.md): odsyłacze do zatwierdzonych reguł.

Reguła jest definiowana w jednym dokumencie; pozostałe odsyłają do niego.
Projekt dostarcza integracje istniejących edytorów, bez własnego GUI
i bez usługi sieciowej.
