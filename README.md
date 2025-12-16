# RicCleanMyMac

Un'applicazione macOS open source per ottimizzare e pulire il sistema Mac, simile a "Clean My Mac" ma completamente gratuita e open source.

## Caratteristiche

- **Pulizia Sicura**: Scansione e pulizia di file temporanei, cache e log di sistema
- **Controllo Totale**: Nessuna eliminazione automatica - ogni operazione richiede conferma esplicita
- **Architettura Leggera**: Nessun processo in background, chiusura completa quando l'app viene terminata
- **Interfaccia Moderna**: UI moderna basata su SwiftUI con sidebar navigation

## Requisiti

- macOS 12.0 (Monterey) o superiore
- Xcode 14.0 o superiore (per compilare da sorgente)

## Installazione

### Da Sorgente

1. Clona il repository:
```bash
git clone https://github.com/tuousername/RicCleanMyMac.git
cd RicCleanMyMac
```

2. Apri il progetto in Xcode:
```bash
open RicCleanMyMac.xcodeproj
```

3. Seleziona lo schema "RicCleanMyMac" e premi ⌘R per compilare ed eseguire

## Uso

1. Avvia l'applicazione
2. Clicca su "Scansione" nel dashboard per trovare file da pulire
3. Seleziona gli elementi che vuoi eliminare
4. Clicca su "Pulizia" e conferma l'operazione
5. L'app mostrerà lo spazio liberato

## Sicurezza

- L'app **NON elimina** alcun file senza la tua conferma esplicita
- Ogni operazione di pulizia richiede un dialog di conferma
- Validazione rigorosa dei path per prevenire eliminazioni accidentali
- Whitelist di directory sicure

## Sviluppo

### Struttura Progetto

```
RicCleanMyMac/
├── App/              # Entry point e AppDelegate
├── Views/            # Interfaccia SwiftUI
├── Services/         # Logica di business
├── Models/           # Modelli di dati
└── Utilities/        # Funzioni di supporto
```

### Build per Release

1. Seleziona lo schema "RicCleanMyMac"
2. Product → Scheme → Edit Scheme → Build Configuration: Release
3. Product → Archive
4. Esporta l'app dall'Organizer

## Contribuire

I contributi sono benvenuti! Per maggiori informazioni, consulta [CONTRIBUTING.md](CONTRIBUTING.md) (da creare).

## Licenza

[Da definire: MIT, Apache 2.0, o GPL]

## Note

- L'app è in fase di sviluppo attivo
- Tutte le funzionalità sono soggette a modifiche
- La sicurezza e la stabilità sono prioritarie

