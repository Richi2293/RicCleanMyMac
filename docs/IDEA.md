# RicCleanMyMac - Idea del Progetto

## Panoramica

RicCleanMyMac è un'applicazione macOS open source progettata per ottimizzare e pulire il sistema Mac, simile al famoso "Clean My Mac" ma completamente gratuita e open source.

## Obiettivo

L'obiettivo principale di RicCleanMyMac è fornire agli utenti Mac uno strumento potente e affidabile per:
- Liberare spazio su disco
- Migliorare le prestazioni del sistema
- Mantenere il Mac pulito e organizzato
- Monitorare l'utilizzo delle risorse di sistema

## Caratteristiche Principali

### 1. Pulizia del Sistema
- **File temporanei**: Rimozione automatica di file temporanei e cache non necessarie
- **Log di sistema**: Pulizia dei file di log che occupano spazio
- **Cache applicazioni**: Gestione e pulizia delle cache delle applicazioni
- **Download**: Analisi e pulizia della cartella Download
- **Cestino**: Svuotamento automatico del cestino

### 2. Analisi Disco
- Visualizzazione dettagliata dello spazio utilizzato
- Identificazione di file e cartelle di grandi dimensioni
- Analisi per tipo di file
- Grafici e visualizzazioni intuitive

### 3. Monitoraggio Sistema
- Monitoraggio utilizzo RAM
- Monitoraggio utilizzo CPU
- Spazio disco disponibile in tempo reale
- Statistiche di sistema

### 4. Pulizia Avanzata
- Rimozione sicura di applicazioni
- Pulizia libreria foto (duplicati, cache)
- Pulizia browser (cache, cookie, cronologia - opzionale)
- Pulizia file di sistema non critici

## Tecnologie

- **Swift**: Linguaggio di programmazione principale
- **SwiftUI**: Framework per l'interfaccia utente moderna e reattiva
- **Combine**: Gestione asincrona e reattiva dei dati
- **Foundation**: Accesso al filesystem e operazioni di sistema

## Architettura

Il progetto seguirà un'architettura modulare:
- **Views**: Interfaccia utente SwiftUI
- **Services**: Logica di business e servizi di pulizia
- **Models**: Modelli di dati
- **Utilities**: Funzioni di supporto e estensioni

## Principi di Sviluppo

1. **Sicurezza**: Validazione rigorosa prima di qualsiasi operazione di eliminazione
2. **Controllo Utente**: Nessuna eliminazione automatica - ogni operazione richiede azione esplicita e conferma dell'utente
3. **Trasparenza**: Mostrare sempre all'utente cosa verrà eliminato prima della conferma
4. **Architettura Leggera**: App on-demand senza processi in background - chiusura completa quando l'app viene terminata
5. **Performance**: Operazioni asincrone per non bloccare l'interfaccia
6. **Privacy**: Nessun dato viene inviato a server esterni
7. **Open Source**: Codice completamente aperto e verificabile

## Requisiti Critici

### Sicurezza e Controllo Utente
- **Nessuna eliminazione automatica**: L'app NON elimina o modifica alcun file senza un'azione esplicita dell'utente
- **Conferma obbligatoria**: Ogni operazione di pulizia richiede una conferma esplicita tramite dialog/alert
- **Solo scansione di default**: Di default l'app scansiona e mostra risultati, senza eseguire alcuna azione
- **Whitelist directory**: Validazione rigorosa dei path con lista directory sicure consentite

### Architettura Leggera
- **Nessun processo in background**: Quando l'app viene chiusa, tutti i processi terminano completamente
- **Nessun daemon o agent**: Non vengono utilizzati LaunchAgents o LaunchDaemons
- **Nessun monitoraggio continuo**: L'app è completamente on-demand, senza polling o monitoraggio continuo
- **Chiusura completa**: Implementazione di gestione ciclo vita per garantire terminazione completa senza residui

## Roadmap

### Fase 1 - MVP (Minimum Viable Product)
- [ ] Interfaccia base con dashboard
- [ ] Scansione file temporanei e cache
- [ ] Pulizia base del sistema
- [ ] Visualizzazione spazio liberato

### Fase 2 - Funzionalità Avanzate
- [ ] Analisi dettagliata del disco
- [ ] Rimozione applicazioni
- [ ] Monitoraggio sistema in tempo reale
- [ ] Pulizia browser

### Fase 3 - Ottimizzazioni
- [ ] Pulizia automatica programmata
- [ ] Notifiche intelligenti
- [ ] Personalizzazione regole di pulizia
- [ ] Export report di pulizia

## Licenza

Il progetto sarà rilasciato con licenza open source (da definire: MIT, Apache 2.0, o GPL).

## Contribuire

RicCleanMyMac è un progetto open source e accoglie contributi dalla community. Per maggiori informazioni su come contribuire, consulta il file CONTRIBUTING.md (da creare).

## Note

- Il progetto è attualmente in fase di sviluppo iniziale
- Tutte le funzionalità sono soggette a modifiche durante lo sviluppo
- La sicurezza e la stabilità sono prioritarie rispetto alle nuove funzionalità

