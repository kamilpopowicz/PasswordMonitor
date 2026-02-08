# Raport: Analiza punktów awarii synchronizacji uwierzytelniania w środowisku macOS + Active Directory (bez MDM)

**Data:** 8 lutego 2026  
**Autor:** Senior macOS Systems Architect & Security Operations Engineer  
**Kontekst:** Środowisko hybrydowe (biuro/remote), unmanaged macOS (brak MDM), AD binding przez Directory Utility

---

## 1. Streszczenie Wykonawcze

W środowisku bez rozwiązania Mobile Device Management (MDM), gdzie użytkownicy zmieniają hasła Active Directory poza macOS (OWA, Windows, portale self-service), występuje systematyczne **zerwanie łańcucha zaufania** między trzema kluczowymi warstwami zabezpieczeń:

1. **Active Directory** (źródło prawdy)
2. **ShadowHash / LocalCachedUser** (lokalny cache poświadczeń)
3. **FileVault KEK + SecureToken** (warstwa szyfrowania dysku)
4. **Kerberos TGT** (bilety sieciowe SSO)

Niniejszy raport identyfikuje **Top 10 krytycznych punktów awarii**, opisuje objawy, przyczyny techniczne oraz dostarcza konkretne rozwiązania bez użycia MDM.

---

## 2. Architektura problemu

### 2.1. Prawidłowy przepływ (Apple Way)

Apple projektuje zmianę hasła jako **atomową operację** wykonaną z poziomu macOS (System Settings → Users & Groups → Change Password), która synchronicznie aktualizuje:

- **Active Directory** (LDAP Password Modify / Kerberos kpasswd)
- **LocalCachedUser ShadowHash** (`/var/db/dslocal/`)
- **Login Keychain** (przepakowanie `~/Library/Keychains/login.keychain-db`)
- **FileVault KEK** (przepakowanie klucza szyfrowania dysku)
- **Kerberos TGT** (automatyczne odnowienie biletu)

**Zaangażowane daemony:**
- `opendirectoryd` – plugin AD, zarządzanie cache
- `authd` – centralna autoryzacja
- `securityd` – operacje kryptograficzne (keychain, FileVault)
- `fdesetup` / `diskmanagementd` – zarządzanie FileVault
- `loginwindow` – UI logowania

### 2.2. Problematyczny przepływ (Off-Mac Password Change)

Gdy użytkownik zmienia hasło poza macOS:

```
OWA / Windows / Portal
       ↓
   AD Updated
       ↓
   [macOS nie wie o zmianie]
       ↓
   ❌ ShadowHash = stare hasło
   ❌ FileVault KEK = stare hasło
   ❌ Login Keychain = stare hasło
   ❌ Kerberos TGT = podpisany starym hasłem
```

**Konsekwencja:** Użytkownik ma różne hasła w różnych warstwach systemu.

---

## 3. Top 10 krytycznych punktów awarii

### 3.1. FileVault KEK nieprze­pakowany po zdalnej zmianie hasła w AD

**Issue Name:** FileVault 2 pre‑boot password / KEK desynchronization with AD password

**Symptom:**
- Ekran FileVault (pre-boot) odrzuca nowe hasło AD: *"Your password is incorrect"*
- Stare hasło nadal działa przy pre-boot
- Po odblokowaniu dysku starym hasłem ekran logowania macOS akceptuje już nowe hasło AD

**Root Cause:**
- FileVault KEK (Key Encryption Key) jest przepakowywany **tylko** gdy zmiana hasła odbywa się przez `authd`/`securityd` z poziomu macOS
- Zmiana w OWA/Windows/portalu aktualizuje AD, ale nie dotyka KEK
- KEK nadal oczekuje starego hasła do odblokowania dysku

**Zaangażowane komponenty:**
- `authd`, `securityd`, `fdesetup`, `diskmanagementd`, APFS Preboot

**Prevention (No-MDM):**
- SOP: *"Hasło zmieniasz WYŁĄCZNIE na Macu"* (System Settings → Users & Groups → Change Password)
- LaunchAgent monitorujący atrybut `pwdLastSet` w AD (LDAP query) i ostrzegający użytkownika

**Fix (No-MDM):**
```bash
# Wymagany: lokalny admin z SecureToken
sudo fdesetup list -verbose
sudo fdesetup remove -user <username>
sudo fdesetup add -usertoadd <username>
# Podczas 'add' podaj AKTUALNE hasło AD – to nim zostanie przepakowany KEK
```

---

### 3.2. Stary ShadowHash: różne hasła online/offline

**Issue Name:** Stale AD Mobile Account ShadowHash / cached credentials mismatch

**Symptom:**
- **Na sieci/VPN:** logowanie akceptuje nowe hasło AD
- **Poza siecią:** logowanie akceptuje tylko stare hasło
- Terminal: `dscl . passwd /Users/<user> <old> <new>` → *"eDSServiceUnavailable"*

**Root Cause:**
- LocalCachedUser ShadowHash (`/var/db/dslocal/`) nie jest automatycznie aktualizowany po zmianie hasła w AD
- ShadowHash odświeża się **dopiero** gdy użytkownik zaloguje się na Maca będąc połączonym z DC
- Zmiana w OWA + brak kolejnego logowania na sieci = stary hash lokalnie

**Zaangażowane komponenty:**
- `opendirectoryd`, `loginwindow`, `authd`, protokół: LDAP + Kerberos

**Prevention (No-MDM):**
- SOP: Po zdalnej zmianie hasła użytkownik **musi** zalogować się na Maca z sieci/VPN przynajmniej raz
- LaunchAgent: sprawdzanie dostępności AD i wymuszanie "network login check"

**Fix (No-MDM):**
```bash
# Metoda 1: Re-login na sieci
# Wyloguj użytkownika, zaloguj nowym hasłem AD będąc na sieci/VPN

# Metoda 2: Wymuszenie recreate mobile account
sudo /System/Library/CoreServices/ManagedClient.app/Contents/Resources/createmobileaccount -v -n <domainuser>
login <domainuser>

# Metoda 3: Odwiązanie i ponowne związanie z AD
sudo dsconfigad -remove -u <ad-admin> -p <password>
sudo dsconfigad -add <domain> -u <ad-admin> -p <password> -mobile enable -mobileconfirm disable
```

---

### 3.3. Login keychain nie nadąża za hasłem domenowym

**Issue Name:** Login Keychain password divergence after off‑Mac AD password change

**Symptom:**
- Po pierwszym zalogowaniu nowym hasłem AD:
  - *"macOS wants to use the 'login' keychain."*
  - *"The system was unable to unlock your login keychain."*
- Keychain Access prosi o stare hasło

**Root Cause:**
- Login keychain (`~/Library/Keychains/login.keychain-db`) jest szyfrowany hasłem konta w momencie utworzenia
- Zmiana hasła poza Maciem → `opendirectoryd` aktualizuje ShadowHash, ale `securityd` nie może rozszyfrować keychainu bez starego hasła
- Keychain pozostaje zakodowany starym hasłem

**Zaangażowane komponenty:**
- `securityd`, `loginwindow`, `authd`

**Prevention (No-MDM):**
- Jak wyżej: zmiana hasła tylko z Maca

**Fix (No-MDM):**
```bash
# Jeśli użytkownik pamięta stare hasło:
security set-keychain-password ~/Library/Keychains/login.keychain-db

# Jeśli stare hasło nieznane (UWAGA: traci zapisane hasła):
security delete-keychain ~/Library/Keychains/login.keychain-db
# Loginwindow stworzy nowy przy następnym logowaniu
```

**GUI:** Keychain Access → prawy klik "login" → Change Password for Keychain

---

### 3.4. Brak Kerberos TGT przy logowaniu (pam_krb5 `no_ccache`)

**Issue Name:** Kerberos TGT not cached on login due to pam_krb5 no_ccache

**Symptom:**
- Logowanie działa, ale brak automatycznego SSO (SMB/DFS/HTTP SPNEGO)
- `klist` po logowaniu: *"No credentials cache found"*
- Po zablokowaniu ekranu i odblokowaniu TGT pojawia się normalnie

**Root Cause:**
- `/etc/pam.d/authorization` używa opcji:
  ```
  auth optional pam_krb5.so use_first_pass no_ccache
  ```
  Co oznacza: uwierzytelnij przez Kerberos, ale **nie zapisuj TGT**
- `/etc/pam.d/screensaver` używa `use_kcminit` – dlatego lockscreen tworzy TGT

**Zaangażowane komponenty:**
- `pam_krb5`, `authd`, `loginwindow`, `opendirectoryd`, protokół: Kerberos

**Fix (No-MDM):**
```bash
sudo cp /etc/pam.d/authorization /etc/pam.d/authorization.bak
sudo sed -i '' 's/no_ccache/use_kcminit/' /etc/pam.d/authorization

# Po restarcie:
klist   # powinien pokazać ważny TGT
```

**Uwaga:** Nieoficjalny workaround – może być nadpisany przez update systemu. Rozprowadzanie: własny `.pkg` z postinstall script.

---

### 3.5. Kerberos TGT podpisany starym hasłem po zmianie w AD

**Issue Name:** Kerberos TGT invalidation after off‑device password change

**Symptom:**
- Użytkownik zmienia hasło w OWA/Windows
- Mac pozostaje zalogowany na starej sesji
- Po wygaśnięciu TGT: losowe błędy SSO, SMB/DFS pyta o hasło
- `kinit` z nowym hasłem: *"preauthentication failed"*

**Root Cause:**
- Kerberos TGT jest zaszyfrowany kluczem pochodzącym z hasła użytkownika
- Po zmianie hasła stare bilety są logicznie nieważne
- macOS nie ma natywnego mechanizmu automatycznego niszczenia starych TGT po wykryciu zmiany hasła w AD

**Zaangażowane komponenty:**
- `kcm` (Kerberos credential manager), `klist`, `kinit`, `kdestroy`, `opendirectoryd`

**Prevention (No-MDM):**
- SOP helpdesku: Po zdalnej zmianie hasła każ użytkownikowi wylogować się i zalogować ponownie
- LaunchAgent wykonujący przy logowaniu:
  ```bash
  #!/bin/zsh
  /usr/bin/kdestroy -A 2>/dev/null
  ```

**Fix (No-MDM):**
```bash
klist          # obejrzyj istniejące TGT
kdestroy -A    # wyczyść cache
kinit <user@REALM>  # ręczne pobranie nowego TGT nowym hasłem
```

---

### 3.6. SecureToken/FileVault state vs AD password reset

**Issue Name:** SecureToken and FileVault metadata desync after AD‑side or PRK password reset

**Symptom:**
- Użytkownik normalnie loguje się nowym hasłem AD
- Ale:
  - Nie może włączyć/wyłączyć FileVault
  - Nie jest widoczny w `fdesetup list`
  - `sysadminctl -secureTokenStatus <user>` pokazuje `DISABLED`

**Root Cause:**
- SecureToken (10.13+) to warstwa "meta" wiążąca konto użytkownika z FileVault 2
- Zmiana hasła "świadoma" (na Macu) aktualizuje SecureToken + FV KEK jednocześnie
- Zmiana hasła:
  - zresetowanego na poziomie AD,
  - zmienionego lokalnie w Recovery (PRK),
  - przywróconego z Time Machine sprzed zmiany
  powoduje niespójność SecureToken ↔ FileVault

**Zaangażowane komponenty:**
- `sysadminctl`, `fdesetup`, `opendirectoryd`, `authd`, `securityd`

**Prevention (No-MDM):**
- Minimalizować resety hasła z AD bez kontaktu z Maciem
- SOP: Po takim incydencie zawsze wykonać cykl `fdesetup remove/add` + `sysadminctl -secureTokenOff/On`

**Fix (No-MDM):**
```bash
# Sprawdź status
sudo sysadminctl -secureTokenStatus <username>

# Wyłącz i włącz ponownie
sudo sysadminctl \
  -secureTokenOff <username> -password - \
  -adminUser <admin> -adminPassword -

sudo sysadminctl \
  -secureTokenOn <username> -password - \
  -adminUser <admin> -adminPassword -

# Następnie:
sudo fdesetup remove -user <username>
sudo fdesetup add -usertoadd <username>
```

---

### 3.7. Zerwany secure channel komputera do AD

**Issue Name:** Broken AD computer account secure channel with local cached ShadowHash still valid

**Symptom:**
- Logowanie na Maca działa (offline/online)
- W Users & Groups → Network Account Server: **czerwony status**
- SMB/DFS pyta wielokrotnie o hasło
- Zmiana hasła z Maca: *"server unreachable"*
- `id <DOMAIN\user>` zwraca błędy

**Root Cause:**
- Konto komputera w AD ma własne hasło (secure channel)
- Przywrócenie z Time Machine, reset konta komputera w AD, problemy z NTP → secure channel niespójny
- Lokalny ShadowHash użytkownika nadal działa (logowanie możliwe), ale:
  - LDAP query do AD nie działa (eDSServiceUnavailable)
  - Kerberos host principal nie działa

**Zaangażowane komponenty:**
- `opendirectoryd`, protokół: LDAP, Kerberos, NetLogon

**Prevention (No-MDM):**
- Ograniczyć restore całego systemu z Time Machine na Macach związanych z AD
- Monitorować:
  ```bash
  dsconfigad -show
  id <DOMAIN\\user>
  ```

**Fix (No-MDM):**
```bash
# Pełne odwiązanie i związanie
sudo dsconfigad -remove -u <ad-admin> -p '<admin-pass>'
sudo dsconfigad -add <domain.fqdn> \
  -u <ad-admin> -p '<admin-pass>' \
  -mobile enable -mobileconfirm disable

# W razie ciężkich problemów:
sudo rm -rf /Library/Preferences/OpenDirectory/*
sudo killall opendirectoryd
```

---

### 3.8. Obsługa „must change password at next logon" tylko częściowo zgodna z AD

**Issue Name:** AD password expiration / must‑change flag handled inconsistently on macOS

**Symptom:**
- AD ustawia "User must change password at next logon"
- Na Macu przy logowaniu:
  - Okno drży, hasło nie jest akceptowane
  - Próba zmiany: *"You cannot change your password to the password you entered..."*
- Użytkownik kończy z różnymi hasłami w AD i na Macu

**Root Cause:**
- Zmiana hasła z Maca: LDAP Password Modify lub Kerberos kpasswd
- AD ma restrykcje: minimalny czas życia, historia, złożoność
- Przy nieudanej zmianie:
  - macOS pokazuje ogólny błąd
  - Lokalne hasło (ShadowHash) może być już zmienione, a AD odmówił → rozjazd

**Zaangażowane komponenty:**
- `opendirectoryd`, `authd`, PAM, protokół: LDAP, Kerberos (kpasswd)

**Prevention (No-MDM):**
- Przy silnych politykach haseł AD: wymuszaj pierwszą zmianę (po "must change") na Windows/portalu, nie na Macu
- Po zmianie: wymuś logowanie na Macu z nowym hasłem przy połączeniu z AD

**Fix (No-MDM):**
- Doprowadź AD do znanego stanu (hasło ustalone przez helpdesk)
- Na Macu:
  - Zaloguj na lokalnego admina
  - Zresetuj lokalne hasło użytkownika na to samo co w AD
  - Przeprowadź standardowy cykl odświeżenia ShadowHash (logowanie na sieci)

---

### 3.9. Długowieczne cached credentials vs stan konta w AD (disable/lockout)

**Issue Name:** Long‑lived LocalCachedUser ShadowHash after AD account disable/lockout

**Symptom:**
- Konto w AD: wyłączone (disable), zablokowane (lockout), przeniesione do OU bez uprawnień
- Mimo to: użytkownik **nadal może logować się lokalnie do Maca** (offline)
- Brak dostępu do zasobów AD (SMB/DFS/SSO)

**Root Cause:**
- `ShadowHashData` LocalCachedUser nie ma domyślnego TTL – może istnieć "latami"
- Gdy konto w AD zostanie wyłączone:
  - DC przestaje wydawać bilety Kerberos
  - Ale Mac uwierzytelni użytkownika względem lokalnego ShadowHash offline

**Zaangażowane komponenty:**
- `opendirectoryd`, `loginwindow`, `authd`, protokół: LDAP, Kerberos

**Prevention (No-MDM):**
- Jasno określ w polityce bezpieczeństwa: czy akceptujesz lokalny dostęp do Maca dla wyłączonych kont domenowych
- Jeśli nie: procedura helpdesku przy disable w AD:
  ```bash
  sudo sysadminctl -deleteUser <username>
  # lub manualne usunięcie z /var/db/dslocal/nodes/Default/users/
  ```
- Skrypt audytowy:
  - Pobierający listę lokalnych LocalCachedUser
  - Porównujący z AD (LDAP query)
  - Flagujący konta disabled w AD, a istniejące lokalnie

---

### 3.10. Niespójność: ShadowHash ↔ FileVault KEK po „złym" przepływie zmiany hasła

**Issue Name:** ShadowHash vs FileVault KEK mismatch after password change off‑Mac then local reset

**Symptom:**
- Logowanie do macOS wymaga nowego hasła AD
- FileVault przy starcie wymaga starego hasła
- Po akcjach helpdesku (reset lokalnego hasła w Recovery):
  - FileVault akceptuje nowe lokalne hasło/PRK
  - Ale przy logowaniu do AD nowe hasło lokalne nie zgadza się z AD
- Użytkownik ma: jedno hasło do odblokowania dysku, inne do logowania domenowego

**Root Cause:**
- Kombinacja wszystkich trzech warstw:
  - **AD** – "prawdziwe" hasło do TGT
  - **ShadowHash** – przestawiony lokalnie (reset w Recovery bez AD)
  - **FileVault KEK** – przepakowany PRK-iem lub lokalnym hasłem bez dotykania AD

**Scenariusz:**
1. Użytkownik zmienia hasło w OWA → AD ma nowe hasło
2. Mac nie zaktualizował ShadowHash ani KEK
3. Helpdesk używa PRK w Recovery, by zmienić hasło lokalne
4. Wynik:
   - ShadowHash + FileVault KEK = "lokalne hasło z Recovery"
   - AD = "hasło z OWA"
   - Kerberos TGT i zasoby AD nie pasują

**Prevention (No-MDM):**
- Spiąć wszystkie wcześniejsze SOP: zmiana hasła wyłącznie na Macu
- W incydentach z PRK: po naprawie lokalnego dostępu **wyrównaj hasło z AD**

**Fix (No-MDM):**
```bash
# 1. Uzgodnij z AD jedno docelowe hasło (reset po stronie AD)
# 2. Zresetuj lokalne hasło na docelowe
sudo sysadminctl -resetPasswordFor <username> -newPassword '<new-pass>'

# 3. Upewnij się o SecureToken (lub nadaj)
sudo sysadminctl -secureTokenStatus <username>

# 4. Przepnij w FileVault
sudo fdesetup remove -user <username>
sudo fdesetup add -usertoadd <username>

# 5. Po restarcie FileVault, logowanie i AD używają tego samego hasła

# 6. Wyczyść i odnów TGT
kdestroy -A
kinit <user@REALM>
```

---

## 4. Podsumowanie techniczno-biznesowe

### 4.1. Kluczowe wnioski

1. **Brak atomowości:** Apple nie zbudowało spójnego mechanizmu propagacji zmiany hasła z AD do wszystkich lokalnych warstw (ShadowHash, FileVault KEK, Keychain, Kerberos TGT) w scenariuszu off-Mac password change.

2. **Mobile Account Cache:** LocalCachedUser ShadowHash nie ma TTL – może żyć nieograniczenie długo, co jest zagrożeniem bezpieczeństwa przy wyłączeniu konta w AD.

3. **FileVault KEK as Single Point of Failure:** Zmiana hasła w OWA/Windows nie przepakowuje KEK → użytkownik nie może przejść pre-boot bez starego hasła lub PRK.

4. **Kerberos TGT:** Brak automatycznej invalidacji starych biletów po zmianie hasła poza Maciem.

5. **PAM Configuration:** Domyślna konfiguracja `/etc/pam.d/authorization` z `no_ccache` blokuje zapisywanie TGT przy logowaniu.

### 4.2. Ryzyko biznesowe

- **Produktywność:** Użytkownicy tracą czas na helpdesk tickets związane z hasłami
- **Bezpieczeństwo:** Wyłączone konta AD nadal mają lokalny dostęp do Maców
- **Compliance:** Trudność w audycie spójności haseł i dostępów
- **Escalacja:** Każdy incydent wymaga interwencji technicznej (helpdesk/admin)

### 4.3. Koszty operacyjne

- Bez MDM: każda naprawa wymaga manualnej interwencji (zdalnej lub fizycznej)
- Bez automatyzacji: helpdesk spędza ~30-60 min na ticket związany z rozjazdem haseł

---

## 5. Rekomendacje strategiczne

### 5.1. Krótkoterminowe (Immediate - 0-3 miesiące)

1. **SOP:** Wprowadzić twardą procedurę "Hasło zmieniasz WYŁĄCZNIE na Macu"
2. **Helpdesk Playbook:** Udokumentować wszystkie 10 scenariuszy z gotowymi skryptami naprawczymi
3. **PAM Fix:** Wdrożyć poprawkę `/etc/pam.d/authorization` (no_ccache → use_kcminit) na wszystkich Macach
4. **Lokalny Admin:** Zapewnić każdemu Macowi drugi lokalny admin z SecureToken (break-glass account)

### 5.2. Średnioterminowe (Tactical - 3-6 miesięcy)

5. **Password Health Agent:** Zbudować lekki LaunchAgent/Daemon monitorujący:
   - Status AD bind
   - Spójność haseł (online/offline behavior)
   - Obecność Kerberos TGT
   - Ostatnią zmianę hasła (`pwdLastSet` w AD)

6. **Automatyzacja naprawcza:** Skrypty (bash/Swift CLI) do półautomatycznego naprawiania Top 3 najczęstszych problemów

7. **Audyt bezpieczeństwa:** Skrypt porównujący lokalne LocalCachedUser z AD (flagowanie disabled accounts)

### 5.3. Długoterminowe (Strategic - 6-12 miesięcy)

8. **MDM Evaluation:** Rozważyć wdrożenie lekkiego MDM (Jamf Now, Kandji, JumpCloud) dla:
   - Automatycznej synchronizacji haseł
   - Wymuszenia polityk bezpieczeństwa
   - Zdalnego zarządzania FileVault

9. **Kerberos SSO Extension:** Wdrożenie natywnego mechanizmu Apple (wymaga MDM lub ręcznego deployu `.mobileconfig`)

10. **Przejście na Cloud Identity:** Rozważyć migrację z on-premise AD na Entra ID + Platform SSO (macOS 13+)

---

## 6. Załączniki

### 6.1. Kluczowe komendy diagnostyczne

```bash
# Sprawdź status AD bind
dsconfigad -show

# Sprawdź użytkowników FileVault
sudo fdesetup list -verbose

# Sprawdź SecureToken
sudo sysadminctl -secureTokenStatus <username>

# Sprawdź Kerberos TGT
klist

# Sprawdź dostępność AD
id <DOMAIN\\user>

# Sprawdź logi uwierzytelniania
log show --predicate 'subsystem == "com.apple.opendirectoryd"' --last 1h
log show --predicate 'process == "authd"' --last 1h
```

### 6.2. Daemony i protokoły - Quick Reference

| Warstwa | Daemon | Protokół | Odpowiedzialność |
|---------|--------|----------|------------------|
| AD Binding | `opendirectoryd` | LDAP, Kerberos, NetLogon | Plugin AD, cache kont, ShadowHash |
| Autoryzacja | `authd` | PAM, XPC | Centralna autoryzacja, orchestration |
| Keychain | `securityd` | - | Operacje kryptograficzne, keychain |
| FileVault | `fdesetup`, `diskmanagementd` | - | Zarządzanie użytkownikami FV, KEK |
| Kerberos | `kcm`, `kinit`, `kdestroy` | Kerberos | Credential manager, TGT/TGS |
| Login UI | `loginwindow` | - | UI logowania, inicjalizacja sesji |

### 6.3. Referencje Apple

- [Active Directory and mobility on Mac](https://support.apple.com/guide/directory-utility/active-directory-and-mobility-ior6d33c187e/mac) – oficjalna dokumentacja Apple opisująca poprawny przepływ zmiany hasła dla kont mobilnych
- [FileVault password sync (10.14.4+)](https://mrmacintosh.com/10-14-4-forgotten-active-directory-password-sync-fv2/) – mechanizm "forgotten password sync" wprowadzony w Mojave

---

## 7. Kontakt i dalsze kroki

Raport stanowi bazę do budowy **Password Health Agent** oraz kompleksowego **Helpdesk Playbook**.

**Następne kroki:**
1. Przegląd i akceptacja raportu przez Security & Operations
2. Priorytetyzacja rozwiązań (krótko/średnio/długoterminowe)
3. Budowa planu wdrożenia (plan.md)
4. Rozwój Password Health Agent (Swift/SwiftUI menu-bar app)

---

**Koniec raportu**