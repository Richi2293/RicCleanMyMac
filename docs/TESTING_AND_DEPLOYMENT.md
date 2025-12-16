# Testing e Deployment - RicCleanMyMac

## Testing Durante lo Sviluppo

### 1. Testing in Xcode

#### Run e Debug
- **Run (⌘R)**: Avvia l'app in modalità debug
- **Test (⌘U)**: Esegue tutti gli unit test
- **Debug Console**: Visualizza log e errori durante l'esecuzione

#### Breakpoint e Debugging
- Impostare breakpoint per debuggare il flusso di esecuzione
- Utilizzare `print()` o `os_log` per logging durante lo sviluppo
- Verificare che le operazioni filesystem funzionino correttamente

#### Testing Manuale
1. **Test Scansione**:
   - Avviare l'app
   - Cliccare su "Scansione" nel dashboard
   - Verificare che vengano trovati file temporanei, cache e log
   - Verificare che le dimensioni siano calcolate correttamente

2. **Test Pulizia**:
   - Dopo la scansione, selezionare alcuni elementi
   - Cliccare su "Pulizia"
   - Verificare che appaia il dialog di conferma
   - Verificare che i file vengano eliminati solo dopo conferma
   - Verificare che l'app si aggiorni correttamente dopo la pulizia

3. **Test Sicurezza**:
   - Verificare che non vengano eliminati file fuori dalle directory consentite
   - Verificare che la whitelist funzioni correttamente
   - Tentare di eliminare file di sistema critici (non dovrebbe essere possibile)

4. **Test Chiusura**:
   - Avviare una scansione
   - Chiudere l'app durante la scansione
   - Verificare che tutti i processi terminino completamente
   - Verificare con Activity Monitor che non ci siano processi residui

### 2. Unit Testing

#### Struttura Test
```
RicCleanMyMacTests/
├── FileScannerTests.swift
├── CleanupServiceTests.swift
├── DiskAnalyzerTests.swift
└── FileManagerExtensionsTests.swift
```

#### Test da Implementare

**FileScannerTests**:
- Test scansione directory esistente
- Test scansione directory non esistente
- Test calcolo dimensioni corretto
- Test enumerazione file nascosti

**CleanupServiceTests**:
- Test validazione path (whitelist)
- Test rifiuto eliminazione fuori whitelist
- Test eliminazione corretta dopo conferma
- Test gestione errori durante eliminazione

**DiskAnalyzerTests**:
- Test calcolo spazio disco disponibile
- Test formattazione dimensioni

### 3. Testing con Dati Realistici

#### Preparazione Ambiente Test
1. Creare directory di test con file temporanei simulati
2. Utilizzare file di dimensioni note per verificare calcoli
3. Testare con diverse dimensioni di cache e log

#### Test di Performance
- Testare scansione di directory grandi (migliaia di file)
- Verificare che l'UI rimanga responsiva durante scansioni lunghe
- Testare memoria durante operazioni intensive

### 4. Testing su Diversi macOS

#### Versioni Supportate
- macOS 12.0 (Monterey)
- macOS 13.0 (Ventura)
- macOS 14.0 (Sonoma)
- macOS 15.0 (Sequoia) - se disponibile

#### Test Cross-Version
- Verificare compatibilità SwiftUI su tutte le versioni
- Testare permessi filesystem su diverse versioni
- Verificare comportamento UI su diverse risoluzioni

## Deployment e Distribuzione

### 1. Build per Release

#### Configurazione Xcode
1. **Selezionare Schema Release**:
   - Product → Scheme → Edit Scheme
   - Impostare Build Configuration su "Release"

2. **Ottimizzazioni**:
   - Abilitare compiler optimizations
   - Rimuovere debug symbols se necessario
   - Verificare che non ci siano `print()` statements di debug

3. **Archivio**:
   - Product → Archive
   - Attendere completamento build
   - Xcode Organizer si aprirà automaticamente

### 2. Code Signing e Notarizzazione

#### Code Signing (Opzionale ma Consigliato)
Per distribuire l'app fuori dall'App Store, è necessario firmare il codice:

1. **Apple Developer Account**:
   - Iscrizione Developer Program ($99/anno) per distribuzione fuori App Store
   - Oppure Developer ID per distribuzione diretta

2. **Configurazione Signing**:
   - Xcode → Target → Signing & Capabilities
   - Selezionare team developer
   - Xcode gestirà automaticamente il provisioning

3. **Notarizzazione**:
   - Richiesta da macOS Catalina+ per app non da App Store
   - Processo automatico tramite Xcode Organizer
   - Verifica sicurezza da parte di Apple (24-48 ore)

#### Alternative per Open Source
- **Notarizzazione Opzionale**: Gli utenti possono bypassare con `xattr -cr` se necessario
- **Distribuzione Source Code**: Gli utenti possono compilare direttamente da Xcode
- **GitHub Releases**: Distribuire `.zip` con istruzioni per compilazione

### 3. Metodi di Distribuzione

#### Opzione 1: GitHub Releases (Consigliato per Open Source)

**Vantaggi**:
- Gratuito
- Integrato con repository Git
- Facile per utenti tecnici
- Nessun costo aggiuntivo

**Processo**:
1. Creare release su GitHub:
   ```
   git tag v1.0.0
   git push origin v1.0.0
   ```
2. GitHub → Releases → Draft new release
3. Caricare `.zip` dell'app compilata
4. Aggiungere changelog e istruzioni

**Formato Distribuzione**:
```
RicCleanMyMac-v1.0.0.zip
├── RicCleanMyMac.app
└── README.txt (istruzioni installazione)
```

**Istruzioni per Utenti**:
- Scaricare `.zip`
- Estrarre `.app`
- Spostare in `/Applications`
- Prima esecuzione: click destro → Apri (per bypassare Gatekeeper)

#### Opzione 2: Homebrew Cask (Per Utenti Tecnici)

**Vantaggi**:
- Installazione facile per utenti Homebrew
- Aggiornamenti automatici
- Standard per app macOS open source

**Processo**:
1. Creare formula Homebrew Cask
2. Aggiungere a `homebrew-cask` repository
3. Mantenere aggiornata con nuove versioni

**Formula Esempio**:
```ruby
cask 'riccleanmymac' do
  version '1.0.0'
  sha256 '...'
  
  url "https://github.com/tuousername/RicCleanMyMac/releases/download/v#{version}/RicCleanMyMac-#{version}.zip"
  name 'RicCleanMyMac'
  homepage 'https://github.com/tuousername/RicCleanMyMac'
  
  app 'RicCleanMyMac.app'
end
```

#### Opzione 3: Mac App Store (Futuro)

**Requisiti**:
- Apple Developer Account ($99/anno)
- Review process Apple
- Conformità linee guida App Store
- Sandboxing (potrebbe limitare accesso filesystem)

**Vantaggi**:
- Distribuzione ufficiale
- Aggiornamenti automatici
- Maggiore fiducia utenti

**Svantaggi**:
- Review process lungo
- Restrizioni sandbox
- 30% commissione su vendite (non applicabile se gratuito)

### 4. Creazione DMG (Disk Image)

#### Per Distribuzione Professionale

**Strumenti**:
- `create-dmg` (tool CLI)
- `DropDMG` (app GUI)
- Script personalizzato

**Struttura DMG**:
```
RicCleanMyMac.dmg
└── RicCleanMyMac.app
    └── Applications (alias)
```

**Processo con create-dmg**:
```bash
# Installare create-dmg
brew install create-dmg

# Creare DMG
create-dmg \
  --volname "RicCleanMyMac" \
  --window-pos 200 120 \
  --window-size 800 400 \
  --icon-size 100 \
  --icon "RicCleanMyMac.app" 200 190 \
  --hide-extension "RicCleanMyMac.app" \
  --app-drop-link 600 185 \
  "RicCleanMyMac-v1.0.0.dmg" \
  "build/"
```

### 5. CI/CD con GitHub Actions

#### Automatizzare Build e Release

**Workflow GitHub Actions**:
```yaml
name: Build and Release

on:
  release:
    types: [created]

jobs:
  build:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v3
      - name: Build
        run: |
          xcodebuild -scheme RicCleanMyMac \
            -configuration Release \
            -archivePath build/RicCleanMyMac.xcarchive \
            archive
      - name: Export
        run: |
          xcodebuild -exportArchive \
            -archivePath build/RicCleanMyMac.xcarchive \
            -exportPath build/export \
            -exportOptionsPlist ExportOptions.plist
      - name: Create DMG
        run: |
          # Script per creare DMG
      - name: Upload Release
        uses: softprops/action-gh-release@v1
        with:
          files: build/RicCleanMyMac.dmg
```

### 6. Versioning

#### Semantic Versioning
- **Major** (1.0.0): Cambiamenti incompatibili
- **Minor** (0.1.0): Nuove funzionalità compatibili
- **Patch** (0.0.1): Bug fixes

#### Info.plist
```xml
<key>CFBundleShortVersionString</key>
<string>1.0.0</string>
<key>CFBundleVersion</key>
<string>1</string>
```

## Checklist Pre-Release

### Funzionalità
- [ ] Tutti i test passano
- [ ] Nessun bug critico conosciuto
- [ ] UI testata su diverse risoluzioni
- [ ] Performance accettabili

### Sicurezza
- [ ] Validazione path implementata
- [ ] Whitelist directory funzionante
- [ ] Conferma eliminazione sempre richiesta
- [ ] Nessun file eliminato senza conferma

### Architettura
- [ ] Nessun processo in background
- [ ] Chiusura completa verificata
- [ ] Nessun daemon o agent
- [ ] Memoria gestita correttamente

### Documentazione
- [ ] README.md aggiornato
- [ ] Changelog creato
- [ ] Istruzioni installazione chiare
- [ ] Screenshot o demo video (opzionale)

### Build
- [ ] Build Release funzionante
- [ ] App testata su macOS target
- [ ] Dimensioni app ragionevoli
- [ ] Icona app creata

## Suggerimenti per Distribuzione Open Source

### 1. README Completo
- Descrizione chiara del progetto
- Screenshot dell'app
- Istruzioni installazione dettagliate
- Requisiti di sistema
- Come contribuire

### 2. LICENSE File
- Scegliere licenza appropriata (MIT, Apache 2.0, GPL)
- Aggiungere file LICENSE nella root

### 3. Contributing Guidelines
- Creare CONTRIBUTING.md
- Spiegare come contribuire
- Linee guida per pull request

### 4. Issue Templates
- Template per bug report
- Template per feature request
- Template per domande

### 5. Security Policy
- Creare SECURITY.md
- Spiegare come reportare vulnerabilità
- Processo di disclosure responsabile

## Raccomandazione Finale

Per un progetto open source come RicCleanMyMac, suggerisco:

1. **Fase Iniziale (MVP)**:
   - Distribuzione via GitHub Releases
   - Build manuale per prime versioni
   - Focus su funzionalità e stabilità

2. **Fase di Crescita**:
   - Automatizzare build con GitHub Actions
   - Aggiungere Homebrew Cask per facilità installazione
   - Creare DMG per distribuzione professionale

3. **Fase Maturità**:
   - Considerare Mac App Store se necessario
   - Implementare auto-update mechanism
   - Espandere canali distribuzione

**Approccio Consigliato**: Iniziare con GitHub Releases semplice, poi espandersi gradualmente in base alle necessità della community.

