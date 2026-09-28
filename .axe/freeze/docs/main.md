# Mapa specyfikacji

## Cel i decyzja

`Cyrograf` jest samodzielną biblioteką opisu kontraktów i generowania
typów oraz kodeków, dostępną niezależnie od Well i od przyszłego `ocaml-cell`.
Pierwsze wydanie kopiuje i dostosowuje istniejące rozwiązanie Well; integracja
Well z nową biblioteką jest osobnym, późniejszym zadaniem.

Nazwa języka i narzędzi: `Cyrograf`. Nazwa formatu danych: `Drut`.
Checkout nosi nazwę `ocaml-contract`; obecny moduł publiczny to `Contract`,
wariant wyboru formatu to `Wire_v1`, a identyfikator kodeka to `wire-v1`.
Przypięta specyfikacja Drutu i profil tej implementacji są wskazane w
[odniesieniu do formatu](wire.md). Język deklaracji kontraktów jest oparty na TOML.

Użytkownik 2026-09-27 zlecił utworzenie projektu, zapisanie specyfikacji oraz
delegowanie implementacji przez skopiowanie odpowiednich fragmentów Well.
Pierwsze wydanie nie obejmuje Protobuf, gRPC ani generowania Proxy.

## Etykiety

- `[impl]`: wiążąca specyfikacja implementacji.
- `[test]`: wiążący plan weryfikacji.

## Artefakty

- [Architektura](arch.md) `[impl]`: zmienności, granice, zależności.
- [Język kontraktów](language.md) `[impl]`: deklaracje, nazwy, diagnostyka.
- [Drut](wire.md) `[impl]`: przypięta specyfikacja formatu i profil implementacji.
- [API i generowanie](api.md) `[impl]`: interfejs biblioteki, CLI i artefakty.
- [Plan testów](stp.md) `[test]`: sprawdzalne kryteria odbioru.
- [Ekstrakcja](extraction.md) `[impl]`: źródła i zakres kopiowania.
- [Notatka o alternatywach](research.md): kontekst decyzji, nie wymagania.

Reguła jest definiowana w jednym dokumencie; pozostałe odsyłają do niego.
Nie ma interfejsu graficznego ani usług sieciowych tego projektu.
