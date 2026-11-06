# archive-sync

## Purpose

Conservare il contesto nell'archivio privato e trasferirlo fra computer senza perdere modifiche locali.

## Requirements

### Requirement: Salvataggio circoscritto

Engramma MUST creare il commit dei soli dati dell'area richiesta, distinguendo il commit locale dall'esito dell'invio. L'invio Git può comprendere altri commit già presenti sullo stesso branch e questo comportamento MUST essere documentato.

#### Scenario: Due workspace modificati

- **WHEN** l'utente salva un workspace mentre un altro contiene modifiche non salvate
- **THEN** il nuovo commit contiene solo le modifiche del workspace richiesto e l'esito distingue salvataggio locale e invio

### Requirement: Invio ritentabile

Engramma MUST permettere di ritentare l'invio dei commit locali dopo un push fallito anche senza nuove modifiche, senza duplicare il commit già creato.

#### Scenario: Push fallito dopo il commit

- **WHEN** l'utente ripete il salvataggio dopo un push fallito e non ha modificato altri file
- **THEN** Engramma ritenta l'invio e conserva il commit originale

### Requirement: Ricezione senza perdita di modifiche

Engramma MUST ricevere gli aggiornamenti compatibili senza sovrascrivere modifiche locali divergenti; in caso di conflitto MUST segnalare che l'aggiornamento non è stato applicato.

#### Scenario: Aggiornamento su un secondo computer

- **WHEN** un computer sincronizza un archivio pulito dopo l'invio dall'altro computer
- **THEN** riceve i dati salvati nell'archivio condiviso

#### Scenario: Modifiche incompatibili fra computer

- **WHEN** la memoria locale contiene modifiche incompatibili con quelle ricevute
- **THEN** il contenuto locale resta disponibile e Engramma segnala l'aggiornamento non applicato
