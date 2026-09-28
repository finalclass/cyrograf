# Plan testów [test]

## Odbiór produktu

Implementacja dostarcza `make build`, `make check` i `make test`.
`make check` sprawdza typy OCaml i generowanego TS; `make test` wykonuje poniższe
przypadki i testy wygenerowanego kodu. `make test-all` obejmuje ponadto kompilację
i wykonanie fixture'ów Go, Dart, Python, Java, C# i Rust. Brak toolchainu jest oznaczonym blokującym
brakiem weryfikacji, nie sukcesem ani cichym pominięciem testu.
Zależności OCaml są opisane w projekcie Dune/opam; build nie wymaga Well.
Skrypty pomocnicze wykonuje Deno.

Wydanie wymaga także celów `make test-language`, `make test-format`,
`make test-migrate`, `make test-lsp`, `make test-editors`, `make test-drut`,
`make test-ocaml-js`, `make package` i `make test-release`.
`make test-ocaml-js` kompiluje profil `js` przez js_of_ocaml 6.2.0 i wykonuje
wymianę z natywnym OCaml i TS zgodnie z sekcją profilu. `make test-all` obejmuje całą automatyczną
weryfikację poza pakowaniem i testem wypakowanego wydania. Testy protokołu
uruchamiają publiczne `cyrograf lsp`, nie wyłącznie funkcje wewnętrzne.
`make check` sprawdza także kanoniczne formatowanie natywnych przykładów
i fixture'ów oznaczonych jako poprawne/formatted, bez zmiany testowych
przypadków celowo niepoprawnych lub niesformatowanych.

## Kontrakt języka

Na przykładzie z language.md oraz osobnym module wspólnych typów sprawdzamy
lokalne i kwalifikowane referencje, warianty, listy, optional, pusty struct,
znaczenie kolejności pól i deklaracje metod bez kodu ich wywołania.
Przestawienie plików wejściowych nie zmienia artefaktów.
Nieznany typ, cykl, kolizja nazw targetu, malformed RPC, brak of, duplikat,
nieprawidłowy optional, Ctx oraz actor dają przewidziane diagnostyki ze ścieżką.

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
Ograniczenia profilu źródłowego raportujemy oddzielnie od błędów dekodowania;
poprawny przypadek Drutu niewyrażalny w tym frontendzie nie staje się błędną
wiadomością. Dotychczasowe fixture'y ekstrakcji pozostają testami jej pochodzenia.

`test-drut` rozdziela testy publicznego `from_drut` wygenerowanych wiadomości
od testów prywatnego runtime'u dla korzeni prymitywnych, listowych i record.
Zachowuje dostępne pokrycie algorytmów bez wystawiania dodatkowych publicznych
funkcji. Nie dodaje aliasów typów ani generyków do języka, żeby obsłużyć korpus.
Przekazuje oryginalny tekst, bez wcześniejszego parsowania JSON i utraty cyfr
lub duplikatów. Test prywatnej funkcji, syntetycznego opakowania lub walidacji
w adapterze nie jest raportowany jako test publicznego wejścia oryginalnego korzenia.

Wektory `wire_hex` ze złym UTF-8 przechodzą przez stringowe wejście OCaml i Go.
Dla TS, Darta, Pythona, Javy, C# i Rusta są jawnie oznaczone jako
niewyrażalne przez publiczne API tekstowe,
zgodnie z wire.md, bez dodawania `Bytes`. Poprawne bajty można ściśle przekształcić
do tekstu dla testu tych targetów; nie zalicza to ich publicznej walidacji bajtów.
Wektor z tagiem Unicode poza gramatyką może pozostać poza profilem, z ID i powodem.
Dokładne liczby, duplikaty i niepoprawne surogaty dostępne w tekście nie mogą
być wyłączone jako ograniczenie API. `invalid-schemas.json` przechodzi przez
realny kompilator; raport rozróżnia odrzucenie schematu od niewyrażalności.

Wymagane regresje to `1.0000000000000001` w pozycji int, całkowite zapisy
dziesiętne i wykładnicze, granice int, przepełnienie float, niedozwolone
surrogate i ich poprawne pary, złe bajty UTF-8, klucze równe po escape,
komentarze, trailing value oraz jawna polityka BOM z wire.md. Badamy je również
w zagnieżdżonych pozycjach. Oczekiwania pochodzą z normy/korpusu, nie z outputu
testowanego generatora. Encodery odrzucają niedozwolone rodzime wartości,
które API danego języka pozwala skonstruować.

Kompilujemy wygenerowane artefakty w izolowanych małych konsumentach bez Well.
Dla wspólnego zestawu fixture'ów każdy język dekoduje te same pliki Drutu
wyłącznie przez publiczne operacje opisane w api.md, a jego ponownie zakodowany
wynik dekodują pozostali konsumenci we wszystkich 56 kierunkach. Obowiązkowa
para podstawowego testu to OCaml i TypeScript uruchamiany przez Deno;
pełny odbiór obejmuje wszystkie osiem generatorów z api.md.
Samo przeszukanie tekstu outputu nie dowodzi poprawności generatora.

Wariant Go ma wspólny interfejs i osobny typ każdego przypadku. Konsument Go
tworzy przypadki, rozgałęzia się `type switch` i odczytuje typowane `Value`;
sprawdzamy też, że przypisanie niewłaściwego typu do `Value` jest błędem
kompilacji.

## Odrzucanie błędnych danych

Sprawdzamy nieprawidłowy JSON, złe arności, nieznany tag, zły payload wariantu,
null w polu, którego typ go nie dopuszcza, niecałkowity int, przekroczenie zakresu, NaN/Infinity
przekazane do `to_drut`, błędny element zagnieżdżonej listy oraz duplikaty kluczy
na wejściu tekstowym. Oczekujemy jawnych błędów wskazanych w api.md,
bez domyślnych wartości i bez panic w publicznym dekoderze Go. Publiczne wejścia
wariantu Go odrzucają `nil`, interfejs z nil pointerem i nieobsługiwane
implementacje błędem, nie panic.

## Profil OCaml js_of_ocaml i informacja dla adapterów

Profil `js` generuje kod OCaml z `Int` jako `int64`. Sprawdzamy rzeczywistą
kompilację przez js_of_ocaml 6.2.0, a nie samo przeszukanie tekstu. Wygenerowane
biblioteki natywna i `js` kompilują się i wymieniają wiadomości z natywnym
OCaml i TS w obie strony dla wspólnych fixture'ów Drutu.

Przypadki obowiązkowe:

- granice 32-bitowe i `±9007199254740991` w polu Int, także w listach,
  wariantach i referencjach;
- odrzucenie ułamkowego lub wykładniczego tekstu niebędącego dokładną liczbą
  całkowitą, np. `1.0000000000000001`;
- brak obcięcia wartości spoza zakresu `int` i brak zawężenia Drutu do 32 bitów;
- Unicode, `Record`, `optional` obecne/brakujące, `List` i warianty;
- identyczny tekst Drutu dla tego samego schematu i wartości w obu profilach.

Minimalna informacja kompilatora: publiczna projekcja nazw symboli i ścieżek
artefaktów pozwala zbudować adapter poza biblioteką wiadomości. Test negatywny
sprawdza, że konsument nie musi importować prywatnego `Naming`, a publiczne
wejście konwersji pozostaje wyłącznie `to_drut`/`from_drut`. Wybór nazwy
biblioteki danych OCaml pozwala opublikować profil natywny i `js` w jednym
workspace bez kolizji nazw Dune.

Brak js_of_ocaml 6.2.0 jest oznaczonym blokującym brakiem weryfikacji, nie
zielonym pominięciem ani sukcesem na podstawie samych małych liczb.

## Małe API, opcjonalność i nazwy targetów

Izolowany konsument każdego targetu tworzy wiadomości, koduje i dekoduje je
przez dokładnie dwie operacje z api.md. Konsument OCaml używa zainstalowanego
pakietu `cyrograf`; publiczne odwołanie do `Cyrograf.Codec`, `Cyrograf.Wire`
lub dawnego `Contract` nie kompiluje się. Typowane negatywne przykłady
sprawdzają brak dawnych wejść `to_wire`/`encodeName`/`ToWire`/`fromWireBytes`
w odpowiednich targetach. TS eksportuje typ oraz obiekt wiadomości, którego
klucze konwersji to wyłącznie `toDrut` i `fromDrut`; nie wymaga importu kodeka.
Samo usunięcie przykładów z README nie zalicza ograniczenia publicznego API.

Wiadomości z opcjonalnym String/Int/Bool/List/wariantem rozróżniają brak
od obecnego pustego napisu, zera, false i pustej listy. OCaml używa None/Some,
Go pointerów, Dart nullable, a TS opcjonalnych właściwości zgodnie z api.md.
TS po odczycie nie ma własnej właściwości nieobecnego pola; przy kodowaniu
brak i undefined dają ten sam Drut, null jest błędem. Go odróżnia nil pointer
od pointera do pustej listy, w tym nil slice. Sprawdzamy roundtrip w 56 kierunkach
i zgodność z istniejącymi oczekiwanymi tekstami Drutu.

Konsumenci TS są sprawdzani z `strict: true` i `exactOptionalPropertyTypes: true`.
Bezwarunkowe użycie opcjonalnego pola oraz przypisanie null/undefined do
`field?: T` są celowo niepoprawnymi testami kompilacji; poprawne zawężenie
typu przechodzi. Brak wymaganego pola albo zły typ daje błąd `from_drut`,
nie domyślną wartość ani brak. Void i Record sprawdzamy według ich jawnych reguł.

Fixture z polami/metodami snake_case sprawdza wygenerowane nazwy dla wszystkich
targetów, w szczególności owner_id/ownerId/OwnerID, przy niezmiennym deskryptorze
kanonicznym i Drucie. Testujemy kolizje po konwersji, zastrzeżone nazwy typów,
słowa kluczowe targetu i konflikt z członem wygenerowanego API. Błąd jest
wspólny dla check/build/LSP; generowanie błędnego kodu nie jest rozwiązaniem.

## Python, Java, C# i Rust

Każdy nowy target przechodzi publiczny scenariusz: natywny i równoważny
TOML → check/build → osobny projekt poza repo → konstrukcja typowanych
wiadomości → to_drut/from_drut. Wywołania nie potrzebują kompilatora Cyrografu
w runtime, deskryptora, frameworka ani uruchomionego serwera.

Profile z api.md sprawdzamy rzeczywistymi narzędziami:

- Python 3.11: wykonanie oraz przypięty mypy w trybie strict dla publicznych
  modeli i konsumentów; błędny payload/niewłaściwy optional ma błąd typów.
  Python jest targetem produktu; sterowanie testami pozostaje w Deno.
- Java 21: javac z release 21 i uruchomienie konsumenta; pattern matching
  po przypadkach wariantu, typed payload i Optional bez null.
- C#: dotnet build/run dla net10.0, nullable włączone; negatywny konsument
  sprawdza zły payload oraz użycie nullable bez zawężenia jako błąd
  przy warnings-as-errors w tym teście.
- Rust: cargo check/test na zadeklarowanym minimum, konsument jako osobny
  crate; błędny payload lub użycie Option bez rozpakowania nie kompiluje się.
  Testy nie korzystają z unsafe do obchodzenia reprezentacji tekstu.

Pozytywny i negatywny konsument weryfikują granicę małego API, także po
spakowaniu/zainstalowaniu artefaktu. Sprawdzamy brak dodatkowych publicznych
ToValue/FromValue, encode/decode, Bytes, kodeków lub ich przemianowanych
odpowiedników. W Pythonie kontrolujemy __all__, nazwy eksportów i prywatne
prefiksy, bez fikcyjnego zapewnienia prywatności kompilacyjnej.

Wspólny korpus obejmuje wszystkie prymitywy, pustą strukturę, każdy wariant,
również Void i przypadki z tym samym typem payloadu, referencje między
modułami, listy zagnieżdżone i List<Void>, Record i opcjonalne Record.
Opcjonalność obejmuje brak oraz obecne "", 0, false, [], wariant z danymi
i bez nich. Niezależne oczekiwania Drutu są źródłem porównań, nie wynik
innego nowego generatora. Każdy producent i odbiorca sprawdza wartości
typowanych pól, nie tylko ponowne kodowanie lub brak wyjątku.

Python odrzuca bool w miejscu Int/Float i niejawne konwersje złych typów.
Java odrzuca null zamiast Optional oraz wymaganej referencji.
C# sprawdza trwałość zwróconego JsonElement i odrzuca Undefined oraz
niedozwolone null. Rust zwraca Error zamiast panic. Każdy target przechodzi
ten sam profil ścisłych liczb, duplikatów, BOM, trailing i Unicode z wire.md,
również wewnątrz referencji/list/Record. Raport korpusu rozróżnia publiczną
konwersję, runtime i przypadki niewyrażalne per ID/target.

Testy nazw dla każdego nowego targetu obejmują snake_case i konwencję
docelową, słowa kluczowe, kolizje modułów, typów i członów generowanego API.
Dla kolizji właściwej nowemu targetowi check/build zgłaszają błąd bez publikacji,
a LSP zgłasza go dla niezapisanego bufora i czyści po poprawieniu.
Jawne wybranie innych targetów nie zgłasza kolizji specyficznej dla wykluczonego.

Macierz wymiany jest generowana z pełnej listy targetów. Końcowy odbiór wymaga
dokładnie 56 różnych par nadawca–odbiorca (osiem razy siedem) zarówno dla
głównego korpusu wiadomości, jak i korpusu optional; brak pary lub targetu
jest błędem testu. Każdy target dodatkowo ma własny roundtrip i oczekiwane
wektory. Nowe kontrole są w test-all i CI, bez ręcznej listy wyjątków.
Pełny odbiór zachowuje kontrole czterech istniejących targetów.

CLI check/build/help, biblioteczny typ target, domyślny wybór i wybór podzbioru,
manifest oraz usuwanie własnych nieaktualnych plików obejmują nowe targety.
Native/TOML/migrate pozostawiają identyczne znaczenie dla całej ósemki.
Test-release generuje osiem projektów wypakowaną binarką, a następnie
kompiluje/uruchamia małego konsumenta każdego z nowych targetów.
Samo generowanie nie może wymagać ich toolchainów na PATH; toolchainy
są potrzebne dopiero do kompilacji/uruchamiania wygenerowanego kodu.

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

## Natywny język i wspólna analiza

`test-language`: przykłady language.md i toml.md dają równoważny schemat
i artefakty wszystkich targetów. Osobne projekty zawierają mieszane frontendy,
referencje do późniejszych deklaracji, zagnieżdżone listy, kontekstowe słowa
jako nazwy pól, wariant void, średniki, CRLF, BOM i komentarze Unicode.
Zmiana kolejności plików nie zmienia wyniku, zmiana kolejności pól ma
przewidziany wpływ na schemat i Wire. Dwie wersje modułu są odrzucane.

Niepoprawne UTF-8, niezamknięte nawiasy, brak typu, nieznany typ, optional
w złej pozycji, duplikat, cykl i zła referencja dają wskazane błędy i zakresy.
Sprawdzamy EOF, błąd po znaku spoza BMP w komentarzu, kilka niezależnych
błędów i użyteczny indeks deklaracji po odzyskaniu parsowania. Nie może powstać
poprawny `Schema` dla projektu z błędami. Ten sam błąd z CLI i analizy dla LSP
ma ten sam kod i ścieżkę. Kolizje targetu sprawdza także `check`.

Język akceptuje `String`, `List<String>`, `List<List<Common.Thing>>`,
`note?: String`, `items?: List<String>` i nazwy snake_case. Odrzuca dawne
małe litery prymitywów, `[T]`, `T?`, wadliwe snake_case, `List<>`,
`List<A, B>`, `Box<T>`, definicje generyków, Optional/Option bez deklaracji
oraz opcjonalne Void. Błędy mają właściwe zakresy. TOML zachowuje własną
pisownię i daje ten sam schemat oraz artefakty co natywny odpowiednik.

## Formatowanie

`test-format`: utrwalone oczekiwane teksty według tooling.md obejmują komentarze
osobne/końcowe, komentarze wewnątrz typów, puste struktury, średniki, CRLF,
BOM, jawne void, długie nazwy i zagnieżdżone listy. Dwa formatowania dają ten
sam tekst. Formatowanie poprawnego projektu zachowuje jego schemat i Wire.
Brak referencji nie blokuje formatera; błąd składni go blokuje.

Fixture'y nowej notacji zawierają `name?: List<List<Type>>` i komentarze
wewnątrz `< >`. Oczekiwany układ, idempotencja i zachowanie semantyki
obowiązują dla CLI oraz formatowania LSP.

Proces CLI bada zapis domyślny, `--check`, stdin, ścieżki ze spacjami i
zaczynające się od `-` po `--`. Zestaw z jednym błędnym plikiem nie zmienia
żadnego źródła. Podmieniony od odczytu plik nie jest nadpisywany.
W testach granicy zastępuje się WorkspaceAccess kontrolowanym zasobem,
aby deterministycznie wywołać konflikt i awarię przygotowania zapisu.

## Migracja

`test-migrate`: projekt z TOML, native i referencjami między nimi przechodzi
konwersję do odrębnego katalogu. Schemat przed/po oraz wygenerowane artefakty
są równoważne, a kolejność pól i tagi pozostają identyczne. Uwzględniamy
komentarze i `#` wewnątrz stringa TOML, puste moduły, optional/list/void/RPC.
Źródła nie zmieniają bajtów. Drugie wykonanie daje ten sam wynik.
Niepoprawny projekt, podwójny moduł, obcy plik i wynik nachodzący na źródła
powodują błąd bez częściowej publikacji.

## Protokół i praca edytorowa

`test-lsp`: sterownik Deno uruchamia binarkę i wymienia rzeczywiste ramki.
Bada inicjalizację, capabilities, shutdown/exit/EOF, nieznane żądania,
fragmentację ramek, kilka ramek naraz i brak obcych bajtów na stdout.

W projekcie dwóch modułów wysyła otwarcie, niezapisany błąd, poprawienie,
zmianę zależnego typu, nowy plik i zamknięcie. Diagnostyka dotyczy bufora,
odświeża zależności i jest czyszczona. Starsze wersje nie cofają wyniku.
Zmiana/zniknięcie zamkniętego pliku jest widoczna po następnym zdarzeniu.
Badamy niezależność dwóch katalogów i ścieżki URI ze spacjami.

Zakresy UTF-16 są sprawdzane na CRLF i znakach spoza BMP. Formatowanie LSP
po zastosowaniu edycji daje identyczny tekst jak CLI i nie zapisuje dysku.
Hover, definicja, symbole i completion działają dla lokalnego i kwalifikowanego
typu oraz sensownie kończą się na niekompletnym dokumencie. Składnia z błędem
nie daje edycji formatera. Powtórzone sesje nie dziedziczą overlay poprzednika.

Completion i hover pokazują aktualne typy; definicja i completion działają
wewnątrz `List<Common.Type>`, również w niekompletnym argumencie. Testy
edytorów oraz Markdowna używają wielkich liter prymitywów, List i `field?: T`.
Test pliku blokady Emacsa zachowuje pokrycie podczas rzeczywistej sesji Eglota.

## Integracje edytorów

`test-editors`: wspólny zestaw natywnych tekstów sprawdza rozpoznanie języka,
kolorowanie tokenów/komentarzy i konfigurację uruchamiania LSP. Emacs, Vim i Neovim
uruchamiają swoje pakiety w trybie batch/headless; VS Code sprawdza pakowalną
integrację w Extension Host; TextMate/konfiguracja LSP4IJ przechodzą walidację
artefaktów. Polecenie programu ze spacjami nie jest błędnie dzielone przez shell.

Odbiór wydania dodatkowo wymaga rzeczywistego smoke testu w każdym z pięciu
edytorów według editors.md, automatycznego albo ręcznego. Raport podaje wersję,
wykonane czynności i dowód (log lub obraz). Brak środowiska oznacza BLOCKED;
sama walidacja konfiguracji JetBrains nie zalicza jego smoke testu.

Scenariusz z editors.md wykonuje faktyczny klient danego edytora: uruchamia
publiczne `cyrograf lsp`, dostaje diagnostykę po niezapisanej zmianie na
nieznany typ, po naprawie ją usuwa, przechodzi do definicji w drugim module
i formatuje bufor do wyniku zgodnego z CLI. Bezpośrednia wymiana ramek
test-lsp nie zastępuje tej kontroli. Ładowanie pakietu bez otwarcia dokumentu
nie uruchamia serwera. Brak wymaganego klienta lub narzędzia daje niezerowy
kod także w pomocniczym procesie testowym, nie tylko napis BLOCKED.

### Markdown

`test-editors` obejmuje rzeczywiste kolorowanie bloków `cyrograf` w zakresach
gwarantowanych w editors.md: font-lock Emacsa, grupy syntax Vima/Neovima,
tokenizację Markdowna w VS Code i wynik podglądu przez dostarczony adapter.
Obecność pliku gramatyki lub poprawny JSON konfiguracji nie wystarcza.

Fixture'y zawierają deklarację, typ, pole, wariant, RPC i komentarz Unicode,
kilka bloków rozdzielonych prozą, blok niekompletnego kodu, blok innego języka
i blok bez nazwy. Sprawdzamy powrót do składni Markdowna po ogrodzeniu,
dłuższe ogrodzenie z krótszym ciągiem backticków wewnątrz i brak uruchomienia
LSP przez samo kolorowanie. Test podglądu VS Code bada HTML i poprawne
escape znaków `<`, `>` i `&` w komentarzu; tekst kodu nie staje się aktywnym
HTML. Dokumentowana konfiguracja działa w czystym profilu bez ustawień autora.
Przykład Markdowna i potrzebne zasoby trafiają do pakietów edytorowych.

## Publikacja artefaktów i instalacja

Badamy niepoprawny manifest, ścieżkę absolutną, `..`, symlink i nakładanie się
źródła z outputem przez inną pisownię ścieżki. Awaria przygotowania w Accessie
nie niszczy poprzedniego outputu. Sukces usuwa wyłącznie stare własne pliki.
Te przypadki wchodzą do podstawowego `make test`.

`test-release` rozpakowuje wynik `make package`, sprawdza sumy i uruchamia
binarkę poza repo: brak argumentów, wszystkie pomoce, wersja, check, build,
format/check/stdin, migrate i minimalna sesja LSP. Ze źródeł uruchamia prawdziwe
`make install` do tymczasowego prefiksu ze spacjami, bez zastępowania tego
kopią drzewa `_build/install`. Sprawdza także staging przez `DESTDIR`, ponowną
instalację, zachowanie obcego pliku w prefiksie i niezerowy kod przy błędzie
zapisu. Potwierdza domyślny prefiks bez instalacji do rzeczywistego katalogu
użytkownika. Zainstalowana binarka działa poza checkoutem, bez odwołań do
niego lub `_build`; test kompiluje i uruchamia osobnego konsumenta OCaml
z bibliotekami zainstalowanymi przez ten sam cel. Instalacja nie uruchamia
testów pozostałych języków ani edytorów. Archiwum
źródeł buduje się bez cache specyficznego dla maszyny autora. Manifest pakowania
nie obejmuje `.git`, `.local`, logów ani danych prywatnych.

CI wykonuje `make build`, `make check`, `make test-all` i `make test-release`
z wymaganymi narzędziami. Smoke edytorów, którego nie wykonano w CI, musi mieć
osobny rzeczywisty wynik przed uznaniem wydania za gotowe. Raport nie zastępuje
braku narzędzia sukcesem i nie nadaje etykiety pełnej zgodności częściowemu
korpusowi. Samo wydanie publiczne nie jest testem ani częścią tego zlecenia.
