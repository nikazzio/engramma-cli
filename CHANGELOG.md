# Changelog

## Unreleased

- Inventario per file della memoria di Claude nel log e riepilogo per operazione. Anche il salvataggio manuale registra il commit locale e l’esito dell’invio.
- Setup guidato con scelta di archivio, agenti e memoria, anteprima e sincronizzazione facoltativa del primo workspace.
- Scelta locale fra Claude Code, Codex e Copilot CLI con `eng setup --agents` e riepilogo con `eng agents`.
- Copilot CLI riceve istruzioni personali, skill e contesto dei repo. La memoria di Claude può essere disattivata senza perdere i ricordi già collegati.
- Controlli e anteprime locali, `check --refresh` per verificare il remoto, aiuto per comando e codici distinti per errori d’uso.
- Percorsi salvati in modo atomico, blocco per archivio e scollegamento che dimentica l’archivio dopo il successo.
- `--prune` conserva i branch con commit solo locali.
- Output statico con `--plain`, Unicode comune di default e opzione `--non-interactive`.
- Documentazione navigabile con Zensical e workflow GitHub Pages.
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
- `eng` parte anche senza archivio: mostra la schermata, segnala il problema e controlla i comandi `eng`, mise e git. `eng setup` crea i comandi anche in quel caso.
- `eng init` crea un archivio nuovo da un esempio. `eng setup <indirizzo o cartella>` collega o clona un archivio esistente. Entrambi ricordano il percorso e non sovrascrivono niente.
- L'output standard è più breve: una riga per sezione con l'icona dell'esito, i problemi elencati una sola volta in fondo con il comando che li risolve, il logo solo con `eng setup`. `-v` mantiene l'output completo. Icone `nerd`, `unicode` o `ascii` con `ENGRAMMA_ICONS` o `icons` nel file di configurazione.
- I collegamenti `eng` ed `engramma` che puntano a un'altra copia del programma sono un solo problema, con il comando per riportarli qui.
