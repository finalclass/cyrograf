# Architektura [impl]

## Granica systemu

Cyrograf opisuje wiadomości i sygnatury operacji, sprawdza kontrakty oraz
wytwarza typy i kodeki. Jeden program `cyrograf` obsługuje terminal i protokół
edytora. Biblioteka wykonawcza koduje dane niezależnie od narzędzi autora.
Cyrograf nie wykonuje operacji zadeklarowanych w kontrakcie.

To biblioteki i moduły jednego programu. Granice wynikają ze zmienności;
nie oznaczają osobnych procesów, mikroserwisów ani ładowanych pluginów.

## Zmienności, ryzyko i właściciele

| Co może się zmienić i dlaczego | Właściciel | Ryzyko powstrzymane na granicy |
|---|---|---|
| Notacja kontraktu: własna składnia, zgodność z wejściem TOML, przyszła rewizja gramatyki. | `Analysis.Syntax`, z frontendami `Native` i `Toml` | Generatory i reguły typów nie czytają tokenów ani tabel Otoml. |
| Dozwolone konstrukcje typów, wiązanie nazw i reguły poprawności kontraktu. | `Analysis.Semantics` | CLI i edytor nie implementują odrębnych walidatorów. |
| Zasady układu źródła, zachowania komentarzy i drukowania deklaracji. | `Layout` | Zmiana stylu nie zmienia schematu, tagów ani kodeków. |
| Idiomy, nazwy i organizacja kodu w językach docelowych. | `Emission`, strategie targetów z api.md | Dodanie targetu nie zmienia parsera ani protokołu edytora. |
| Reprezentacja danych i rygor walidacji kodowania. | prywatny runtime Drutu, odwzorowanie formatu w `Emission` | Drut nie narzuca składni plików źródłowych ani transportu aplikacji. |
| Reprezentacja `Int` w OCaml: natywna 64-bitowa albo js_of_ocaml (32-bitowy `int`). | profil OCaml w `Emission` | Drut, reguły języka ani API konwersji nie zależą od szerokości `int`. |
| Pochodzenie i aktualność źródeł: pliki, niezapisane bufory, wersje dokumentów. | `WorkspaceAccess` | Analiza operuje na jednym niezmiennym obrazie źródeł; nie czyta dysku w trakcie walidacji. |
| Własność i sposób publikowania zbioru wygenerowanych plików. | `ArtifactAccess` | Generatory nie usuwają plików i nie znają manifestu poprzedniego builda. |
| Kolejność analizy, przekształcenia, sprawdzenia i publikacji wyniku. | `Tooling` | Procedury nie są kopiowane między komendami i obsługą edytora. |
| Interakcja z terminalem, wersja protokołu edytora, API edytorów i rendererów Markdown. | adaptery `Cli`, `Lsp`, pakiety `editors/` | Protokół i prezentacja nie przeciekają do modelu kontraktu. |
| Sposób instalowania i budowania wydania na danej platformie. | konfiguracja dystrybucji i CI | Pakowanie nie staje się usługą runtime ani warunkiem użycia kodeka. |

Nazwy pól i liczba wiadomości są danymi, nie powodem tworzenia kolejnych
modułów. Poszczególne komendy również nie wyznaczają granic architektury.
`Analysis` jest jedną czystą aktywnością z dwiema wewnętrznymi granicami:
składni i semantyki. Sekwencja parse/resolve/validate jest jej detalem; żadna
strategia składni nie wywołuje generatora, zapisu pliku ani klienta LSP.

## Modele przekazywane przez granice

- `Syntax.Document`: deklaracje, tokeny i komentarze wraz z pozycjami; może
  opisywać dokument niekompletny. Drzewo nie zależy od Otoml ani JSON-RPC.
- `Analysis.Result`: diagnostyka, indeks symboli i referencji, dokumenty
  składniowe; poprawny `Schema` jest dostępny wyłącznie bez błędów.
- `Cyrograf.Schema`: znaczenie kontraktu, kwalifikowane nazwy, uporządkowane
  pola, warianty i sygnatury; bez komentarzy, URI edytora i zasobów procesu.
- `Workspace.Snapshot`: niezmienne teksty źródeł i ich rewizje.
- `Artifact`: względna ścieżka oraz gotowe bajty wyniku, bez operacji I/O.

Kontrakty tych granic opisuje [tooling.md](tooling.md). Model danych runtime
pozostaje w [api.md](api.md). Nie używamy samego `Schema` do formatowania,
ponieważ utraciłby komentarze i układ deklaracji.

## Kompozycja i zależności

```static-architecture
Cyrograf tooling

Who
- [Cli] [Lsp] [Klient biblioteczny]

What
- [Tooling]

How
- [Analysis] [Layout] [Emission]

How-to-access -> Where
- [WorkspaceAccess]->(Źródła i bufory)
- [ArtifactAccess]->(Wynik generowania)
```

`Tooling` sekwencjonuje aktywności i dostęp do zasobów. `Analysis`, `Layout`
i `Emission` nie wołają siebie nawzajem; przekazanie wyników należy do
`Tooling`. `Layout` otrzymuje dokument składniowy albo deklaracje do wydrukowania,
`Emission` wyłącznie poprawny schemat. Accessy nie wołają siebie wzajemnie.
Adaptery mapują argumenty, protokół i prezentację; nie określają reguł języka.

Osadzanie kolorowanego kodu w Markdownie należy do adapterów `editors/`.
Używa ich reguł tokenów, bez nowego frontendu kompilatora ani analizy Markdowna
przez `Tooling`. Zmiana renderera nie zmienia schematu, kodeka ani LSP.

Publiczne czyste funkcje `Cyrograf_compiler` udostępniają kompozycję tych samych
aktywnych modułów na dostarczonych tekstach, bez I/O. Nie są drugim walidatorem.
Rozdzielenie bibliotek Dune nie wymusza dodawania pośrednich wywołań bez logiki.

```call-chain
Sprawdzenie kontraktów

[Cli lub Lsp]
  -> [Tooling]
    -> [WorkspaceAccess]
      -> (Źródła i bufory)
    -> [Analysis]
    -> [Emission]
```

Ostatnia aktywność sprawdza wyłącznie zgodność z wybranymi targetami, m.in.
kolizje nazw; nie emituje plików. Diagnostyka języka pochodzi z `Analysis`.

```call-chain
Wygenerowanie typów i kodeków

[Cli]
  -> [Tooling]
    -> [WorkspaceAccess]
      -> (Źródła i bufory)
    -> [Analysis]
    -> [Emission]
    -> [ArtifactAccess]
      -> (Wynik generowania)
```

```call-chain
Formatowanie pliku lub bufora

[Cli lub Lsp]
  -> [Tooling]
    -> [WorkspaceAccess]
      -> (Źródła i bufory)
    -> [Analysis]
    -> [Layout]
    -> [WorkspaceAccess]
      -> (Źródła i bufory)
```

W CLI ostatnie wywołanie może bezpiecznie zapisać pliki; w LSP wynik to edycja
przekazana klientowi, bez zapisu na dysku. Błędy wiązania nazw nie blokują
formatowania poprawnego składniowo dokumentu.

```call-chain
Migracja źródeł TOML

[Cli]
  -> [Tooling]
    -> [WorkspaceAccess]
      -> (Źródła i bufory)
    -> [Analysis]
    -> [Layout]
    -> [Analysis]
    -> [ArtifactAccess]
      -> (Przekonwertowane źródła)
```

Przed publikacją porównuje się znaczenie wejścia i ponownie odczytanego wyjścia.
Powtórne węzły w tych drzewach oznaczają użycie tego samego komponentu;
procedura i warunki zakończenia należą do [tooling.md](tooling.md).

```call-chain
Kodowanie danych w aplikacji

[Aplikacja lub adapter]
  -> [Wygenerowany kodek]
    -> [Prywatny runtime Drutu danego języka]
```

## Biblioteki i izolacja

- `cyrograf`, moduł `Cyrograf`: diagnostyka i wspólny model schematu;
  zależności runtime ograniczone do OCaml i Yojson. Wygenerowane moduły
  wiadomości wystawiają konwersję, prywatny runtime realizuje reguły Drutu.
  Jego helpery nie są publicznymi `Cyrograf.Codec` ani `Cyrograf.Wire`.
- `cyrograf.compiler`, moduł `Cyrograf_compiler`: czysta analiza, układ źródła
  i generowanie; Otoml pozostaje wyłącznie zależnością narzędzia.
- `cyrograf.tooling`: koordynacja pracy na źródłach i implementacje Accessów;
  zależy od kompilatora i zasobów systemu operacyjnego.
- `cyrograf.lsp`: adapter protokołu; zależy od tooling, nie odwrotnie.
- `cyrograf`: jedyny publiczny program, wybiera adapter CLI lub LSP.

Nazwy wewnętrznych plików są detalem. Każda wskazana granica ma `.mli` albo
równie jednoznaczny prywatny kontrakt; nie tworzymy pakietu Dune per mała funkcja.
Komponenty niższe nie zależą od `Cli`, `Lsp` ani bibliotek konkretnego edytora.
Wygenerowany konsument nie linkuje parsera, formatera ani serwera językowego.
Reguły reprezentacji targetu pozostają w strategii tego targetu, nie w `Syntax`.

## Sprawdzenie podziału przez zmianę

- Zastąpienie TOML własną składnią dotyka frontendu, nie reguł kodeków.
- Zmiana wcięcia dotyka `Layout` i oczekiwań formatowania, nie semantyki.
- Przejście LSP z pełnych dokumentów na przyrostowe zmiany dotyka adaptera
  i dostępu do wersji źródeł, nie walidatora typów.
- Nowy target dotyka `Emission` i jego testów, nie klientów edytora.
- Zmiana reguł publikacji artefaktów dotyka `ArtifactAccess`, nie generatorów.

Nowy rodzaj typu może wymagać jawnego rozszerzenia wspólnego modelu i wszystkich
jego interpretacji; architektura nie obiecuje wyeliminowania takiej zależności.

## Integracje poza granicą

Well i Cell będą klientami schematu i wygenerowanych typów; ich adaptery mogą
wiązać konteksty, generować Proxy i rejestrować wykonanie. Wydanie Cyrografu
nie implementuje tych adapterów, innych kodowań, aktorów ani transportu RPC.
