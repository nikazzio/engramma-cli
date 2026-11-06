# archive-management

## Purpose

Permettere di usare e aggiornare Engramma separatamente dall'archivio personale privato.

## Requirements

### Requirement: Archivio identificabile

Engramma MUST permettere di scegliere l'archivio e rendere riconoscibile quello utilizzato prima delle operazioni sui dati.

#### Scenario: Archivio separato dal programma

- **WHEN** viene selezionato un archivio in una cartella diversa dal programma
- **THEN** Engramma usa i dati di quell'archivio e rende riconoscibile la cartella selezionata

#### Scenario: Percorso con spazi

- **WHEN** l'archivio selezionato si trova in un percorso contenente spazi
- **THEN** Engramma usa l'intero percorso senza interpretarlo come più argomenti

### Requirement: Archivio non valido

Engramma MUST fermare le operazioni sui dati quando l'archivio selezionato manca o non è riconosciuto come archivio supportato, indicando il problema senza crearne uno implicitamente o ripiegare su un altro archivio.

#### Scenario: Cartella selezionata inesistente

- **WHEN** l'utente richiede una sincronizzazione verso un archivio che non esiste
- **THEN** Engramma segnala il problema senza creare cartelle o modificare altri archivi

### Requirement: Predefinito locale e scelta temporanea

Engramma MUST risolvere l'archivio nell'ordine: scelta della singola esecuzione, ambiente, predefinito locale e configurazione legacy. La scelta temporanea MUST lasciare invariato il predefinito e i percorsi MUST essere letti come testo letterale.

#### Scenario: Archivio temporaneo diverso dal predefinito

- **WHEN** l'utente sceglie un archivio per una sola esecuzione mentre esiste un predefinito locale
- **THEN** il comando usa l'archivio scelto e il predefinito resta invariato per l'esecuzione successiva

### Requirement: Controllo senza modifiche

La modalità di controllo MUST lasciare invariati dati di lavoro, configurazioni e collegamenti. Eventuali aggiornamenti dei riferimenti Git remoti MUST essere distinti dall'applicazione degli aggiornamenti ai dati.

#### Scenario: Controllo di un archivio da sistemare

- **WHEN** l'utente esegue il controllo e mancano collegamenti o sono presenti modifiche locali
- **THEN** Engramma riporta i problemi senza creare collegamenti, acquisire memorie o salvare modifiche

### Requirement: Aggiornamenti indipendenti

Engramma MUST separare l'aggiornamento del programma dalla sincronizzazione dei dati privati.

#### Scenario: Aggiornamento del programma

- **WHEN** viene aggiornata soltanto la versione di Engramma
- **THEN** il contenuto dell'archivio e delle memorie native resta invariato

### Requirement: Distribuzione pubblica priva di dati personali

La distribuzione pubblica di Engramma MUST contenere programma, documentazione generica ed esempi fittizi, senza dati o cronologia dell'archivio privato.

#### Scenario: Preparazione del repository pubblico

- **WHEN** viene preparato il repository destinato alla pubblicazione
- **THEN** contenuto e cronologia sono verificati per escludere i dati personali e la cronologia privata
