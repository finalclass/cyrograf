# Zatwierdzone decyzje języka i API

Użytkownik zatwierdził małe API Drutu, nazewnictwo Cyrograf, wielkie litery
w nazwach typów, zapis `List<T>` oraz opcjonalność przez `?` przy nazwie pola.
Polecenie obejmuje specyfikację i zlecenie implementacji operatorowi
`cyrograf:mechanik`.

Wiążące reguły są zapisane w odpowiednich kontraktach:

- [language.md](language.md): `String`, `List<String>`, `note?: String`,
  `items?: List<String>`, nazwy pól i metod snake_case oraz brak generyków
  użytkownika w tym wydaniu.
- [api.md](api.md): tylko `to_drut`/`from_drut` w konwencji targetu,
  publiczne nazwy Cyrograf i reprezentacja opcjonalnych pól w językach docelowych.
- [wire.md](wire.md): zachowany format Drutu i granice publicznego API tekstowego.
- [stp.md](stp.md): odbiór zmian, testy typów, nieobecnych eksportów,
  opcjonalności i wymiany między językami.

Ta notatka wskazuje zatwierdzone kontrakty; nie definiuje dodatkowych API
ani wyjątków. Opcjonalność nie jest już decyzją otwartą.
