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

Publiczna konwersja ma wyłącznie tekstowe `to_drut`/`from_drut`
według [API](api.md). Wiadomość nie przesyła identyfikatora kodeka,
nazwy modułu runtime ani deskryptora schematu. Błędy mają powierzchnię z API.
Duże litery typów w języku, `List<T>`, zapis `field?: T` i nazwy w językach
docelowych nie zmieniają formatu Drutu. Brak opcjonalnego pola pozostaje
JSON-owym `null` na jego pozycji; lista pusta pozostaje `[]`.

Własne fixture'y ASCII i liczb całkowitych weryfikują także dokładny zapis
tekstu jako regresję tej implementacji. Nie ustanawia to kanonicznego kodowania
Drutu; różne poprawne zapisy float, escape'ów Unicode i kolejności kluczy record
porównujemy semantycznie według specyfikacji formatu.

Zakres liczb całkowitych Drutu jest wspólny dla wszystkich profili i targetów,
także dla OCaml w profilu js_of_ocaml. Profil `js` reprezentuje `Int` jako
`int64` i sprawdza dokładną dziesiętną wartość przed konwersją, bez zawężania
do 32-bitowego `int` js_of_ocaml i bez obcinania wartości spoza `int`. Profile
różnią się wyłącznie reprezentacją w wygenerowanym kodzie OCaml, nie treścią
ani walidacją tekstu Drutu.

Wejścia tekstowe wszystkich targetów są ścisłe: odrzucają trailing data,
komentarze JSON, duplikaty kluczy po odkodowaniu, niesparowane surogaty
i początkowy BOM. Sprawdzają dokładną dziesiętną wartość `int` przed
zaokrągleniem binary64. Nie ma publicznej ścieżki przez już sparsowane wartości.
Encoder nie emituje BOM; BOM wewnątrz napisu jest zwykłym znakiem.

Stringi OCaml i Go są bajtowe: ich `from_drut` dodatkowo odrzuca niepoprawne
UTF-8. Stringi TS, Darta, Pythona, Javy i C# są dostarczonym tekstem Unicode.
Rust przyjmuje `&str`, który już gwarantuje poprawne UTF-8. Te targety nie mają publicznego
wejścia bajtowego, więc nie gwarantują wykrycia błędów bajtów utraconych przez
wcześniejsze dekodowanie do tekstu. Odrzucają niepoprawne sekwencje surogatów
w dostarczonym tekście lub escape'ach JSON. Konsument odbierający bajty jest
odpowiedzialny za ich ścisłe przekształcenie do tekstu.

Raport zgodności rozdziela publiczne API wiadomości, testy wewnętrznego
runtime'u oraz wektory niewyrażalne przez dany publiczny interfejs. Test
prywatnej funkcji lub walidacja UTF-8 w adapterze testów nie dowodzi istnienia
publicznego dekodera bajtowego targetów przyjmujących gotowy tekst. Prywatne szczegóły implementacji
nie są podstawą do dodania publicznych funkcji `Bytes`.
Ewentualne limity zasobów muszą być opisane w raporcie i dokumentacji.

Pochodzenie zachowania oraz różnica między ścisłą walidacją biblioteki a dawnymi,
tolerancyjnymi kodekami RPC Well są opisane w [ekstrakcji](extraction.md).
