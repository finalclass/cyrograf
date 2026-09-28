# Plan testów [test]

## Odbiór początkowej ekstrakcji

Implementacja dostarcza `make build`, `make check` i `make test`.
`make check` sprawdza typy OCaml i generowanego TS; `make test` wykonuje poniższe
przypadki i testy wygenerowanego kodu. `make test-all` obejmuje ponadto kompilację
i wykonanie fixture'ów Go i Dart. Brak toolchainu jest oznaczonym blokującym
brakiem weryfikacji, nie sukcesem ani cichym pominięciem testu.
Zależności OCaml są opisane w projekcie Dune/opam; build nie wymaga Well.
Skrypty pomocnicze wykonuje Deno.

## Kontrakt języka

Na przykładzie z language.md oraz osobnym module wspólnych typów sprawdzamy
lokalne i kwalifikowane referencje, warianty, listy, optional, pusty struct,
znaczenie kolejności pól i deklaracje metod bez kodu ich wywołania.
Przestawienie plików wejściowych nie zmienia artefaktów.
Nieznany typ, cykl, kolizja nazw targetu, malformed RPC, brak of, duplikat,
nieprawidłowy optional, ctx oraz actor dają przewidziane diagnostyki ze ścieżką.

## Zgodność Wire z Well

Zapisujemy fixture'y oczekiwanego Wire z przypiętej wersji źródłowej Well,
nie wyliczamy oczekiwań generatorem biblioteki, którą testujemy.
Pokrywamy rekord wielopolowy, każdy konstruktor wariantu, void, optional
obecne/brakujące, listę pustą/niepustą, referencję między modułami, Unicode,
escapowanie, record i liczby na granicach dopuszczalnego zakresu.
Porównujemy według reguł zgodności z wire.md. Dane nie wymagają serwera Well.

## Wymiana między językami

Zgodność z Drutem weryfikujemy dla rewizji wskazanej w [odniesieniu do formatu](wire.md),
według jej zestawu [przypadków i zasad raportowania](https://github.com/finalclass/drut-spec/blob/0d4b4e1e7ef3d7fffe095bfa9b2d88b564e9da8a/docs/conformance.md).
Adapter testowy mapuje wspólne schematy i oczekiwane wartości na badany target.
Ograniczenia frontendu TOML raportujemy oddzielnie od błędów dekodowania;
poprawny przypadek Drutu niewyrażalny w tym frontendzie nie staje się błędną
wiadomością. Dotychczasowe fixture'y ekstrakcji pozostają testami jej pochodzenia.

Kompilujemy wygenerowane artefakty w izolowanych małych konsumentach bez Well.
Dla wspólnego zestawu fixture'ów każdy język dekoduje te same pliki Wire,
a jego ponownie zakodowany wynik dekodują pozostali konsumenci. Obowiązkowa
para podstawowego testu to OCaml i TypeScript uruchamiany przez Deno;
pełny odbiór czterech generatorów obejmuje również Go i Dart.
Samo przeszukanie tekstu outputu nie dowodzi poprawności generatora.

Wariant Go ma wspólny interfejs i osobny typ każdego przypadku. Konsument Go
tworzy przypadki, rozgałęzia się `type switch` i odczytuje typowane `Value`;
sprawdzamy też, że przypisanie niewłaściwego typu do `Value` jest błędem
kompilacji.

## Odrzucanie błędnych danych

Sprawdzamy nieprawidłowy JSON, złe arności, nieznany tag, zły payload wariantu,
null w polu wymaganym, niecałkowity int, przekroczenie zakresu, NaN/Infinity
na wejściu wartości, błędny element zagnieżdżonej listy oraz duplikaty kluczy
na wejściu tekstowym. Oczekujemy jawnych błędów wskazanych w api.md,
bez domyślnych wartości i bez panic w publicznym dekoderze Go. Publiczne wejścia
kodeka wariantu Go odrzucają `nil` i nieobsługiwane implementacje błędem, nie panic.

## Izolacja i CLI

Sprawdzamy manifesty zależności i kompilację konsumentów: brak frameworka,
kompilatora TOML w runtime oraz zależności od sieci. Kontrakt zawierający
service.rpc generuje dane sygnatur, ale żadnego Proxy lub transportu.
Sprawdzamy deterministyczność dwóch buildów, ścieżki ze spacjami, pusty katalog,
nieznany target, usunięcie nieaktualnego własnego artefaktu, ochronę obcych
plików i zachowanie poprzedniego outputu po błędzie.

## Ślad weryfikacji

Wynik implementacji podaje wykonane komendy, ich kody wyjścia i brakujące
sprawdzenia. Dopuszczalny jest nieukończony raport z konkretną przyczyną;
nie wolno opisywać niewykonanego testu jako zaliczonego.
Pomiar rozmiaru binarki lub wydajności może być informacyjny, ale nie ma
niezmierzonej obietnicy przewagi Wire nad MessagePack.
