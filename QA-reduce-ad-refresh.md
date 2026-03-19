# QA reduce-ad-refresh

1. **Domena z systemu** – Po uruchomieniu aplikacji sprawdź, czy ustawienia pokazują domenę Active Directory tylko jako wartość do odczytu i czy tekst informacyjny mówi o konfiguracji z "Użytkownicy i grupy".
2. **Ręczne odświeżenie** – Kliknij "Sprawdź teraz" w menu i upewnij się, że aplikacja wykonuje dokładnie jedno odpytywanie AD (logi lub analiza procesów dscl) oraz że przycisk wraca do stanu aktywnego po zakończeniu.
3. **Automatyczne cooldowny** – Ponownie uruchom system lub helpera i sprawdź logi, czy kolejne automatyczne wywołania (wake, scheduled time) nie powodują wielokrotnych zapytań do AD, a zamiast tego używają cache, dopóki nie upłyną co najmniej 15 minut.
4. **Fallback i cache** – Wywołaj scenariusz, w którym helper nie ma połączenia z AD, a następnie włącz je; sprawdź, czy aplikacja korzysta z cache (czy `menu` pokazuje ostrzeżenie) oraz czy po ponownym połączeniu odświeża dane i usuwa cache flagi.
5. **Helper i menu** – Upewnij się, że helper nie wykonuje godzinnych odświeżeń, tylko reaguje na wybudzenia i ustawiony czas powiadomień, a otwarcie menu nie wywołuje dodatkowych zapytań AD.

## Automatyczne sprawdzenie
- Uruchomiono `xcodebuild test -project PasswordMonitor.xcodeproj -scheme PasswordMonitorCore -destination platform=macOS`. Wszystkie 22 testy `PasswordMonitorCoreTests` przeszły, ale `xcodebuild` zgłosił problemy z zapisem folderu DerivedData/logów (brak uprawnień), więc wynik nadal jest ręcznie weryfikowalny i trzeba poprawić uprawnienia/logi, jeżeli potrzebny jest komplet danych `xcresult`.
