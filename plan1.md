# Plan 1.0 (App Store Ready)

## Cel
Dowieźć wersję 1.0, która przechodzi App Store Review i nie ujawnia danych wrażliwych.

## Checklist 1.0 (App Store)
- [ ] **PII masking w logach** (username, domena, ścieżki)
- [ ] **Minimal logging** jako domyślny tryb
- [ ] **Informacja o działaniu w tle** (UI + opis w app)
- [ ] **Entitlements audit** (tylko niezbędne)
- [ ] **Brak prywatnych API** i obejść systemowych
- [ ] **Opis funkcji helpera** w onboarding/Settings
- [ ] **Logi możliwe do wyczyszczenia** przez użytkownika
- [ ] **Smoke build** + uruchomienie na lokalnym macOS

## Zadania techniczne (1.0)
1. **Maskowanie PII**
   - `Logger.maskSensitive(_:)` z regex + whitelist
   - Maskować `NSUserName()`, `NSFullUserName()`, domenę, `/Users/<name>`

2. **Minimal logging toggle**
   - `@AppStorage` w Settings
   - Logger: wycina DEBUG, maskuje PII

3. **UI / Copy**
   - Sekcja w Settings: „Background helper działa w celu…”
   - Sekcja w Logach: „Logi nie zawierają danych wrażliwych”

4. **Entitlements**
   - Przegląd `PasswordMonitor.entitlements` i helpera
   - Usunięcie nieużywanych

## Kryteria App Store (1.0)
- Brak wrażliwych danych w logach i UI
- Użytkownik świadomie włącza helpera w tle
- Uprawnienia minimalne
- Brak nieudokumentowanych API

## Estymacja
- 1–2 dni
