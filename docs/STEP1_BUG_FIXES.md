# Step 1 — Fix bug critici e completare Phase 1

## Contesto

Il progetto ha una base funzionante ma presenta bug di sicurezza, limitazioni nello scan (solo 3 directory aggregate senza granularità), e UX incompleta (errori non mostrati, dead code). L'obiettivo è risolvere i problemi critici e completare la Phase 1 del roadmap definita in IDEA.md.

---

## 1. Fix `isPathSafe` — vulnerabilità path traversal

**File:** `RicCleanMyMac/Utilities/FileManager+Extensions.swift` (linea 66)

**Problema:** `hasPrefix` senza trailing `/` permette match falsi positivi. Es. se la whitelist contiene `/Users/test`, anche `/Users/test.cache` verrebbe considerato sicuro.

**Fix:** Normalizzare i path e aggiungere `/` alla fine del path consentito prima del confronto. Gestire anche il caso in cui il path sia esattamente uguale alla directory consentita.

```swift
func isPathSafe(_ path: String, within allowedDirectories: [String]) -> Bool {
    let normalizedPath = URL(fileURLWithPath: path).standardized.path

    for allowedDir in allowedDirectories {
        let normalizedAllowed = URL(fileURLWithPath: allowedDir).standardized.path
        if normalizedPath == normalizedAllowed || normalizedPath.hasPrefix(normalizedAllowed + "/") {
            return true
        }
    }
    return false
}
```

---

## 2. Fix `/Applications` vs `~/Applications`

**File:** `RicCleanMyMac/Services/DiskAnalyzer.swift` (linea 59)

**Problema:** `homeURL.appendingPathComponent("Applications")` punta a `~/Applications` (quasi sempre vuota). Le app dell'utente sono in `/Applications`.

**Fix:** Sostituire con `URL(fileURLWithPath: "/Applications")`.

---

## 3. Scan granulare — sotto-directory nella cache e nei log

**File:** `RicCleanMyMac/Services/FileScanner.swift`

**Problema:** Lo scan ritorna UN solo `CleanupItem` per directory intera (es. tutta `~/Library/Caches` come unico item da 2GB). Il cleanup cancella l'intera directory, potenzialmente rompendo app in esecuzione.

**Fix:** Modificare `scanCacheDirectory()` e `scanLogDirectory()` per enumerare le sotto-directory/file di primo livello, creando un `CleanupItem` per ciascuna app/sotto-directory. Le directory temporanee (`NSTemporaryDirectory`) restano aggregate perché non hanno sotto-directory significative per l'utente.

---

## 4. Aggiungere scan Downloads e Trash

**File:** `RicCleanMyMac/Services/FileScanner.swift`

**Problema:** `CleanupType.downloads` e `.trash` esistono nel model `CleanupItem.swift` ma `FileScanner` non li usa mai.

**Fix:**
- Aggiungere `scanDownloadsDirectory()` → `~/Downloads`, scan per file/cartella di primo livello
- Aggiungere `scanTrashDirectory()` → `~/.Trash`, scan per file/cartella di primo livello
- Chiamarli in `scanForCleanupItems()`

**File:** `RicCleanMyMac/Services/CleanupService.swift` (linee 17-36)

Aggiungere Downloads e Trash alla whitelist `allowedDirectories`:
```swift
let homeURL = URL(fileURLWithPath: NSHomeDirectory())
directories.append(homeURL.appendingPathComponent("Downloads").path)
directories.append(homeURL.appendingPathComponent(".Trash").path)
```

---

## 5. Fix icone duplicate

**File:** `RicCleanMyMac/Models/CleanupItem.swift` (linee 33, 37)

**Problema:** `CleanupType.temp` e `.trash` usano entrambi `"trash.fill"`.

**Fix:** Cambiare icona di `.temp` a `"clock.arrow.circlepath"` (semantica per file temporanei).

---

## 6. Rimuovere dead code

**File:** `RicCleanMyMac/Views/ConfirmationDialog.swift` (linee 4-42)

**Problema:** La struct `ConfirmationDialog` non è mai utilizzata. L'app usa `CleanupConfirmationModifier` (linee 45+).

**Fix:** Rimuovere la struct `ConfirmationDialog`, mantenere solo `CleanupConfirmationModifier` e la relativa View extension.

---

## 7. Mostrare errori di cleanup all'utente

**File:** `RicCleanMyMac/Views/CleanupView.swift` (linee 108-109)

**Problema:** Se il cleanup fallisce (validation error), c'è solo un commento `// Show error if validation failed`. L'utente non riceve feedback.

**Fix:** Aggiungere `@State var showError = false` e un `.alert` che informa l'utente quando `cleanup()` ritorna `nil`.

---

## 8. Aggiungere Scan e Select All nella CleanupView

**File:** `RicCleanMyMac/Views/CleanupView.swift`

**Problemi:**
- Flow spezzato: lo scan parte solo dalla Dashboard, bisogna cambiare tab per vedere i risultati
- Manca un bottone "Select All" (c'è solo "Deselect All")

**Fix:**
- Aggiungere un bottone Scan nella `EmptyStateView` e nella toolbar della `CleanupView`
- Aggiungere un bottone "Select All" accanto a "Deselect All" nella bottom toolbar

---

## Ordine di implementazione

1. Fix `isPathSafe` (sicurezza critica)
2. Fix `/Applications` in DiskAnalyzer
3. Scan granulare in FileScanner (cache e logs per sotto-directory)
4. Scan Downloads e Trash + aggiornamento whitelist
5. Fix icona `.temp` duplicata
6. Rimuovere dead code `ConfirmationDialog`
7. Alert errori in CleanupView
8. Bottone Scan + Select All in CleanupView

## Verifica

- Aprire il progetto in Xcode e verificare che compili senza errori (⌘B)
- Testare lo scan: verificare che vengano mostrate le sotto-directory della cache e dei log, non più un singolo item aggregato
- Testare il cleanup: selezionare una sotto-directory piccola, confermare, verificare alert di conferma e successo
- Verificare che Downloads e Trash compaiano nei risultati dello scan
- Verificare che `/Applications` mostri la dimensione corretta in SpaceUsageView
- Verificare che errori di cleanup mostrino un alert all'utente
