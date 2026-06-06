# E2E: Flow powiadomień o aktualizacji

Użyj tej checklisty, gdy implementacja będzie gotowa do finalnej ręcznej walidacji E2E.

## Przygotowanie

- Zbuduj lub zainstaluj starszą wersję PasswordMonitor niż release używany w teście.
- Potwierdź, że uprawnienie do powiadomień jest świeżo niewybrane albo celowo włączone dla PasswordMonitor.
- Potwierdź, że helper login item jest włączony w Ustawieniach systemowych.
- Przed każdym scenariuszem z cooldownami zresetuj albo zapisz stan współdzielonych ustawień aktualizacji.
- Przygotuj dwa podpisane manifesty release: jeden z `urgency: "normal"` i jeden z `urgency: "critical"`.

## Zwykła Aktualizacja

- Uruchom starszą aplikację i potwierdź, że automatyczny check wykrywa nowszy GitHub Release.
- Sprawdź, czy dla dostępnej aktualizacji pojawia się zwykłe powiadomienie macOS.
- Sprawdź, czy każde widoczne okno aplikacji pokazuje subtelny badge aktualizacji bez nachodzenia elementów UI: popover menu bar, Ustawienia, Logi, O aplikacji i okno zmiany hasła.
- Kliknij badge i potwierdź, że bezpośrednio startuje zweryfikowany flow aktualizacji.
- Kliknij akcję albo treść powiadomienia macOS i potwierdź, że bezpośrednio startuje zweryfikowany flow aktualizacji.
- Potwierdź, że powtarzane kliknięcia badge'a albo powiadomienia nie uruchamiają duplikatów pobierania ani duplikatów flow instalacji.
- Użyj `Przypomnij później` i sprawdź, czy zwykłe przypomnienia o aktualizacji są wyciszone na 7 dni.
- Potwierdź, że okno O aplikacji nadal obsługuje ręczny check, pobranie, weryfikację, instalację i ponowne uruchomienie.

## Krytyczna Aktualizacja

- Opublikuj albo skieruj aplikację na podpisany manifest z `urgency: "critical"`.
- Uruchom starszą aplikację i potwierdź, że pojawia się time-sensitive notification macOS.
- Sprawdź, czy zwykłe widoki aplikacji są zablokowane stałą treścią o krytycznej aktualizacji do czasu rozpoczęcia albo zakończenia instalacji.
- Sprawdź, czy ścieżka O aplikacji / aktualizacja pozostaje dostępna.
- Sprawdź, czy powiadomienia o wygasaniu hasła są wstrzymane, gdy krytyczna aktualizacja czeka na instalację.
- Potwierdź, że `Przypomnij później` nie ukrywa ani nie degraduje krytycznego blockera.
- Kliknij akcję blockera i potwierdź, że bezpośrednio startuje zweryfikowany flow aktualizacji.
- Zasymuluj nieudaną aktualizację i potwierdź, że krytyczny blocker zostaje, błąd jest widoczny, a ponowienie jest dostępne.
- Dokończ instalację i ponowne uruchomienie, a potem potwierdź, że stan krytyczny znika i powiadomienia o wygasaniu hasła wracają.

## Helper, Cooldowny I Błędy

- Uruchom aplikację główną i helper w krótkim odstępie czasu, a potem potwierdź, że w ramach in-flight TTL tylko jeden proces przejmuje automatyczny check GitHub.
- Wywołaj aktywację aplikacji, otwarcie menu, wake i start helpera; potwierdź, że udane checki respektują tygodniowy success cooldown.
- Wymuś błąd sieci albo GitHub w tle i potwierdź, że błąd jest widoczny w Ustawieniach / O aplikacji.
- Potwierdź, że automatyczne ponowienia po błędzie respektują godzinny failure cooldown.
- Potwierdź, że świeży podpisany kandydat manifestu jest używany ponownie przy natychmiastowej instalacji.
- Potwierdź, że przestarzały kandydat starszy niż 30 minut jest odświeżany przed instalacją.

## Regresja

- Potwierdź, że alerty wygasania hasła, drzemka, quiet hours i ręczne checki hasła działają jak wcześniej, gdy nie ma oczekującej krytycznej aktualizacji aplikacji.
- Potwierdź, że odmowa uprawnienia do powiadomień aktualizacji nie ukrywa ścieżki przez in-app badge.
- Sprawdź polskie i angielskie teksty dla zwykłej aktualizacji, krytycznej aktualizacji, wstrzymanych powiadomień, błędów i akcji aktualizacji.
- Sprawdź renderowanie badge'y i blockerów w motywie jasnym, ciemnym i auto.
- Sprawdź, czy etykiety VoiceOver i fokus klawiatury docierają do akcji aktualizacji.
