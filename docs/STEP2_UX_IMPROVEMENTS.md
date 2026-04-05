# Step 2 — Miglioramenti UX

## Contesto

Dopo aver risolto i bug critici dello Step 1, questo step si concentra sul miglioramento dell'esperienza utente: navigazione moderna macOS, feedback visivo migliore, e un'interfaccia più intuitiva.

---

## 1. Migrare sidebar a `NavigationSplitView`

**File:** `RicCleanMyMac/Views/MainView.swift`

**Problema:** La sidebar usa `HSplitView` + `List` con styling manuale per l'evidenziazione dell'item selezionato (`Color.accentColor.opacity(0.2)`). Questo non segue il pattern nativo macOS e produce un'esperienza visiva non standard.

**Fix:** Migrare a `NavigationSplitView` (disponibile da macOS 13+) con `NavigationLink` e `navigationDestination`. Se si vuole mantenere supporto macOS 12, usare `NavigationView` con `SidebarListStyle()` come fallback.

**Vantaggi:**
- Evidenziazione nativa dell'item selezionato
- Animazioni di transizione standard macOS
- Supporto nativo per collapse/expand della sidebar
- Comportamento corretto con Dark Mode

---

## 2. Feedback visivo post-cleanup

**File:** `RicCleanMyMac/Views/CleanupView.swift`

**Problema:** Dopo un cleanup riuscito, l'unico feedback è che gli item scompaiono dalla lista. Non c'è un messaggio che indica quanto spazio è stato liberato.

**Fix:**
- Dopo cleanup riuscito, mostrare un banner/alert con "Freed X MB/GB of disk space"
- Aggiungere un'animazione di fade-out per gli item eliminati
- Mostrare il numero di item eliminati con successo vs totale

---

## 3. Progress indicator durante lo scan

**File:** `RicCleanMyMac/Views/CleanupView.swift`, `DashboardView.swift`

**Problema:** Durante lo scan c'è solo un `ProgressView` circolare generico senza indicazione di avanzamento.

**Fix:**
- Aggiungere uno stato di progresso nel `CleanupService` (es. "Scanning cache...", "Scanning logs...", "Scanning downloads...")
- Mostrare il nome della directory attualmente in fase di scansione
- Opzionale: progress bar determinata se possibile stimare il numero di directory

---

## 4. Ordinamento e filtri nella CleanupView

**File:** `RicCleanMyMac/Views/CleanupView.swift`

**Problema:** Gli item sono mostrati nell'ordine in cui vengono scansionati, senza possibilità di ordinare o filtrare.

**Fix:**
- Aggiungere un picker/segmented control per ordinare per: dimensione (default), nome, tipo
- Aggiungere filtri per `CleanupType` (cache, logs, temp, downloads, trash)
- Mostrare un riepilogo per tipo nella parte superiore (es. "Cache: 1.2GB, Logs: 300MB, Downloads: 5GB")

---

## 5. Migliorare DiskSpaceCard

**File:** `RicCleanMyMac/Views/DashboardView.swift`

**Problema:** La card mostra solo totale/disponibile con una progress bar lineare. È informativa ma poco visiva.

**Fix:**
- Usare un grafico a ciambella (donut chart) per la visualizzazione dello spazio disco
- Aggiungere colori diversi per spazio usato/disponibile/recuperabile
- Mostrare la percentuale di spazio usato in modo più prominente

---

## 6. Conferma cleanup con dettagli

**File:** `RicCleanMyMac/Views/ConfirmationDialog.swift`

**Problema:** Il dialog di conferma mostra solo il numero di item e la dimensione totale. Non elenca gli item specifici.

**Fix:**
- Migrare da `.confirmationDialog` (nativo macOS, limitato) a un `.sheet` custom
- Mostrare la lista degli item selezionati con nome e dimensione
- Aggiungere un warning più visibile per item di grandi dimensioni

---

## Ordine di implementazione

1. Migrare sidebar a `NavigationSplitView` (impatto visivo immediato)
2. Feedback visivo post-cleanup (UX critica)
3. Progress indicator con nome directory durante scan
4. Ordinamento e filtri nella CleanupView
5. Migliorare DiskSpaceCard con donut chart
6. Conferma cleanup con dettagli

## Verifica

- Verificare che la sidebar si comporti come le app native macOS (Mail, Finder)
- Testare il feedback post-cleanup con item di diverse dimensioni
- Verificare che il progress indicator mostri correttamente la directory in scan
- Testare ordinamento e filtri con molti item
- Verificare il donut chart con diverse percentuali di spazio disco
- Testare il dialog di conferma con 1 item, pochi item, e molti item
