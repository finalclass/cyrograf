# Ekstrakcja z Well [impl]

## Pochodzenie

Źródło: [finalclass/well](https://github.com/finalclass/well), commit
`5c573753367f10d7226f5eaedf1adbeacab2c09d`, licencja MIT.
Kopiujemy odpowiednie fragmenty; nie dodajemy Well jako zależności ani submodułu.
Zachowujemy oryginalną informację copyright i licencję w LICENSE.

| Źródło w Well | Zakres przeniesienia |
|---|---|
| `lib/well_cli/contract_types.ml` | Model typów wiadomości i opis sygnatur; bez narzuconego ctx frameworka. |
| `lib/well_cli/contract_parser.ml` | Składnia TOML, kolejność pól, referencje i porządkowanie typów; diagnostyka według language.md. |
| `lib/well_cli/contract_codegen.ml` | Generatory samych typów, konstruktorów i odwzorowania Wire w czterech językach. |
| `lib/well/actor_contract.ml` | Wyłącznie przydatne czyste fragmenty walidacji schematu/wartości; bez rejestracji, aktorów i runtime'u. |
| `lib/well/actor/CONTRACT.md` | Punkt odniesienia dla ścisłej walidacji i poprawnej reprezentacji Wire. |
| `test/contract_codegen_test/fixtures/Echo.toml` | Mały fixture języka i typów, bez oczekiwań dotyczących Proxy. |

Zależności wskazane w [architekturze](arch.md) zastępują twarde odniesienia
do Well. Kod źródłowy służy do kopii implementacji; o wymaganym zachowaniu
nowej biblioteki rozstrzyga ta specyfikacja.

## Elementy pozostające w Well

Z generatora nie przenosimy generate_make_spec, generate_convenience_fns,
globalnego `_service_ref`, generate_ts_proxy, generate_ts_rpc, generate_go_calls,
HTTP helperów Go, generate_dart_proxy ani generate_ocaml_browser_proxy/rpc.
Nie przenosimy automatycznych IMPL z Well.rpc_ctx, Well.Service.spec,
Well.Actor.Generated, message_type witness zależnego od Actor, handlerów,
importów transportu ani zależności `well.core` w wygenerowanym Dune.

Nazwy funkcji są wskazówkami dla przypiętej wersji donora; usunięcie tych nazw
nie wystarcza, jeśli pozostał kod realizujący tę samą funkcję.

## Różnice konieczne do usamodzielnienia

1. Wyjścia generatorów zależą od małej biblioteki danych lub standardowej
   biblioteki targetu, a nie od frameworka.
2. Sygnatury są metadanymi; tworzenie działającego klienta lub usługi wymaga
   przyszłego adaptera.
3. Błędne dane mają jawną diagnostykę zgodnie z Wire, zamiast niejawnego
   podstawienia wartości domyślnych z części dawnych kodeków RPC.
4. Kopiowane generatory muszą przejść rzeczywistą kompilację i wymianę fixture'ów.
   Ewentualne błędy donora naprawiamy w kopii bez zmiany jego checkoutu.

Zakres ekstrakcji określa pochodzenie kodu; dalszą gotowość produktu definiuje
[release.md](release.md). Przełączenie Well na tę bibliotekę, wycofanie jego
kopii generatora, publikacja opam, nowy format danych i adapter Erlanga są
osobnymi zadaniami.
