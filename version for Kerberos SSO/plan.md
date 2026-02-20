<!-- plan.md -->

# plan.md — “Nearly-native” password/SSO monitor in my macOS app

## 1) Cel produktu
Zbudować komponent w Twojej aplikacji (Swift/SwiftUI), który w tle monitoruje **stan Kerberos SSO** i “higienę” uwierzytelnienia (TGT świeże/wygaśnięte, potrzeba re-login, zbliżające się wygaśnięcie hasła), a użytkownik dostaje szybki, natywny UX do naprawy problemu. [page:2]  
Nie próbujemy “czytać hasła” użytkownika ani wykonywać agresywnych prób logowania (to ryzykowne i może powodować lockout), tylko opieramy się o mechanizmy systemowe i sygnały stanu. [page:2]

## 2) Założenia i ograniczenia
- Źródłem prawdy dla SSO jest Kerberos SSO extension, które na macOS proaktywnie dba o TGT i może prosić użytkownika o credentiale, gdy Kerberos credential wygasa (typowo ~10h). [page:2]  
- Extension wspiera password expiration (pobiera info o wygaśnięciu po uwierzytelnieniu, po zmianach hasła i okresowo w ciągu dnia), więc Twoja aplikacja może budować UX wokół tych zdarzeń. [page:2]  
- Extension potrafi syncować lokalne hasło z hasłem AD i monitoruje daty zmian haseł, aby ocenić czy są w sync, unikając prób logowania w celu zapobiegania lockoutom. [page:2]  
- Jeśli użytkownicy logują się mobile accounts i zmieniają hasło “na zewnątrz” (WWW/helpdesk reset), extension nie przywróci zgodności hasła mobile account z AD, więc aplikacja powinna ten scenariusz wykrywać i kierować do właściwego remediations. [page:2]

## 3) Architektura (zalecana)
### 3.1 Warstwa “State Reader”
- Użyj CLI `app-sso` do odczytu stanu extension oraz do żądania akcji (np. sign in), bo Apple opisuje `app-sso` właśnie jako narzędzie do odczytu stanu i inicjowania typowych akcji. [page:2]  
- Dodatkowo, dla diagnostyki i fallbacku możesz czytać stan Kerberos przez standardowe narzędzia (`klist`, `kdestroy`, `kinit`) oraz kierować użytkownika do Ticket Viewer. [page:2]

### 3.2 Warstwa “Eventing”
- Extension publikuje notyfikacje, które mogą służyć jako triggery do wykonywania skryptów/akcji (Apple podaje, że notyfikacje są wysyłane zamiast bezpośredniego uruchamiania skryptów, bo procesy extension są sandboxed). [page:2]  
- Twoja aplikacja powinna nasłuchiwać tych zdarzeń (lub cyklicznie odpytywać `app-sso`) i aktualizować stan UI. [page:2]

### 3.3 Warstwa “UI/UX”
- SwiftUI Menu Bar app: status (Signed in / Needs sign-in / Expiring soon / Network not reachable), przyciski “Sign in”, “Reconnect”, “Change password” (jeżeli dozwolone w konfiguracji). [page:2]  
- W UX uwzględnij, że extension ma własne menu extra i własne akcje (Sign In, Reconnect, Change Password, Sign Out), więc Twoja aplikacja ma być spójna semantycznie z tym modelem. [page:2]

## 4) State machine (propozycja)
- `SignedOut`: brak ważnego TGT / extension nie uwierzytelnione. [page:2]  
- `SignedIn`: TGT obecny i świeży, zasoby Kerberos działają. [page:2]  
- `CredentialExpired`: credential wygasł, extension zwykle poprosi o dane (gdy user nie ma auto sign-in), więc Twoja aplikacja powinna promptować do “Sign In”. [page:2]  
- `PasswordExpiringSoon`: extension ma dane o wygaśnięciu hasła i generuje notyfikacje, więc pokaż banner/alert i CTA do zmiany hasła. [page:2]  
- `UnsupportedAccountModel`: wykryty mobile account + zewnętrzna zmiana hasła → pokaż instrukcję migracji / naprawy, bo password sync w tym wariancie nie zadziała. [page:2]

## 5) Implementacja w Twojej aplikacji (kroki)
1. Dodaj moduł `SSOStateProvider`, który uruchamia `app-sso` i parsuje wynik do struktury stanu. [page:2]  
2. Dodaj `SSOEventLoop`: polling co X minut + natychmiastowy refresh po zmianie sieci (NWPathMonitor) i po otrzymaniu notyfikacji systemowych związanych z extension. [page:2]  
3. Dodaj UI Menu Bar + ekran diagnostyki: “Open Ticket Viewer”, “Copy klist output”, “Trigger Reconnect/Sign In”. [page:2]  
4. Dodaj “safe actions only”: nigdy nie wykonuj własnych prób logowania do AD w pętli; oprzyj się o extension, które i tak monitoruje synchronizację na podstawie dat zmian (anti-lockout). [page:2]  
5. Dodaj telemetrię lokalną (bez danych wrażliwych): liczba przypadków `CredentialExpired`, czas do ponownego `SignedIn`, częstotliwość problemów w zależności od sieci (VPN/LAN). [page:2]

## 6) Plan wdrożenia (aplikacja)
- Pilot: 10–20 użytkowników, zbieranie logów i metryk UX, korekty progów polling/alertów.  
- Rollout: kolejne fale, komunikacja w stylu “SSO Health Monitor”, runbook dla helpdesk z akcjami (`app-sso`, `klist`, Ticket Viewer). [page:2]

## 7) Ryzyka i mitigacje
- Brak MDM / brak profilu → brak stabilnego źródła stanu `app-sso` dla Kerberos SSO extension, bo konfiguracja extension jest zakładana przez profil Extensible SSO. [page:1][page:2]  
- Mobile accounts + zewnętrzne zmiany hasła → brak możliwości “magicznego” dosynchronizowania, więc aplikacja musi jasno to komunikować i prowadzić do właściwej ścieżki naprawy/migracji. [page:2]
