## Purpose

Descrivere le capacità effettivamente supportate da ogni agente prima di condividere istruzioni o memorie.

## ADDED Requirements

### Requirement: Supporto dichiarato per agente

Engramma MUST dichiarare separatamente per ogni agente il supporto a istruzioni, note e memorie native, distinguendo ciò che è verificato da ciò che è proposto.

#### Scenario: Anteprima senza integrazione nativa

- **WHEN** per un agente è disponibile soltanto un'anteprima di testo
- **THEN** Engramma non la presenta come caricamento automatico o sincronizzazione della memoria nativa

### Requirement: Condivisione esplicita e verificata

Engramma MUST introdurre la condivisione con Codex e poi Copilot solo dopo ricognizione delle funzionalità supportate e prove isolate, conservando le memorie native Claude.

#### Scenario: Aggiunta di un agente

- **WHEN** viene proposta un'integrazione con un nuovo agente
- **THEN** prima dell'attivazione sono specificati contenuti condivisi, contenuti specifici dell'agente e prove necessarie
