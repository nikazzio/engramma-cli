# native-memory

## Purpose

Preservare l'uso della memoria nativa di Claude mentre Engramma ne conserva e sincronizza i contenuti.

## Requirements

### Requirement: Continuità della memoria nativa

Engramma MUST permettere a Claude di continuare a leggere e aggiornare la propria memoria nativa senza richiedere una seconda registrazione manuale dei ricordi.

#### Scenario: Memoria aggiornata da Claude

- **WHEN** Claude aggiorna una memoria correttamente collegata all'archivio
- **THEN** l'aggiornamento è disponibile nell'archivio per il normale salvataggio

### Requirement: Acquisizione verificata

Engramma MUST verificare backup e contenuti acquisiti prima di sostituire una cartella locale con un collegamento. File diversi già presenti MUST fermare l'acquisizione senza sovrascriverli.

#### Scenario: Prima memoria creata dopo la sincronizzazione

- **WHEN** viene acquisita una nuova cartella nativa locale priva di conflitti
- **THEN** il collegamento viene creato solo dopo la verifica dei contenuti e resta disponibile un backup

#### Scenario: Copia fallita o contenuto diverso

- **WHEN** il backup o la copia non riesce oppure un file di destinazione contiene dati diversi
- **THEN** Engramma segnala il problema e mantiene disponibile la cartella originale

### Requirement: Recuperabilità delle interruzioni

Engramma MUST conservare l'originale e rendere riconoscibile un'acquisizione interrotta. Se la creazione del collegamento fallisce, MUST ripristinare la cartella oppure indicare dove è conservata.

#### Scenario: Interruzione durante la creazione del collegamento

- **WHEN** l'acquisizione viene interrotta dopo lo spostamento dell'originale
- **THEN** l'originale resta recuperabile e l'esecuzione successiva segnala l'acquisizione incompleta

### Requirement: Prove isolate

Le prove di acquisizione e sincronizzazione MUST usare dati fittizi e configurazioni isolate dalle memorie reali.

#### Scenario: Simulazione di errore di copia

- **WHEN** viene eseguita una prova che forza un errore o un'interruzione
- **THEN** vengono coinvolti solo archivi e memorie fittizie dell'ambiente di prova
