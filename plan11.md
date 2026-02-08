# Plan 1.1 (Stabilizacja + zgodność App Store)

## Cel
Podnieść jakość, zachowując pełną zgodność App Store.

## Checklist 1.1 (App Store)
- [ ] **Testy jednostkowe core**
- [ ] **Automatyczny check lokalizacji**
- [ ] **Dokumentacja privacy** w app (krótkie wyjaśnienie danych)
- [ ] **Regresja logów** (nadal bez PII)
- [ ] **Stabilne powiadomienia i snooze**

## Zadania techniczne (1.1)
1. **Target testowy**
   - `PasswordMonitorCoreTests`
   - Testy: cache, powiadomienia, parsing

2. **CI / lokalny skrypt**
   - `scripts/check_localizations.py` jako krok w pipeline

3. **Privacy copy**
   - Krótki opis w Settings o danych i logach

## Kryteria App Store (1.1)
- Testy przechodzą
- Lokalizacje kompletne
- Privacy copy jasne i aktualne

## Estymacja
- 1–2 dni
