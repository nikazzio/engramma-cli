# Changelog

## Unreleased

- Programma separato dall'archivio privato, con scelta dell'archivio per postazione o per singola esecuzione.
- Memoria nativa Claude con acquisizione verificata, backup e gestione delle interruzioni.
- Salvataggio e invio ritentabile dei commit locali.
- Test isolati e strumenti per CI e release.
- `eng <ws>` ed `eng global` controllano senza cambiare niente; `global` si usa come un workspace con check, sync, save e detach.
- `eng tools` e `eng tools install`: programmi di mise e di `requires.txt`, con mise obbligatorio e `mise.toml` per workspace.
- `eng integrations` e `global/integrations.txt`: boost, caveman, code-review-graph e repomix attivi solo se elencati.
- I backup stanno in `~/.local/state/engramma/backup/`, fuori dall'archivio.
- I nomi dei comandi, `global` e `all` non si possono usare come nomi di workspace.
- Un file del team non viene sostituito da un file personale con lo stesso nome; copie e backup falliti non cancellano più il file locale; i conflitti dei file uniti si scelgono per chiave; un `settings.json` svuotato non svuota l'archivio.
- Documentazione riorganizzata in `docs/`.
- `eng tools` mostra gli errori di mise e suggerisce l’attivazione con l’eseguibile presente sul computer.
- `eng integrations` allinea i simboli alle colonne e verifica lo stato dei plugin di Claude installato.
- Il completamento Bash e zsh segue gli argomenti del comando. `--version` funziona anche dopo le altre opzioni.
- Lo scollegamento segnala copie e sostituzioni fallite. La guida descrive come verificare lo scambio della memoria fra due installazioni.
