# Plan wdrożenia: Password Monitor – Aplikacja do monitorowania spójności haseł macOS + AD

**Wersja:** 1.0  
**Data:** 8 lutego 2026  
**Cel nadrzędny:** Zbudowanie natywnej aplikacji macOS (Swift/SwiftUI) monitorującej i naprawiającej problemy synchronizacji haseł w środowisku AD bez MDM

---

## 1. Założenia architektoniczne

### 1.1. Nazwa projektu
**Password Monitor** (nazwa robocza)

### 1.2. Stack technologiczny
- **Język:** Swift 5.9+ (Concurrency: async/await, Actors)
- **UI:** SwiftUI 5.0+ (macOS 14 Sonoma+)
- **Integracja systemowa:** AppKit (NSViewRepresentable), ServiceManagement (LaunchAgent)
- **Bezpieczeństwo:** Security.framework, LocalAuthentication.framework
- **Logi:** OSLog (Unified Logging), NaturalLanguage.framework (klasyfikacja błędów)
- **Deployment:** Standalone `.app` + opcjonalny `.pkg` installer

### 1.3. Architektura aplikacji

```
┌─────────────────────────────────────────────────────────────┐
│  Password Monitor (Menu Bar App)                            │
│  ┌────────────────────────────────────────────────────────┐ │
│  │  SwiftUI UI Layer                                       │ │
│  │  • MenuBarView (SF Symbols status indicator)            │ │
│  │  • SettingsView (user preferences)                      │ │
│  │  • DiagnosticsView (real-time health check)             │ │
│  │  • RepairView (guided repair workflows)                 │ │
│  └────────────────────────────────────────────────────────┘ │
│                           ↓                                  │
│  ┌────────────────────────────────────────────────────────┐ │
│  │  Business Logic (Actor-based)                           │ │
│  │  • ADHealthMonitor (AD bind status, pwdLastSet)         │ │
│  │  • FileVaultMonitor (fdesetup status, KEK sync)         │ │
│  │  • KerberosMonitor (TGT presence, validity)             │ │
│  │  • LogAnalyzer (OSLog parsing, NLP classification)      │ │
│  └────────────────────────────────────────────────────────┘ │
│                           ↓                                  │
│  ┌────────────────────────────────────────────────────────┐ │
│  │  System Integration (Process, XPC, Security.framework)  │ │
│  │  • ShellExecutor (dsconfigad, fdesetup, klist)          │ │
│  │  • PrivilegedHelper (XPC Service for root operations)   │ │
│  └────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

### 1.4. Privacy-first design
- **On-device only:** Wszystkie operacje wykonywane lokalnie
- **Zero telemetrii:** Brak wysyłania danych na zewnątrz
- **Minimal permissions:** Tylko niezbędne uprawnienia (Full Disk Access dla odczytu logów)

---

## 2. Roadmap wdrożenia (MVP → Full Feature Set)

### Faza 0: Research & Prototyping (2 tygodnie)
**Cel:** Walidacja feasibility kluczowych funkcji

### Faza 1: MVP - Core Monitoring (4 tygodnie)
**Cel:** Podstawowy monitoring i alerting

### Faza 2: Enhanced Diagnostics (3 tygodnie)
**Cel:** Zaawansowana diagnostyka i klasyfikacja problemów

### Faza 3: Automated Repair (4 tygodnie)
**Cel:** Półautomatyczne naprawy z guided workflows

### Faza 4: Polish & Distribution (2 tygodnie)
**Cel:** Hardening, notarization, dystrybucja

---

## 3. Szczegółowy breakdown - Faza 0: Research & Prototyping

### Milestone 0.1: Shell Integration PoC

**Zadanie:** Sprawdzić wykonalność wywołań shell commands z Swift i parsowania ich outputu

**Kroki:**
1. Stworzyć `ShellExecutor` struct z metodą `run(_:) async throws -> String`
2. Zaimplementować wywołania:
   ```swift
   try await shell.run("dsconfigad -show")
   try await shell.run("fdesetup list")
   try await shell.run("klist")
   try await shell.run("id \(domain)\\\\(username)")
   ```
3. Przetestować parsowanie outputu (Regex / Scanner)

**Kryteria akceptacji:**
- [ ] Udane wywołanie wszystkich 4 komend
- [ ] Parsowanie outputu do struktur Swift (np. `struct ADStatus { var computerAccount: String; var forestName: String }`)
- [ ] Obsługa błędów (command not found, permission denied)
- [ ] Wykonanie w tle (Task.detached) bez blokowania UI

**Ryzyko:** `dsconfigad` wymaga root → konieczność PrivilegedHelper (XPC). Alternatywa: użyć `dscl` i `id` (nie wymagają sudo dla read-only).

**Czas:** 3 dni

---

### Milestone 0.2: OSLog Parsing PoC

**Zadanie:** Sprawdzić czy możliwe jest odczytywanie logów `authd`, `opendirectoryd`, `securityd` w runtime

**Kroki:**
1. Użyć `OSLogStore` (macOS 12+) do odczytu logów:
   ```swift
   import OSLog
   
   let store = try OSLogStore(scope: .currentProcessIdentifier)
   let position = store.position(date: Date().addingTimeInterval(-3600)) // ostatnia godzina
   let entries = try store.getEntries(at: position)
   ```
2. Filtrować po subsystem:
   - `com.apple.opendirectoryd`
   - `com.apple.authd`
   - `com.apple.securityd`
3. Wyodrębnić kluczowe wzorce błędów:
   - `"eDSServiceUnavailable"`
   - `"preauthentication failed"`
   - `"password mismatch"`

**Kryteria akceptacji:**
- [ ] Udany odczyt logów z ostatnich 24h
- [ ] Filtrowanie po subsystem i poziomie (error, fault)
- [ ] Wykrycie przynajmniej 3 wzorców błędów związanych z hasłami
- [ ] Wydajność: parsowanie 1h logów < 2s

**Ryzyko:** Full Disk Access (FDA) może być wymagane dla dostępu do logów systemowych → dodać do Entitlements.

**Czas:** 3 dni

---

### Milestone 0.3: NaturalLanguage Classification PoC

**Zadanie:** Użyć NaturalLanguage.framework do klasyfikacji błędów logów na kategorie

**Kroki:**
1. Przygotować prosty dataset treningowy (50-100 przykładów):
   ```
   "eDSServiceUnavailable" → "AD_UNREACHABLE"
   "password mismatch" → "PASSWORD_OUT_OF_SYNC"
   "No credentials cache" → "KERBEROS_TGT_MISSING"
   ```
2. Użyć `NLModel` + `NLModelConfiguration` (klasyfikacja tekstu):
   ```swift
   import NaturalLanguage
   
   let model = try NLModel(contentsOf: modelURL)
   let prediction = model.predictedLabel(for: logMessage)
   ```
3. Alternatywa (jeśli nie ma czasu na trening): Rule-based classifier (Regex + Dictionary)

**Kryteria akceptacji:**
- [ ] Klasyfikator rozpoznaje 5 kategorii błędów:
  - `AD_UNREACHABLE`
  - `PASSWORD_OUT_OF_SYNC`
  - `KERBEROS_TGT_MISSING`
  - `FILEVAULT_KEK_MISMATCH`
  - `SECURE_CHANNEL_BROKEN`
- [ ] Accuracy > 80% na testowym zestawie
- [ ] Inference time < 100ms na log entry

**Ryzyko:** Training NLModel może być overkill dla MVP → jeśli tak, użyć rule-based.

**Czas:** 4 dni

---

### Milestone 0.4: MenuBar App Scaffold

**Zadanie:** Stworzyć podstawową strukturę menu bar app z SwiftUI

**Kroki:**
1. Projekt Xcode: macOS App (SwiftUI)
2. Ukryć main window, pokazać tylko menu bar icon:
   ```swift
   @main
   struct PasswordMonitorApp: App {
       @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
       
       var body: some Scene {
           Settings {
               EmptyView()
           }
       }
   }
   
   class AppDelegate: NSObject, NSApplicationDelegate {
       var statusItem: NSStatusItem!
       
       func applicationDidFinishLaunching(_ notification: Notification) {
           statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
           statusItem.button?.image = NSImage(systemSymbolName: "lock.shield", accessibilityDescription: nil)
           // Menu setup
       }
   }
   ```
3. Dodać podstawowe menu:
   - "Status: Checking..."
   - "Open Diagnostics"
   - "Settings"
   - "Quit"

**Kryteria akceptacji:**
- [ ] Aplikacja uruchamia się i pokazuje ikonę w menu bar
- [ ] Menu rozwija się po kliknięciu
- [ ] "Quit" zamyka aplikację
- [ ] Ikona zmienia kolor w zależności od stanu (zielony/żółty/czerwony – SF Symbols)

**Czas:** 2 dni

---

### Milestone 0.5: Go/No-Go Decision

**Cel:** Ocena feasibility całego projektu

**Kryteria Go:**
- [ ] Shell integration działa (parsing outputu)
- [ ] OSLog parsing działa (Full Disk Access akceptowalne)
- [ ] NaturalLanguage lub rule-based classifier działa (accuracy > 80%)
- [ ] MenuBar scaffold działa

**Jeśli Go → przejście do Fazy 1 (MVP)**

**Czas:** 1 dzień (review)

---

## 4. Faza 1: MVP - Core Monitoring

### Milestone 1.1: ADHealthMonitor Implementation

**Zadanie:** Zaimplementować monitoring statusu AD bind

**Kroki:**
1. Stworzyć `ADHealthMonitor` actor:
   ```swift
   actor ADHealthMonitor {
       private let shell: ShellExecutor
       
       func checkStatus() async throws -> ADStatus {
           let output = try await shell.run("dsconfigad -show")
           return parseADStatus(output)
       }
       
       func checkUserPwdLastSet(_ username: String) async throws -> Date? {
           // LDAP query via dscl or ldapsearch
       }
   }
   ```
2. Parsować kluczowe pola:
   - Computer Account
   - Forest
   - Domain Controller connectivity (zielony/czerwony)
3. Dodać `pwdLastSet` check (wymaga LDAP query):
   ```bash
   ldapsearch -H ldap://<dc> -b "DC=domain,DC=com" "(sAMAccountName=username)" pwdLastSet
   ```

**Kryteria akceptacji:**
- [ ] Detekcja czy Mac jest AD-bound (true/false)
- [ ] Detekcja statusu połączenia z DC (online/offline)
- [ ] Pobranie `pwdLastSet` z AD dla aktualnego użytkownika
- [ ] Porównanie `pwdLastSet` z lokalnym timestampem (heurystyka: czy hasło zmieniono ostatnio?)
- [ ] Wykonanie w tle (actor isolation), wynik zwracany na @MainActor

**Czas:** 5 dni

---

### Milestone 1.2: FileVaultMonitor Implementation

**Zadanie:** Monitorowanie stanu FileVault i wykrywanie KEK desync

**Kroki:**
1. Stworzyć `FileVaultMonitor` actor:
   ```swift
   actor FileVaultMonitor {
       func checkStatus() async throws -> FileVaultStatus {
           let output = try await shell.run("fdesetup status")
           let users = try await shell.run("fdesetup list")
           return parseFileVaultStatus(output, users)
       }
   }
   ```
2. Parsować:
   - Czy FileVault jest włączony
   - Lista użytkowników z dostępem do FV
   - Czy aktualny użytkownik jest na liście
3. Heurystyka KEK desync:
   - Jeśli `pwdLastSet` (z AD) > "last FV user modification" → potencjalny desync
   - Alternatywa: user reporting (prompt "czy FileVault wymaga starego hasła?")

**Kryteria akceptacji:**
- [ ] Detekcja czy FileVault włączony (true/false)
- [ ] Detekcja czy aktualny user ma dostęp do FV
- [ ] Detekcja czy istnieje SecureToken (via `sysadminctl -secureTokenStatus`)
- [ ] Warning jeśli heurystyka wskazuje na KEK desync
- [ ] UI pokazuje status FileVault (zielony/żółty/czerwony)

**Czas:** 4 dni

---

### Milestone 1.3: KerberosMonitor Implementation

**Zadanie:** Monitorowanie TGT (Ticket Granting Ticket)

**Kroki:**
1. Stworzyć `KerberosMonitor` actor:
   ```swift
   actor KerberosMonitor {
       func checkTGT() async throws -> KerberosStatus {
           let output = try await shell.run("klist")
           return parseKerberos(output)
       }
   }
   ```
2. Parsować:
   - Czy TGT istnieje
   - Czas wygaśnięcia TGT
   - Principal name
3. Walidacja:
   - TGT powinien istnieć zaraz po logowaniu
   - TGT nie powinien być expired

**Kryteria akceptacji:**
- [ ] Detekcja obecności TGT (true/false)
- [ ] Detekcja czasu do wygaśnięcia TGT
- [ ] Warning jeśli brak TGT mimo że Mac jest AD-bound
- [ ] Warning jeśli TGT expired (potencjalnie stare hasło)
- [ ] UI pokazuje status Kerberos (zielony/żółty/czerwony)

**Czas:** 3 dni

---

### Milestone 1.4: Unified Health Dashboard (SwiftUI)

**Zadanie:** Stworzyć centralny dashboard pokazujący status wszystkich monitorów

**Kroki:**
1. `DiagnosticsView.swift`:
   ```swift
   struct DiagnosticsView: View {
       @StateObject private var viewModel = DiagnosticsViewModel()
       
       var body: some View {
           VStack(alignment: .leading, spacing: 16) {
               StatusRow(title: "Active Directory", status: viewModel.adStatus)
               StatusRow(title: "FileVault", status: viewModel.fvStatus)
               StatusRow(title: "Kerberos", status: viewModel.kerberosStatus)
               
               if viewModel.hasIssues {
                   Button("View Details") { viewModel.showDetails() }
               }
           }
           .padding()
           .frame(width: 400, height: 300)
       }
   }
   ```
2. `DiagnosticsViewModel`:
   - Agreguje dane z trzech monitorów
   - Określa overall health status
   - Wyświetla top issue (jeśli istnieje)

**Kryteria akceptacji:**
- [ ] Dashboard pokazuje status 3 komponentów (AD, FileVault, Kerberos)
- [ ] Każdy komponent ma kolor status indicator (zielony/żółty/czerwony)
- [ ] Overall status agregowany (czerwony jeśli którykolwiek komponent czerwony)
- [ ] Ikona w menu bar zmienia kolor w zależności od overall status
- [ ] Kliknięcie "View Details" rozwija szczegóły problemu

**Czas:** 4 dni

---

### Milestone 1.5: LaunchAtLogin Integration

**Zadanie:** Umożliwić użytkownikowi włączenie "Launch at Login"

**Kroki:**
1. Użyć `ServiceManagement.framework`:
   ```swift
   import ServiceManagement
   
   func enableLaunchAtLogin() {
       SMLoginItemSetEnabled("com.yourcompany.PasswordMonitor" as CFString, true)
   }
   ```
2. Alternatywa (macOS 13+):
   ```swift
   import ServiceManagement
   
   @MainActor
   func enableLaunchAtLogin() throws {
       try SMAppService.mainApp.register()
   }
   ```
3. Dodać toggle w Settings

**Kryteria akceptacji:**
- [ ] Toggle "Launch at Login" w Settings działa
- [ ] Po restart aplikacja automatycznie startuje (jeśli enabled)
- [ ] Status "Launch at Login" persystowany (UserDefaults)

**Czas:** 2 dni

---

### Milestone 1.6: MVP Release (Internal Beta)

**Cel:** Wdrożenie wersji MVP do testów wewnętrznych

**Kryteria akceptacji:**
- [ ] Wszystkie Milestone 1.1-1.5 ukończone
- [ ] Aplikacja kompiluje się i uruchamia bez crashy
- [ ] Menu bar icon pokazuje overall status
- [ ] Diagnostics dashboard wyświetla real-time status
- [ ] Launch at Login działa
- [ ] Dokumentacja użytkownika (README.md) gotowa

**Deliverables:**
- `PasswordMonitor.app` (unsigned, dla testów lokalnych)
- `README.md` (instrukcja instalacji i użycia)
- `CHANGELOG.md` (MVP features)

**Czas:** 2 dni (testing + bug fixes)

---

## 5. Faza 2: Enhanced Diagnostics

### Milestone 2.1: LogAnalyzer Integration

**Zadanie:** Zintegrować OSLog parsing i klasyfikację błędów

**Kroki:**
1. Stworzyć `LogAnalyzer` actor:
   ```swift
   actor LogAnalyzer {
       private let classifier: ErrorClassifier
       
       func analyzeLogs(since: Date) async throws -> [ClassifiedError] {
           let entries = try fetchLogEntries(since: since)
           return entries.compactMap { classifier.classify($0) }
       }
   }
   ```
2. `ErrorClassifier` (rule-based lub NLModel):
   - Input: log message (String)
   - Output: `ErrorCategory` enum + confidence score
3. Dodać do `DiagnosticsViewModel`:
   ```swift
   @Published var recentErrors: [ClassifiedError] = []
   ```

**Kryteria akceptacji:**
- [ ] Analiza logów z ostatnich 24h
- [ ] Klasyfikacja błędów na 5 kategorii (z Milestone 0.3)
- [ ] Top 3 błędy pokazane w UI
- [ ] Performance: analiza < 3s dla 24h logów
- [ ] User może kliknąć błąd aby zobaczyć pełny context

**Czas:** 5 dni

---

### Milestone 2.2: Automatic Issue Detection

**Zadanie:** Automatyczne wykrywanie Top 3 najczęstszych problemów

**Kroki:**
1. `IssueDetector` actor agregujący dane z monitorów i LogAnalyzer:
   ```swift
   actor IssueDetector {
       func detectIssues() async -> [DetectedIssue] {
           var issues: [DetectedIssue] = []
           
           // Issue 1: FileVault KEK desync
           if adMonitor.pwdLastSet > fvMonitor.lastModified {
               issues.append(.fileVaultDesync)
           }
           
           // Issue 2: Kerberos TGT missing
           if kerberosMonitor.tgt == nil && adMonitor.isOnline {
               issues.append(.kerberosNoCache)
           }
           
           // Issue 3: ShadowHash stale
           if logAnalyzer.hasError(.passwordMismatch) {
               issues.append(.shadowHashStale)
           }
           
           return issues
       }
   }
   ```
2. Każdy `DetectedIssue` ma:
   - Opis problemu
   - Severity (critical/warning/info)
   - Rekomendowaną akcję

**Kryteria akceptacji:**
- [ ] Automatyczne wykrywanie 3 najczęstszych problemów:
  1. FileVault KEK desync
  2. Kerberos TGT missing
  3. ShadowHash stale
- [ ] UI pokazuje detected issues w kolejności severity
- [ ] Każdy issue ma "Learn More" link (otwiera szczegóły)

**Czas:** 4 dni

---

### Milestone 2.3: Notification System

**Zadanie:** Dodać UserNotifications dla critical issues

**Kroki:**
1. Dodać `UserNotifications.framework`:
   ```swift
   import UserNotifications
   
   func sendNotification(title: String, body: String) {
       let content = UNMutableNotificationContent()
       content.title = title
       content.body = body
       content.sound = .default
       
       let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
       UNUserNotificationCenter.current().add(request)
   }
   ```
2. Żądać uprawnienia przy pierwszym uruchomieniu:
   ```swift
   UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
   ```
3. Wysyłać notyfikację gdy:
   - Critical issue wykryty (np. FileVault KEK desync)
   - User zalogował się na Maca po zmianie hasła w AD

**Kryteria akceptacji:**
- [ ] Notyfikacje wysyłane dla critical issues
- [ ] User może wyłączyć notyfikacje w Settings
- [ ] Notyfikacje nie są spamujące (max 1 na issue na 24h)
- [ ] Kliknięcie notyfikacji otwiera Diagnostics view

**Czas:** 3 dni

---

### Milestone 2.4: Historical Tracking

**Zadanie:** Zapisywać historię detected issues dla trendu

**Kroki:**
1. Persistence layer (Core Data lub plik JSON):
   ```swift
   struct IssueRecord: Codable {
       let timestamp: Date
       let issueType: DetectedIssue
       let resolved: Bool
   }
   ```
2. `HistoryView` (SwiftUI):
   - Lista issues z ostatnich 30 dni
   - Filtrowanie po typie
   - Trend graph (jeśli czas pozwala)

**Kryteria akceptacji:**
- [ ] Issues zapisywane lokalnie
- [ ] History view pokazuje ostatnie 30 dni
- [ ] User może oznaczyć issue jako "resolved"
- [ ] Dane persistowane między restartami aplikacji

**Czas:** 4 dni

---

## 6. Faza 3: Automated Repair

### Milestone 3.1: PrivilegedHelper (XPC Service)

**Zadanie:** Stworzyć XPC Service dla operacji wymagających sudo

**Kroki:**
1. Dodać nowy target: "PasswordMonitorHelper" (Command Line Tool)
2. Implementować XPC protocol:
   ```swift
   @objc protocol PrivilegedHelperProtocol {
       func resetShadowHash(username: String, reply: @escaping (Bool, Error?) -> Void)
       func syncFileVault(username: String, reply: @escaping (Bool, Error?) -> Void)
   }
   ```
3. Instalacja helper:
   ```swift
   import ServiceManagement
   
   func installHelper() throws {
       var authRef: AuthorizationRef?
       AuthorizationCreate(nil, nil, [], &authRef)
       
       try SMJobBless(kSMDomainSystemLaunchd, "com.yourcompany.PasswordMonitorHelper" as CFString, authRef, nil)
   }
   ```
4. Komunikacja main app ↔ helper (XPC)

**Kryteria akceptacji:**
- [ ] Helper zainstalowany w `/Library/PrivilegedHelperTools/`
- [ ] Main app może wywołać helper przez XPC
- [ ] Helper wykonuje operacje z uprawnieniami root
- [ ] Authorization prompt pokazuje się przy pierwszym użyciu
- [ ] Bezpieczeństwo: helper weryfikuje code signature main app

**Czas:** 6 dni (najtrudniejszy milestone)

---

### Milestone 3.2: Guided Repair: FileVault KEK Resync

**Zadanie:** Implementacja guided workflow dla Issue #1 (FileVault KEK desync)

**Kroki:**
1. `RepairView.swift` (SwiftUI):
   ```swift
   struct FileVaultRepairView: View {
       @StateObject private var viewModel = FileVaultRepairViewModel()
       
       var body: some View {
           VStack(alignment: .leading, spacing: 16) {
               Text("FileVault Password Out of Sync")
                   .font(.headline)
               
               Text("Your FileVault pre-boot password is different from your AD password. Follow these steps:")
               
               StepView(number: 1, title: "Authenticate", status: viewModel.step1Status) {
                   viewModel.authenticateAdmin()
               }
               
               StepView(number: 2, title: "Remove from FileVault", status: viewModel.step2Status) {
                   viewModel.removeFromFV()
               }
               
               StepView(number: 3, title: "Re-add to FileVault", status: viewModel.step3Status) {
                   viewModel.addToFV()
               }
           }
       }
   }
   ```
2. `FileVaultRepairViewModel`:
   - Wywołuje PrivilegedHelper dla `fdesetup remove/add`
   - Pokazuje progress i error handling

**Kryteria akceptacji:**
- [ ] Guided workflow z 3 krokami
- [ ] User widzi status każdego kroku (pending/in-progress/done/error)
- [ ] Po zakończeniu: weryfikacja czy problem rozwiązany
- [ ] Error handling: jeśli krok nie powiedzie się, pokazać jasny komunikat

**Czas:** 5 dni

---

### Milestone 3.3: Guided Repair: Kerberos TGT Refresh

**Zadanie:** Workflow dla Issue #5 (Kerberos TGT stale)

**Kroki:**
1. `KerberosRepairView.swift`:
   - Krok 1: `kdestroy -A` (clear cache)
   - Krok 2: `kinit user@REALM` (prompt for password)
   - Krok 3: Weryfikacja `klist`
2. Password prompt (SecureField):
   ```swift
   SecureField("Enter your AD password", text: $password)
   ```

**Kryteria akceptacji:**
- [ ] User może ręcznie wyczyścić TGT cache
- [ ] User może pobrać nowy TGT (z prompted password)
- [ ] Po zakończeniu: `klist` pokazuje nowy TGT
- [ ] Success message jeśli TGT valid

**Czas:** 3 dni

---

### Milestone 3.4: Guided Repair: ShadowHash Refresh

**Zadanie:** Workflow dla Issue #2 (ShadowHash stale)

**Kroki:**
1. `ShadowHashRepairView.swift`:
   - Instrukcja: "Log out and log back in with your new AD password while connected to the network"
   - Opcjonalnie: auto-trigger logout (wymaga user consent)
2. Alternatywa (jeśli user nie chce się wylogować):
   - Pokazać instrukcję manualną:
     ```
     1. Connect to VPN (if remote)
     2. Log out (Apple menu → Log Out)
     3. Log in with new AD password
     ```

**Kryteria akceptacji:**
- [ ] User widzi jasne instrukcje
- [ ] Opcjonalnie: przycisk "Log Out Now" (trigger logout)
- [ ] Po ponownym zalogowaniu: aplikacja automatycznie weryfikuje czy ShadowHash odświeżony

**Czas:** 2 dni

---

### Milestone 3.5: Repair Workflow Orchestration

**Zadanie:** Centralny orchestrator decydujący który repair workflow uruchomić

**Kroki:**
1. `RepairCoordinator` actor:
   ```swift
   actor RepairCoordinator {
       func suggestRepair(for issue: DetectedIssue) -> RepairWorkflow {
           switch issue {
           case .fileVaultDesync:
               return .fileVaultKEKResync
           case .kerberosNoCache:
               return .kerberosTGTRefresh
           case .shadowHashStale:
               return .shadowHashRefresh
           }
       }
   }
   ```
2. UI: Po wykryciu issue, pokazać przycisk "Fix Now" który otwiera odpowiedni RepairView

**Kryteria akceptacji:**
- [ ] Dla każdego detected issue istnieje odpowiedni repair workflow
- [ ] User może uruchomić repair z Diagnostics view (przycisk "Fix Now")
- [ ] Po zakończeniu repair: ponowna detekcja (czy issue resolved)
- [ ] Jeśli resolved: success message + usunięcie z listy issues

**Czas:** 3 dni

---

## 7. Faza 4: Polish & Distribution

### Milestone 4.1: Error Handling & Edge Cases

**Zadanie:** Hardening aplikacji - obsługa błędów i edge cases

**Kroki:**
1. Audit wszystkich `try await` - dodać proper error handling
2. Edge cases:
   - Mac nie jest AD-bound → pokazać komunikat
   - User nie ma uprawnień admin → pokazać instrukcję
   - Full Disk Access nie nadany → pokazać prompt
3. Graceful degradation:
   - Jeśli OSLog nie dostępny → disable log analysis, ale podstawowy monitoring działa

**Kryteria akceptacji:**
- [ ] Aplikacja nie crashuje przy żadnym known edge case
- [ ] User widzi jasne komunikaty błędów (nie "Unknown error")
- [ ] Brak memory leaks (Instruments: Leaks, Allocations)
- [ ] Brak retain cycles (Instruments: Retain Cycles)

**Czas:** 4 dni

---

### Milestone 4.2: Performance Optimization

**Zadanie:** Optymalizacja wydajności

**Kroki:**
1. Profiling (Instruments: Time Profiler):
   - Zidentyfikować bottlenecks
   - Optymalizować parsowanie shell output (cache results)
2. Background processing:
   - Wszystkie shell commands w `Task.detached` lub dedicated actor
   - Throttling: nie sprawdzaj statusu częściej niż co 30s
3. UI responsiveness:
   - Lazy loading w History view
   - Debouncing search w Settings

**Kryteria akceptacji:**
- [ ] UI zawsze płynne (60 fps)
- [ ] Health check wykonuje się < 2s
- [ ] Memory footprint < 50 MB (idle)
- [ ] CPU usage < 5% (idle)

**Czas:** 3 dni

---

### Milestone 4.3: Localization (opcjonalne)

**Zadanie:** Dodać lokalizację PL/EN

**Kroki:**
1. Wszystkie stringi w `Localizable.strings`:
   ```swift
   Text("Active Directory")
       .localized()
   ```
2. Dodać tłumaczenia:
   - `en.lproj/Localizable.strings`
   - `pl.lproj/Localizable.strings`

**Kryteria akceptacji:**
- [ ] Aplikacja dostępna w języku polskim i angielskim
- [ ] Język automatycznie wykrywany z system settings
- [ ] Wszystkie stringi (UI + komunikaty błędów) przetłumaczone

**Czas:** 2 dni (jeśli czas pozwala)

---

### Milestone 4.4: Code Signing & Notarization

**Zadanie:** Przygotowanie do dystrybucji - podpisanie i notarization

**Kroki:**
1. Apple Developer Account:
   - Utworzyć App ID: `com.yourcompany.PasswordMonitor`
   - Utworzyć Developer ID Application certificate
2. Entitlements (`PasswordMonitor.entitlements`):
   ```xml
   <key>com.apple.security.app-sandbox</key>
   <false/>
   <key>com.apple.security.files.user-selected.read-write</key>
   <true/>
   ```
3. Code signing:
   ```bash
   codesign --deep --force --verify --verbose --sign "Developer ID Application: Your Name" PasswordMonitor.app
   ```
4. Notarization:
   ```bash
   xcrun notarytool submit PasswordMonitor.zip --apple-id "your@email.com" --password "app-specific-password" --wait
   xcrun stapler staple PasswordMonitor.app
   ```

**Kryteria akceptacji:**
- [ ] Aplikacja podpisana Developer ID certificate
- [ ] Notarization sukces (no issues)
- [ ] Stapled ticket dołączony do .app
- [ ] Aplikacja uruchamia się na czystym Macu bez "unidentified developer" warning

**Czas:** 2 dni

---

### Milestone 4.5: PKG Installer

**Zadanie:** Stworzyć installer `.pkg` z automatyczną instalacją PrivilegedHelper

**Kroki:**
1. Użyć `pkgbuild` + `productbuild`:
   ```bash
   pkgbuild --component PasswordMonitor.app --install-location /Applications PasswordMonitor-component.pkg
   productbuild --distribution distribution.xml --package-path . PasswordMonitor-1.0.pkg
   ```
2. Postinstall script:
   - Instalacja LaunchAgent (opcjonalnie)
   - Prompt o Full Disk Access
3. Podpisać PKG:
   ```bash
   productsign --sign "Developer ID Installer: Your Name" PasswordMonitor-1.0.pkg PasswordMonitor-1.0-signed.pkg
   ```

**Kryteria akceptacji:**
- [ ] PKG instaluje aplikację w `/Applications`
- [ ] PKG podpisany Developer ID Installer certificate
- [ ] Installer zawiera README (pokazywany podczas instalacji)
- [ ] Po instalacji aplikacja automatycznie się uruchamia (opcjonalnie)

**Czas:** 2 dni

---

### Milestone 4.6: Documentation & Release

**Zadanie:** Finalizacja dokumentacji i release

**Deliverables:**
1. **README.md**:
   - Opis aplikacji
   - System requirements (macOS 14+)
   - Instrukcja instalacji
   - FAQ
2. **USER_GUIDE.md**:
   - Szczegółowy przewodnik użytkownika
   - Screenshots
   - Troubleshooting
3. **DEVELOPER.md**:
   - Architektura kodu
   - Build instructions
   - Contributing guidelines
4. **CHANGELOG.md**:
   - Historia wersji
5. **Release artifacts**:
   - `PasswordMonitor-1.0-signed.pkg`
   - `PasswordMonitor.app.zip` (dla advanced users)
   - Checksum (SHA256)

**Kryteria akceptacji:**
- [ ] Wszystkie dokumenty gotowe i sprawdzone
- [ ] Release artifacts wygenerowane i przetestowane
- [ ] GitHub Release utworzony (jeśli open-source) lub wewnętrzna dystrybucja gotowa

**Czas:** 2 dni

---

## 8. Timeline Summary

| Faza | Czas | Deliverable |
|------|------|-------------|
| **Faza 0: Research & Prototyping** | 2 tygodnie | Go/No-Go decision |
| **Faza 1: MVP - Core Monitoring** | 4 tygodnie | Functional monitoring app (internal beta) |
| **Faza 2: Enhanced Diagnostics** | 3 tygodnie | Log analysis + automatic issue detection |
| **Faza 3: Automated Repair** | 4 tygodnie | Guided repair workflows |
| **Faza 4: Polish & Distribution** | 2 tygodnie | Production-ready notarized app + installer |
| **TOTAL** | **15 tygodni** (~3.5 miesiąca) | Production release |

---

## 9. Resource Requirements

### 9.1. Developer Time
- **1 Full-time Swift/macOS developer** (Principal level)
- Część czasu może być dedykowana research (Stack Overflow, Apple Forums, reverse engineering)

### 9.2. Tools & Infrastructure
- **Xcode 15+** (najnowsza wersja)
- **macOS 14 Sonoma** (development machine)
- **Apple Developer Account** ($99/rok) – dla code signing i notarization
- **Test hardware:**
  - Mac AD-bound do test domain
  - Access do test Active Directory (Windows Server lub Azure AD DS)

### 9.3. External Dependencies
- Brak zewnętrznych bibliotek (pure Apple frameworks)
- Opcjonalnie: SwiftLint (code quality)

---

## 10. Risk Register & Mitigations

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|-----------|
| **PrivilegedHelper complexity** | High | High | Start early (Milestone 3.1), dedykować extra time, fallback: manual instructions |
| **OSLog parsing requires FDA** | Medium | Medium | Komunikować użytkownikowi konieczność FDA w onboarding |
| **Shell commands API changes** | Low | High | Unit testy z mockami, wrappery dla shell commands |
| **AD configuration varies** | Medium | Medium | Testować na 2-3 różnych AD environments, dodać fallback logic |
| **Apple blocking XPC in future** | Low | Critical | Monitor Apple updates, przygotować plan B (manual workflows only) |

---

## 11. Success Metrics (Post-Launch)

### 11.1. Technical Metrics
- **Detection accuracy:** >90% detected issues są prawdziwe (nie false positives)
- **Repair success rate:** >80% guided repairs kończy się sukcesem
- **Performance:** CPU usage < 5% idle, < 20% podczas health check
- **Stability:** Zero crashes w production (tracked via crash reports)

### 11.2. User Metrics
- **Adoption rate:** >50% target użytkowników instaluje aplikację w 3 miesiące
- **Helpdesk ticket reduction:** -40% tickets związanych z hasłami AD
- **User satisfaction:** NPS > 40 (survey po 1 miesiącu użycia)

### 11.3. Business Metrics
- **Time saved:** ~30 min/ticket * 40% reduction = X hours/month saved
- **ROI:** (Time saved * hourly rate) > Development cost w 6 miesięcy

---

## 12. Post-Launch Roadmap (Future Enhancements)

### v1.1 (3 miesiące po launch)
- [ ] Support dla Entra ID (Azure AD Join) obok klasycznego AD
- [ ] Integracja z Company Portal (jeśli MDM zostanie wdrożone później)
- [ ] Slack/Teams webhook notifications dla IT admins

### v1.2 (6 miesięcy po launch)
- [ ] Machine Learning model (CoreML) zamiast rule-based classifier
- [ ] Predictive analytics: "Your password will likely desync in 3 days" (based on patterns)
- [ ] Self-healing: automatyczne repair bez user interaction (za zgodą użytkownika)

### v2.0 (12 miesięcy po launch)
- [ ] Full MDM integration (dla organizacji które wdrożą MDM)
- [ ] Cloud dashboard dla IT admins (agregacja statusów floty)
- [ ] Compliance reporting (audit trail zmian haseł)

---

## 13. Appendix A: Development Environment Setup

### 13.1. Xcode Project Structure
```
PasswordMonitor/
├── PasswordMonitor/               # Main app target
│   ├── App/
│   │   ├── PasswordMonitorApp.swift
│   │   └── AppDelegate.swift
│   ├── Views/
│   │   ├── MenuBarView.swift
│   │   ├── DiagnosticsView.swift
│   │   ├── RepairView.swift
│   │   └── SettingsView.swift
│   ├── ViewModels/
│   │   ├── DiagnosticsViewModel.swift
│   │   └── RepairViewModel.swift
│   ├── Models/
│   │   ├── ADStatus.swift
│   │   ├── FileVaultStatus.swift
│   │   └── KerberosStatus.swift
│   ├── Services/
│   │   ├── ADHealthMonitor.swift
│   │   ├── FileVaultMonitor.swift
│   │   ├── KerberosMonitor.swift
│   │   ├── LogAnalyzer.swift
│   │   └── ShellExecutor.swift
│   ├── Utilities/
│   │   ├── ErrorClassifier.swift
│   │   └── IssueDetector.swift
│   └── Resources/
│       ├── Assets.xcassets
│       └── Info.plist
├── PasswordMonitorHelper/         # XPC Service target
│   ├── main.swift
│   ├── PrivilegedHelper.swift
│   └── Info.plist
└── PasswordMonitorTests/          # Unit tests
    └── ...
```

### 13.2. Git Workflow
- **Main branch:** Production-ready code
- **Develop branch:** Integration branch
- **Feature branches:** `feature/milestone-X.Y`
- **Pull Requests:** Required for merge to develop
- **Tagging:** `v1.0.0`, `v1.0.1`, etc.

### 13.3. CI/CD (opcjonalne)
- **GitHub Actions** lub **GitLab CI**:
  - Build on every commit
  - Run unit tests
  - Run SwiftLint
  - Archive and notarize on tag push

---

## 14. Appendix B: Testing Strategy

### 14.1. Unit Tests
- **ShellExecutor:** Mock shell output, test parsing logic
- **ErrorClassifier:** Test classification accuracy (dataset: 100 samples)
- **IssueDetector:** Test detection logic (all 10 issue types)

**Coverage target:** >70%

### 14.2. Integration Tests
- **ADHealthMonitor + real AD:** Test on actual AD-bound Mac
- **FileVaultMonitor:** Test with FV enabled/disabled
- **KerberosMonitor:** Test with valid/invalid TGT

### 14.3. UI Tests (opcjonalne)
- **XCUITest:**
  - Test menu bar interaction
  - Test Diagnostics view rendering
  - Test Settings persistence

### 14.4. Manual Testing Checklist (przed każdym release)
- [ ] Fresh install na czystym Macu
- [ ] Test wszystkich 10 issue scenarios
- [ ] Test repair workflows (success + failure cases)
- [ ] Test permissions (FDA, XPC authorization)
- [ ] Test na różnych macOS versions (14.0, 14.2, 14.5)

---

## 15. Conclusion & Next Steps

### 15.1. Immediate Actions
1. **Approve plan:** Review i akceptacja przez stakeholders
2. **Setup environment:** Xcode, test hardware, Apple Developer Account
3. **Kick-off Faza 0:** Start Research & Prototyping (Milestone 0.1)

### 15.2. Key Decision Points
- **End of Faza 0:** Go/No-Go decision (czy projekt feasible)
- **End of Faza 1:** MVP Review (czy podstawowy monitoring działa poprawnie)
- **End of Faza 3:** Beta testing (czy repair workflows są bezpieczne)

### 15.3. Communication Plan
- **Weekly status updates:** Progress report dla stakeholders
- **Biweekly demos:** Live demo nowych features
- **Post-launch retrospective:** Lessons learned

---

**Plan gotowy do wdrożenia. Powodzenia w budowie Password Monitor!** 🚀🔐