<!-- README.md -->

# Kerberos SSO Extension rollout (from Legacy AD Binding)

## Cel
Celem jest wdrożenie Kerberos Single Sign-on (SSO) Extension jako warstwy SSO i mechanizmu ograniczającego problemy z hasłami w środowisku, które historycznie używało **Legacy AD Binding**. [page:2]  
Kerberos SSO extension nie wymaga, aby Mac był dołączony (bound) do Active Directory, a Apple rekomenduje używanie kont lokalnych zamiast logowania AD/mobile accounts. [page:2]

## Ważne: “bez MDM” kontra rzeczywistość
Apple opisuje Kerberos SSO jako rozwiązanie dostarczane konfiguracją przez **device management service** (MDM), a sam Kerberos payload ma wprost oznaczenie “Requires a device management service to install” i “Requires user approval”. [page:1]  
Jeśli Twoim twardym wymaganiem jest “zero MDM”, potraktuj to README jako docelowy, wspierany kierunek (i rozważ minimalny MDM tylko dla profili), bo bez kanału zarządzania wdrożenie profilu może być formalnie niewspierane lub niewykonalne zależnie od polityk systemu. [page:1]

## Pre-req (checklista)

### 1) Active Directory i infrastruktura
- On‑prem Active Directory na Windows Server 2008 lub nowszym. [page:2]  
- Dostęp sieciowy do domeny (Wi‑Fi, Ethernet lub VPN). [page:2]  
- Środowisko musi być klasycznym on‑prem AD (nie samo Entra ID), bo Kerberos SSO extension jest projektowane do on‑prem AD. [page:2]

### 2) macOS / urządzenia / kanał wdrożenia
- Urządzenia muszą być zarządzane usługą zarządzania urządzeniami, która wspiera Extensible SSO payload. [page:2]  
- Kerberos Extensible SSO payload wspiera m.in. macOS kanał device i user, ale instalacja wymaga usługi zarządzania urządzeniami oraz zgody użytkownika. [page:1]  
- Extensible SSO (com.apple.extensiblesso) jest dostępne od macOS 10.15+. [page:3]

### 3) Konfiguracja profilu (kluczowe pola)
Dla profilu Extensible SSO skonfigurowanego na Apple Kerberos extension:
- `ExtensionIdentifier` ustaw na `com.apple.AppSSOKerberos.KerberosExtension`. [page:3]  
- `Type` ustaw na `Credential` (wymagane dla tego ExtensionIdentifier). [page:3]  
- `TeamIdentifier` ustaw na `apple` (wymagane dla tego ExtensionIdentifier na macOS). [page:3]  
- `Realm` jest wymagany i powinien być poprawnie sformatowany (właściwa kapitalizacja). [page:1][page:3]  
- `Hosts` to lista domen/hostów, dla których SSO ma działać (matchowanie jest case-insensitive, wildcard przez prefix kropką). [page:1][page:3]

### 4) Polityka haseł / model kont
- Kerberos SSO extension potrafi synchronizować hasło konta lokalnego z hasłem AD i monitoruje daty zmian haseł (lokalnie i w AD), aby sprawdzać czy nadal są zsynchronizowane, używając dat zamiast prób logowania (żeby nie powodować lockoutów). [page:2]  
- Jeśli **upierasz się przy mobile accounts/AD login**, Apple ostrzega, że password sync nie zadziała w scenariuszu zewnętrznej zmiany hasła (zmiana na stronie WWW lub reset przez helpdesk) — extension nie przywróci wtedy hasła mobile account do zgodności z AD. [page:2]  
- Z tego powodu realny “fix” problemów z hasłami zwykle wymaga przejścia na **konta lokalne + Kerberos SSO extension**. [page:2]

## Etapy wdrożenia (krok po kroku)

### Etap 0 — Inwentaryzacja i segmentacja
1. Zrób listę Maców: wersja macOS, czy są AD-bound, czy używają mobile accounts, czy mają FileVault, ilu jest użytkowników zdalnych.  
2. Zidentyfikuj “risk group”: użytkownicy często zmieniają hasła poza VPN/LAN, użytkownicy często blokowani w AD, użytkownicy z niestabilnym VPN.

### Etap 1 — Decyzja o docelowym modelu kont
1. Ustal, czy celem jest:
   - (A) “SSO dla zasobów” (SMB/HTTP/LDAP) bez rezygnacji z bindingu (etap przejściowy), czy
   - (B) “de-bind + local accounts” jako docelowy standard zgodny z rekomendacją Apple. [page:2]  
2. Jeśli masz mobile accounts i oczekujesz automatycznej naprawy po zewnętrznej zmianie hasła — zaplanuj migrację do kont lokalnych, bo extension tego nie naprawi. [page:2]

### Etap 2 — Przygotowanie profilu (Extensible SSO + Kerberos)
1. Zbuduj profil konfiguracyjny Extensible SSO z wymaganymi polami: `ExtensionIdentifier`, `TeamIdentifier`, `Type`, `Realm`, opcjonalnie `Hosts`. [page:1][page:3]  
2. Włącz synchronizację hasła lokalnego z AD (w wielu narzędziach MDM to opcja “Local Password Sync”; w dokumentacji cytowane jest ustawienie `syncLocalPassword` na `TRUE` w “Custom Configuration/ExtensionData”). [web:26]  
3. (Opcjonalnie) Dodaj konfigurację VPN/per-app VPN tylko jeśli faktycznie jej używasz — extension wspiera scenariusze VPN, a na macOS proaktywnie odświeża TGT na zmianach stanu sieci. [page:2]

### Etap 3 — Dystrybucja profilu na pilot
1. Rozdystrybuuj profil na małą grupę (5–20 urządzeń) przez device management service (wymagane) i przygotuj komunikat o tym, że instalacja wymaga akceptacji użytkownika. [page:1][page:2]  
2. Zapewnij pilotowi łączność z domeną (LAN/VPN), bo użytkownik może zostać poproszony o uwierzytelnienie natychmiast po instalacji, gdy domena jest osiągalna. [page:2]

### Etap 4 — Onboarding użytkownika (co ma zrobić user)
1. Gdy Mac jest w sieci firmowej (lub na VPN), użytkownik zostanie poproszony o zalogowanie do Kerberos SSO extension po instalacji profilu albo przy ponownym wejściu w sieć firmową. [page:2]  
2. Użytkownik może też uruchomić logowanie ręcznie przez menu extra Kerberos SSO extension i wybrać “Sign In”. [page:2]  
3. Po zalogowaniu extension dba o świeżość Kerberos TGT, monitorując połączenia sieciowe i zmiany cache Kerberos. [page:2]

### Etap 5 — Walidacja techniczna (helpdesk/runbook)
1. Sprawdź bilety w Ticket Viewer: `/System/Library/CoreServices/Applications/` → Ticket Viewer. [page:2]  
2. Zweryfikuj bilety z CLI: `klist` (podgląd), `kdestroy` (czyszczenie), `kinit` (pobranie). [page:2]  
3. Do automatyzacji użyj narzędzia `app-sso` (Apple opisuje je jako CLI do odczytu stanu extension i wykonywania akcji typu sign-in). [page:2]

### Etap 6 — Rollout szeroki
1. Po pilocie rozwiń wdrożenie falami (np. działy / lokalizacje), z oknem wsparcia helpdesk w dniach zwiększonej liczby promptów.  
2. Zbieraj metryki: liczba promptów logowania, liczba zdarzeń wygaśnięcia hasła (extension pobiera info o wygaśnięciu po uwierzytelnieniu, po zmianie hasła i okresowo w ciągu dnia). [page:2]

### Etap 7 — Decommission “Legacy Binding” (opcjonalnie, docelowo zalecane)
1. Zaplanuj “de-bind” jako projekt osobny (backup, migracja profilu użytkownika, FileVault escrow, itd.).  
2. Utrzymuj Kerberos SSO extension jako standardowy mechanizm AD-integracji dla kont lokalnych (to scenariusz, pod który extension było projektowane). [page:2]

## Minimalny szkic profilu (edukacyjny)
Poniższy fragment pokazuje logikę kluczy, a nie kompletny, produkcyjny `.mobileconfig`. [page:3]

- ExtensionIdentifier: `com.apple.AppSSOKerberos.KerberosExtension` [page:3]
- TeamIdentifier: `apple` [page:3]
- Type: `Credential` [page:3]
- Realm: `YOUR.REALM` [page:1][page:3]
- Hosts: np. `.corp.example.com`, `fileserver.corp.example.com` [page:1][page:3]
- ExtensionData / Custom Configuration: opcje Kerberos i password sync (np. `syncLocalPassword`). [web:26]
