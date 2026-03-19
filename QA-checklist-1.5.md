# Lista kontrolna QA PasswordMonitor 1.5.2

Build under test: 1.5.2
Data: 2026-03-11

## 1. Helper w tle
- [ ] Włącz uruchamianie przy logowaniu/helper w Ustawieniach.
- [ ] Zamknij całkowicie `PasswordMonitor.app`.
- [ ] Wyloguj się i zaloguj ponownie, potwierdź automatyczny start helpera.
- [ ] Potwierdź, że refresh helpera działa przy uruchomieniu.
- [ ] Potwierdź odświeżanie co 60 minut.
- [ ] Potwierdź odświeżanie w ustawionym czasie powiadomienia.
- [ ] Potwierdź odświeżanie po uśpieniu/przebudzeniu.
- [ ] Potwierdź, że alert może pojawić się, gdy główna aplikacja jest zamknięta.

## 2. Próg ostrzeżenia
- [ ] Ustaw próg ostrzeżenia na 7 dni.
- [ ] Zasymuluj 28 dni do wygaśnięcia -> brak blokującego alertu.
- [ ] Zasymuluj 8 dni do wygaśnięcia -> brak blokującego alertu.
- [ ] Zasymuluj 7 dni do wygaśnięcia -> alert blokujący się pojawia.
- [ ] Zasymuluj mniej niż 24 godziny -> alert się pojawia, snooze jest wyłączone.

## 3. Spójność menu bar / alertu
- [ ] Otwórz widok menu bar i zanotuj liczbę dni pozostałych do wygaśnięcia.
- [ ] Wywołaj alert dla tego samego stanu konta.
- [ ] Potwierdź, że menu bar i alert używają tej samej logiki dnia pozostałego.
- [ ] Potwierdź, że dane z cache/offline pokazują ten sam stan co alert.

## 4. Godziny ciszy
- [ ] Sprawdź domyślne godziny ciszy `18:01`–`05:59`.
- [ ] Zmień godziny ciszy w Ustawieniach i zapisz.
- [ ] Potwierdź, że helper pomija zapytania do AD w godzinach ciszy.
- [ ] Potwierdź, że helper powraca do sprawdzania poza godzinami ciszy.

## 5. Zaplanowane sprawdzenia
- [ ] Ustaw czas powiadomienia kilka minut do przodu.
- [ ] Potwierdź, że helper wykonuje sprawdzenie dokładnie o tej godzinie.
- [ ] Obudź Maca wcześniej i sprawdź ścieżkę: sprawdzenie po wybudzeniu -> co godzinę -> dokładna godzina.

## 6. Okno testowe powiadomienia
- [ ] Wywołaj powiadomienie testowe z Ustawień.
- [ ] Potwierdź, że okno ma przycisk `Zakończ test` wyśrodkowany pod separatorem.
- [ ] Potwierdź, że `Zakończ test` zamyka tylko alert testowy.
- [ ] Potwierdź, że alert produkcyjny nie pokazuje `Zakończ test`.

## 7. Logowanie
- [ ] Potwierdź, że logi rozróżniają ręczny refresh helpera od automatycznego.
- [ ] Potwierdź, że logi zawierają `daysRemaining` i aktywny próg w checkach.
- [ ] Potwierdź, że przycisk ręcznego refreshu nie jest widoczny w Release.

## 8. Smoke checki
- [ ] Otwórz Ustawienia, Logi i UI menu bar; upewnij się, że nie ma regresji layoutu.
- [ ] Potwierdź, że wskaźnik stanu helpera nadal pokazuje włączony/wyłączony.
- [ ] Potwierdź, że `Zmień hasło` otwiera systemową ścieżkę, gdy jest aktywny.
- [ ] Potwierdź, że nie pojawiają się zduplikowane alerty w tym samym dniu mimo snooze/reset.

## 9. Release sanity
- [ ] README i changelog są dołączone do paczki.
- [ ] Numer wersji w aplikacji to 1.5.2.
- [ ] Osadzony helper login-item znajduje się w `PasswordMonitor.app`.
