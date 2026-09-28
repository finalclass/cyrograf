# Kontekst wyboru Wire

Notatka z 2026-09-27; nie stanowi dodatkowego zakresu implementacji.

## Doświadczenia z gRPC

Autorzy OCaml-owego stosu Dialo opisali w kwietniu 2026 problemy z gRPC nad h2,
konieczność napisania własnego HTTP/2 i przebudowania gRPC, a ostatecznie wybór
Rusta, aby ograniczyć koszt utrzymywania stosu. To relacja bezpośrednich autorów,
potwierdzająca istnienie podobnych doświadczeń w OCaml; nie dowód, że każda
implementacja gRPC jest wadliwa.
[Źródło](https://discuss.ocaml.org/t/seeking-maintainers-for-our-ocaml-sip-server-grpc-and-http-2-libraries/18000)

Deno ma udokumentowaną historię problemów gRPC/node:http2, m.in. odpowiedzi
niedostarczanych do aplikacji. Sprawdzone zgłoszenia #23246 i #23714 są obecnie
zamknięte. Nie ustalono, czy chodzi o ten sam błąd, którego doświadczył użytkownik.
[Błąd #23246](https://github.com/denoland/deno/issues/23246),
[śledzenie wsparcia #23714](https://github.com/denoland/deno/issues/23714).

## Protobuf: zastrzeżenia i granice wniosków

Protobuf ma `oneof`, umożliwiające wybór jednego payloadu; nie jest więc formatem
całkowicie pozbawionym odpowiednika sumy typów. Semantyka dopuszcza brak wyboru,
ma ograniczenia pól repeated/map i szczególne reguły ewolucji. To różni się od
wygody zwykłego, zamkniętego wariantu OCaml.
[Dokumentacja oneof](https://protobuf.dev/programming-guides/proto3/#oneof)

Protobuf powstawał od 2001 roku; jego projektu nie można historycznie wywodzić
z Go. Protobuf określa kodowanie, natomiast gRPC dodaje protokół wywołania.
Odrzucenie obu jest decyzją projektu, nie wymaga uznania ich za tę samą technologię.
[Historia Protobuf](https://protobuf.dev/history/)

Autor Cap'n Proto opisuje koszt kodu inicjalizacji oraz wielkości generowanego
kodu i runtime'u implementacji C++ Protobuf. Jest to techniczne uzasadnienie
alternatywy, ale pochodzi od autora konkurencyjnego rozwiązania i nie rozstrzyga
rozmiaru konkretnej binarki OCaml. Tego tutaj nie zmierzono.
[Porównanie implementacji C++](https://capnproto.org/cxx.html)

## Wire i MessagePack

Wire pomija nazwy zadeklarowanych pól, co oszczędza miejsce wobec obiektowego
JSON-a. MessagePack również potrafi kodować tablice: `[1,2,3]` to 7 bajtów
zwartego tekstu JSON, a ta sama tablica to 4 bajty MessagePack
(`93 01 02 03`). Jest to obliczenie z reguł formatu, nie benchmark aplikacji.
Przewaga Wire nad MessagePack kodującym obiekty z kluczami może wynikać
z innego modelu danych; nie uzasadnia przewagi nad tym samym modelem tablicowym.
[Specyfikacja MessagePack](https://github.com/msgpack/msgpack/blob/master/spec.md)

Decyzja projektu pozostaje: początkowo własny TOML, warianty i tekstowy Wire,
mały runtime oraz możliwość późniejszego dodania innych kodeków.
