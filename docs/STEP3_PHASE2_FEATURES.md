# Step 3 — Phase 2 del roadmap (Feature avanzate)

## Contesto

Dopo aver risolto i bug (Step 1) e migliorato la UX (Step 2), questo step implementa le feature avanzate previste nella Phase 2 del roadmap in IDEA.md: monitoraggio sistema, rimozione app, cleanup browser, e analisi disco avanzata.

---

## 1. Monitoraggio sistema (CPU/RAM)

**Nuovi file:**
- `RicCleanMyMac/Services/SystemMonitor.swift`
- `RicCleanMyMac/Models/SystemStats.swift`
- `RicCleanMyMac/Views/SystemMonitorView.swift`

**Descrizione:** Aggiungere una sezione "System Monitor" nella sidebar con visualizzazione in tempo reale di CPU e RAM.

**Implementazione:**
- Usare `ProcessInfo.processInfo` per memoria fisica totale
- Usare `host_statistics64` (Mach API) per memoria usata/libera
- Usare `host_processor_info` (Mach API) per carico CPU
- Timer con intervallo configurabile (default: 2 secondi) per aggiornamento
- Il timer si ferma quando la view non è visibile (`onAppear`/`onDisappear`)
- Grafici in tempo reale con `Chart` framework (macOS 13+) o gauge custom

**Principi da rispettare (da IDEA.md):**
- Nessun background process: il monitoraggio si attiva solo quando la view è visibile
- Complete shutdown: il timer si ferma quando l'app viene chiusa
- On-demand: nessun polling quando la vista non è attiva

**Modello dati:**
```swift
struct SystemStats {
    let cpuUsage: Double          // 0.0 - 100.0
    let memoryTotal: UInt64       // bytes
    let memoryUsed: UInt64        // bytes
    let memoryFree: UInt64        // bytes
    var memoryUsagePercentage: Double
}
```

---

## 2. Rimozione sicura applicazioni

**Nuovi file:**
- `RicCleanMyMac/Services/AppUninstaller.swift`
- `RicCleanMyMac/Models/InstalledApp.swift`
- `RicCleanMyMac/Views/AppUninstallerView.swift`

**Descrizione:** Permettere la rimozione sicura di applicazioni con pulizia dei file residui (cache, preferences, application support).

**Implementazione:**
- Scansionare `/Applications` per le app installate (`.app` bundles)
- Per ogni app, identificare i file residui in:
  - `~/Library/Application Support/{bundle-id}/`
  - `~/Library/Caches/{bundle-id}/`
  - `~/Library/Preferences/{bundle-id}.plist`
  - `~/Library/Logs/{bundle-id}/`
  - `~/Library/Containers/{bundle-id}/` (per app sandboxed)
- Mostrare dimensione totale app + residui
- Conferma obbligatoria prima della rimozione
- Non permettere rimozione di app di sistema (whitelist di esclusione)

**Modello dati:**
```swift
struct InstalledApp: Identifiable {
    let id: UUID
    let name: String
    let bundleIdentifier: String
    let path: String
    let size: Int64
    let icon: NSImage?
    let residualFiles: [ResidualFile]
    var totalSize: Int64  // app + residui
}

struct ResidualFile: Identifiable {
    let id: UUID
    let path: String
    let size: Int64
    let type: ResidualType  // cache, preferences, support, logs, containers
}
```

**Sicurezza:**
- Whitelist di app non rimuovibili: Safari, Finder, App Store, System Preferences, ecc.
- Doppia conferma per app > 1GB
- Log di tutte le operazioni di rimozione

---

## 3. Cleanup browser

**Nuovi file:**
- `RicCleanMyMac/Services/BrowserCleaner.swift`
- `RicCleanMyMac/Models/BrowserData.swift`
- `RicCleanMyMac/Views/BrowserCleanupView.swift`

**Descrizione:** Pulizia opzionale di cache, cookies e cronologia dei browser principali.

**Browser supportati:**
- Safari
- Google Chrome
- Firefox
- Microsoft Edge
- Brave

**Dati pulibili (per browser):**
- Cache (sempre sicuro)
- Cookies (con warning — logout da tutti i siti)
- Cronologia (con warning — irreversibile)

**Path dei dati per browser:**
```
Safari:
  Cache:   ~/Library/Caches/com.apple.Safari/
  Cookies: ~/Library/Cookies/
  History: ~/Library/Safari/History.db

Chrome:
  Cache:   ~/Library/Caches/Google/Chrome/
  Profile: ~/Library/Application Support/Google/Chrome/Default/
  Cookies: .../Cookies
  History: .../History

Firefox:
  Profile: ~/Library/Application Support/Firefox/Profiles/
  Cache:   ~/Library/Caches/Firefox/Profiles/
```

**Sicurezza:**
- Checkbox separata per ogni tipo di dato (cache, cookies, history)
- Cache selezionata di default, cookies e history deselezionati
- Warning prominente per cookies e cronologia
- Verificare che il browser non sia in esecuzione prima della pulizia

---

## 4. Analisi disco avanzata con drill-down

**Nuovi file:**
- `RicCleanMyMac/Views/DiskAnalysisView.swift`

**File da modificare:**
- `RicCleanMyMac/Services/DiskAnalyzer.swift`
- `RicCleanMyMac/Models/SpaceUsageItem.swift`

**Descrizione:** Evoluzione della SpaceUsageView attuale con capacità di drill-down nelle sotto-directory.

**Implementazione:**
- Rendere `SpaceUsageItem` navigabile (click per esplorare sotto-directory)
- Aggiungere breadcrumb per la navigazione gerarchica
- Visualizzazione a treemap o barre impilate per le dimensioni relative
- Identificare automaticamente i file più grandi (top 10/20)
- Possibilità di aprire file/cartelle nel Finder con doppio click

**Modello dati aggiornato:**
```swift
struct SpaceUsageItem: Identifiable {
    let id: UUID
    let name: String
    let path: String
    let size: Int64
    let isDirectory: Bool
    let children: [SpaceUsageItem]?  // nil = non ancora scansionato, [] = vuoto
    var formattedSize: String
    var displayName: String
}
```

---

## 5. Nuova sezione sidebar

**File:** `RicCleanMyMac/Views/MainView.swift`

Aggiungere le nuove sezioni alla sidebar:

```swift
enum NavigationSection: String, CaseIterable {
    case dashboard = "Dashboard"
    case cleanup = "Cleanup"
    case diskAnalysis = "Disk Analysis"
    case appUninstaller = "Applications"
    case browserCleanup = "Browsers"
    case systemMonitor = "System Monitor"
}
```

---

## Ordine di implementazione

1. Monitoraggio sistema CPU/RAM (indipendente, buon punto di partenza)
2. Analisi disco avanzata con drill-down (evoluzione di codice esistente)
3. Rimozione sicura applicazioni (feature complessa, richiede molta sicurezza)
4. Cleanup browser (richiede test specifici per ogni browser)
5. Aggiornamento sidebar con tutte le nuove sezioni

## Verifica

- **System Monitor:** verificare che i valori CPU/RAM corrispondano a Activity Monitor, e che il timer si fermi quando la view non è visibile
- **Disk Analysis:** verificare drill-down in directory con molti file, performance con directory grandi
- **App Uninstaller:** testare con un'app di test (non di sistema), verificare che tutti i residui vengano trovati
- **Browser Cleanup:** testare con Safari e Chrome (i più comuni), verificare che il browser venga controllato se in esecuzione
- **Sidebar:** verificare navigazione fluida tra tutte le sezioni

## Note

- Tutte le feature devono rispettare i principi di IDEA.md: no auto-delete, conferma obbligatoria, no background processes
- Il System Monitor è l'unica eccezione parziale (usa un timer) ma solo quando la view è attiva
- La rimozione app è la feature più delicata — richiede testing approfondito prima del rilascio
