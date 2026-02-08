# Plan 2.0 (Refactor architektury + App Store readiness)

## Cel
Rozdzielić UI od Core i uprościć zgodność z zasadami App Store.

## Checklist 2.0 (App Store)
- [ ] **Core bez SwiftUI**
- [ ] **UI w osobnym module/target**
- [ ] **Minimalizacja background work**
- [ ] **UX zgodny z policy (notifications, snooze)**

## Zadania techniczne (2.0)
1. **Refactor UI z Core**
   - Przenieść `PasswordExpirationAlert` do app targetu
   - Core tylko dane i eventy

2. **API między Core i UI**
   - Protokół/closure do alertów

3. **Architektura**
   - Rozważ MVVM/TCA (jeśli rośnie złożoność)

## Kryteria App Store (2.0)
- Core nie importuje SwiftUI
- UX w pełni kontrolowany przez app target
- Brak regresji w background helper

## Estymacja
- 2–4 dni
