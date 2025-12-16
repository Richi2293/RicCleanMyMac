# Istruzioni per Creare il Progetto Xcode

## Prerequisiti

- macOS 12.0 o superiore
- Xcode 14.0 o superiore
- Swift 5.7 o superiore

## Creazione Progetto Xcode

### Passo 1: Creare Nuovo Progetto

1. Apri Xcode
2. File → New → Project
3. Seleziona **macOS** → **App**
4. Clicca **Next**

### Passo 2: Configurare Progetto

1. **Product Name**: `RicCleanMyMac`
2. **Team**: Seleziona il tuo team (opzionale)
3. **Organization Identifier**: `com.yourname` (o il tuo dominio)
4. **Bundle Identifier**: Verrà generato automaticamente
5. **Interface**: **SwiftUI**
6. **Language**: **Swift**
7. **Storage**: **None** (non usiamo Core Data)
8. **Include Tests**: ✅ (opzionale ma consigliato)

9. Clicca **Next**
10. Scegli la cartella `/Users/riccardo/development/github/RicClean` come location
11. **IMPORTANTE**: Deseleziona "Create Git repository" se hai già inizializzato Git
12. Clicca **Create**

### Passo 3: Sostituire File Generati

1. **Elimina** i file generati automaticamente da Xcode:
   - `RicCleanMyMacApp.swift` (se presente nella root)
   - `ContentView.swift` (se presente)
   - `Assets.xcassets` (opzionale, puoi mantenerlo per le icone)

2. **Aggiungi** i file esistenti al progetto:
   - Clicca destro sulla cartella `RicCleanMyMac` nel navigator
   - Seleziona "Add Files to RicCleanMyMac..."
   - Naviga nella cartella `RicCleanMyMac` del progetto
   - Seleziona tutte le sottocartelle: `App`, `Views`, `Services`, `Models`, `Utilities`
   - Assicurati che "Copy items if needed" sia **deselezionato**
   - Assicurati che "Create groups" sia **selezionato**
   - Clicca **Add**

### Passo 4: Configurare Deployment Target

1. Seleziona il target `RicCleanMyMac` nel navigator
2. Vai alla tab **General**
3. In **Minimum Deployments**, imposta **macOS** a **12.0**

### Passo 5: Configurare Info.plist

1. Se il progetto usa un `Info.plist` moderno (Xcode 14+), le informazioni potrebbero essere nel target settings
2. Se hai un file `Info.plist` separato, sostituiscilo con quello nella root del progetto
3. Verifica che le seguenti chiavi siano presenti:
   - `LSMinimumSystemVersion`: `12.0`
   - `CFBundleShortVersionString`: `1.0`
   - `CFBundleVersion`: `1`

### Passo 6: Configurare Signing (Opzionale)

1. Vai alla tab **Signing & Capabilities**
2. Se hai un Apple Developer Account:
   - Seleziona il tuo **Team**
   - Xcode genererà automaticamente il provisioning profile
3. Se non hai un account:
   - L'app funzionerà solo in modalità debug
   - Per distribuzione, vedi [TESTING_AND_DEPLOYMENT.md](TESTING_AND_DEPLOYMENT.md)

### Passo 7: Verificare Struttura

La struttura finale nel navigator di Xcode dovrebbe essere:

```
RicCleanMyMac
├── App
│   ├── RicCleanMyMacApp.swift
│   └── AppDelegate.swift
├── Views
│   ├── MainView.swift
│   ├── DashboardView.swift
│   ├── CleanupView.swift
│   └── ConfirmationDialog.swift
├── Services
│   ├── CleanupService.swift
│   ├── FileScanner.swift
│   └── DiskAnalyzer.swift
├── Models
│   ├── CleanupItem.swift
│   └── DiskSpace.swift
├── Utilities
│   ├── FileManager+Extensions.swift
│   └── ByteCountFormatter+Extensions.swift
├── Assets.xcassets (opzionale)
└── Info.plist
```

### Passo 8: Build e Run

1. Seleziona lo schema **RicCleanMyMac** nella toolbar
2. Seleziona **My Mac** come destinazione
3. Premi **⌘R** per compilare ed eseguire
4. L'app dovrebbe avviarsi correttamente

## Risoluzione Problemi Comuni

### Errore: "Cannot find type 'X' in scope"

- Verifica che tutti i file siano stati aggiunti al target `RicCleanMyMac`
- Controlla che non ci siano file duplicati
- Pulisci il build folder: Product → Clean Build Folder (⇧⌘K)

### Errore: "Missing required module"

- Verifica che il deployment target sia impostato correttamente
- Riavvia Xcode

### L'app non si avvia

- Verifica che `RicCleanMyMacApp.swift` sia il file principale (deve avere `@main`)
- Controlla che non ci siano errori di compilazione nella console

### Permessi filesystem

- La prima volta che l'app accede al filesystem, macOS potrebbe chiedere permessi
- Vai in System Settings → Privacy & Security → Full Disk Access
- Aggiungi l'app se necessario (solo per test avanzati)

## Prossimi Passi

Una volta che l'app compila e funziona:

1. Testa le funzionalità base (scansione, pulizia)
2. Verifica che la conferma di eliminazione funzioni
3. Testa la chiusura completa dell'app
4. Consulta [TESTING_AND_DEPLOYMENT.md](TESTING_AND_DEPLOYMENT.md) per il testing completo

