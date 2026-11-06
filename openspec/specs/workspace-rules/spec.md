# workspace-rules

## Purpose

Organizzare progetti e istruzioni per workspace mantenendo utilizzabile lo stesso archivio su postazioni diverse.

## Requirements

### Requirement: Identità condivisa e posizione locale

Engramma MUST conservare nell'archivio l'identità del workspace e i suoi progetti, consentendo una posizione del workspace diversa su ciascun computer.

#### Scenario: Cartelle diverse fra computer

- **WHEN** due computer configurano lo stesso workspace in cartelle differenti
- **THEN** entrambi usano gli stessi dati condivisi senza imporre all'altro il proprio percorso locale

### Requirement: Istruzioni del workspace

Engramma MUST rendere disponibili le istruzioni comuni ai progetti del workspace attraverso i meccanismi supportati dall'agente, preservando le istruzioni già presenti nei repository.

#### Scenario: Istruzioni personali e di progetto presenti insieme

- **WHEN** Engramma configura un progetto che contiene già istruzioni versionate dal team
- **THEN** mantiene quelle istruzioni e rende disponibili quelle personali senza sovrascriverle

### Requirement: Contesto personale esterno alla storia del team

Engramma MUST mantenere il contesto personale nell'archivio privato ed escludere dalla storia dei repository del team gli elementi locali che introduce.

#### Scenario: Collegamenti e note personali nel progetto

- **WHEN** vengono predisposti collegamenti o istruzioni personali nel progetto
- **THEN** questi elementi non vengono aggiunti ai contenuti versionati del repository del team
