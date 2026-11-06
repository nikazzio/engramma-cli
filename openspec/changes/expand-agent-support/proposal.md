# Estendere il supporto agli agenti

## Why

Le istruzioni personali possono servire a più agenti, ma le loro memorie native hanno capacità e regole differenti. Occorre verificare le integrazioni prima di promettere una condivisione automatica.

## What Changes

- Consolidare prima il caricamento reale della memoria Claude.
- Valutare Codex e poi Copilot con prove e configurazioni dedicate.
- Dichiarare distintamente supporto a istruzioni, note e memorie native.

## Capabilities

### New Capabilities

- `agent-support`: descrizione esplicita delle capacità verificate per agente.

### Modified Capabilities

Nessuna.

## Impact

Proposta aperta: l'implementazione richiede ricognizione delle fonti ufficiali e prove isolate. Le configurazioni Codex già presenti non certificano la sincronizzazione della sua memoria. Nessuna migrazione dei dati reali viene attivata.
