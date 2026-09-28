# Architektura [impl]

## Granica systemu

Biblioteka opisuje wiadomości, opisuje sygnatury operacji i zamienia poprawne
wiadomości na reprezentację Wire oraz z powrotem. Kompilator wytwarza kod
dla kilku języków. Biblioteka nie wykonuje operacji opisanych kontraktem.

Rozdział jest oparty na zmiennościach. To projekt infrastrukturalnej biblioteki;
poniższe moduły są granicami wewnątrz niej, nie zestawem usług sieciowych.

## Zmienności i ich właściciele

| Zmienność | Granica | Uzasadnienie |
|---|---|---|
| Składnia deklarowania kontraktu | frontend TOML kompilatora | Zmiana języka wejściowego nie zmienia kodeków już wygenerowanego programu. |
| Zapis danych w przesyłanej wiadomości | backend Wire i interfejs Codec | Dodanie kodowania nie zmienia znaczenia deklarowanych typów. |
| Odwzorowanie typów na język docelowy | generatory języków | Reguły nazw, modułów i wariantów są różne dla OCaml, TS, Go i Dart. |
| Sposób dostarczenia źródeł i zapisania artefaktów | klient CLI lub klient biblioteczny | Kompilator może otrzymać tekst w pamięci bez znajomości systemu plików. |
| Integracja z usługą, komórką lub transportem | adapter poza biblioteką | Well i Cell mają różne modele wywołania, kontekstów i wykonania. |

`Schema` jest wspólnym modelem kontraktu. Zachowuje kwalifikowane nazwy,
kolejność pól, warianty i deklaratywne sygnatury. Nie zawiera adresów endpointów,
sesji, kodu wykonującego operacje ani referencji do Well lub Cell.

## Pakiety i zależności

- `contract`: moduł `Contract`, model schematu, diagnostyka, abstrakcja Codec
  i początkowy kodek Wire. Zależności wykonawcze ograniczone do OCaml i Yojson.
- `contract.compiler`: moduł `Contract_compiler`, frontend TOML oraz generatory;
  zależy od `contract` i Otoml. Użytkownik wygenerowanych wiadomości nie musi
  instalować ani linkować kompilatora TOML.
- `cyrograf` jako program CLI: klient `contract.compiler`; nie uruchamia serwera.

Rozdział pakietów realizuje się oddzielnymi bibliotekami Dune. Parser i generator
nie mogą zostać przypadkowo dołączone do aplikacji, która tylko koduje wiadomości.
Publiczny model Schema nie zależy od Yojson. Typ `Contract.Wire.value` może być
jawnym aliasem `Yojson.Safe.t`; ta zależność należy wyłącznie do powierzchni Wire.
Publiczny `Contract.Codec` operuje na niezmiennych bajtach reprezentowanych przez
OCaml `string`, więc późniejszy kodek nie musi przechodzić przez JSON.

## Kompozycja

```call-chain
Wygenerowanie typów i kodeków

[Klient CLI lub build]
  -> [Contract_compiler]
    -> [Frontend TOML]
    -> [Generator wybranego języka i kodowania]
```

```call-chain
Kodowanie i dekodowanie w aplikacji

[Aplikacja lub adapter]
  -> [Wygenerowany kodek wiadomości]
    -> [Contract.Wire]
```

Są to struktury wywołań biblioteki; nie klasyfikują modułów jako Managerów
i Engine'ów. Nie dodajemy takich usług tylko w celu odtworzenia nazw warstw.
Generator otrzymuje zweryfikowany Schema, nigdy surowe tabele Otoml.
Frontend nie wywołuje generatorów. Żaden element biblioteki nie woła adaptera.

Dodanie backendu innego formatu jest przyszłym rozszerzeniem na tej granicy,
nie wymaganiem implementacji wielu formatów ani rejestru pluginów w wersji 1.
Każdy przyszły backend musi jawnie zdefiniować odwzorowanie typów; zgodność
z dowolnym formatem nie jest obiecywana samym istnieniem interfejsu Codec.

## Adaptery

Przyszły adapter Well będzie klientem modelu kontraktu i wygenerowanych typów.
To on może generować Proxy, wiązać `Well.rpc_ctx`, tworzyć `Well.Service.spec`
oraz rejestrować transport. Analogiczny adapter Cell będzie właścicielem
accepts/emits, deskryptorów aktorów i powiązania z runtime'em.
Pierwsze wydanie nie implementuje tych adapterów i nie zmienia Well.
