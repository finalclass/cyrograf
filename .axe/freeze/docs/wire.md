# Drut — odniesienie do specyfikacji [impl]

## Źródło reguł formatu

Normatywny opis formatu znajduje się w repozytorium
[finalclass/drut-spec](https://github.com/finalclass/drut-spec).
Cyrograf wskazuje **Drut 1, draft 1**, rewizję:

```text
0d4b4e1e7ef3d7fffe095bfa9b2d88b564e9da8a
```

Poniższe odsyłacze prowadzą do dokumentów w przypiętej rewizji. Kolejne zmiany
domyślnej gałęzi repozytorium nie aktualizują tego celu zgodności automatycznie.

- [Typy, zapis i walidacja](https://github.com/finalclass/drut-spec/blob/0d4b4e1e7ef3d7fffe095bfa9b2d88b564e9da8a/docs/drut-v1.md).
- [Zgodność schematów i wersjonowanie](https://github.com/finalclass/drut-spec/blob/0d4b4e1e7ef3d7fffe095bfa9b2d88b564e9da8a/docs/versioning.md).
- [Przypadki zgodności i sposób ich użycia](https://github.com/finalclass/drut-spec/blob/0d4b4e1e7ef3d7fffe095bfa9b2d88b564e9da8a/docs/conformance.md).
- [Pochodzenie i doprecyzowania pierwszego draftu](https://github.com/finalclass/drut-spec/blob/0d4b4e1e7ef3d7fffe095bfa9b2d88b564e9da8a/docs/provenance.md).

To przypięcie określa cel zgodności implementacji. Wynik weryfikacji musi wskazać
rzeczywiście wykonane przypadki; dotychczasowe testy ekstrakcji nie stanowią
potwierdzenia pełnej zgodności z osobną specyfikacją Drutu.

## Profil Cyrografu

Frontend przyjmuje podzbiór schematów określony w [języku](language.md), w tym
jego reguły identyfikatorów i dozwolone deklaracje. Notacja JSON użyta w zestawie
testowym Drutu służy adapterowi testów; nie staje się nowym wejściem kompilatora.

Obecne nazwy techniczne to `Contract.Wire`, wariant `Wire_v1` oraz identyfikator
kodeka `wire-v1`. Nie są one nagłówkiem wiadomości ani identyfikatorem schematu
przesyłanym wewnątrz payloadu. Błędy biblioteki i wygenerowanych kodeków mają
powierzchnię wskazaną w [API](api.md).

Własne fixture'y ASCII i liczb całkowitych weryfikują także dokładny zapis
tekstu jako regresję tej implementacji. Nie ustanawia to kanonicznego kodowania
Drutu; różne poprawne zapisy float, escape'ów Unicode i kolejności kluczy record
porównujemy semantycznie według specyfikacji formatu.

Pochodzenie zachowania oraz różnica między ścisłą walidacją biblioteki a dawnymi,
tolerancyjnymi kodekami RPC Well są opisane w [ekstrakcji](extraction.md).
