# Domande frequenti

## Workspace o repo?

Un **workspace** è un cliente o un progetto e raggruppa più **repo**. I comandi `sync`, `save`, `detach` e `list` lavorano sui workspace. Vedi [Concetti](concepts.md).

## Dove metto i segreti?

Non nell'archivio. Un file personale con valori sensibili si versiona con variabili al posto dei valori. I valori vanno in un file locale, escluso dal Git del repo con `excludes.txt`:

```yaml
# workspaces/acme/repo-files/api/compose.yaml
environment:
  API_KEY: "${API_KEY}"
```

```
# workspaces/acme/excludes.txt
api .env
```

`eng` controlla che le variabili senza valore predefinito dei file Docker Compose di `repo-files/` siano presenti e non vuote nel `.env` del repo. Mostra solo i nomi, mai i valori.

## Scollegare engramma

```bash
eng detach all -n   # cosa verrebbe sostituito
eng detach all      # ogni collegamento diventa una copia indipendente
```

Quando `detach all` termina con successo, i progetti su questo computer usano copie locali di note e memoria. Puoi conservare l’archivio per usarlo su altri computer. Se compare un errore, conserva l’archivio e controlla il percorso indicato. `eng detach <ws>` scollega un solo workspace e `eng detach global` scollega la configurazione del computer.

`detach all` toglie anche i comandi `eng` ed `engramma` e i completamenti. Dimentica anche il percorso dell’archivio scelto dopo uno scollegamento riuscito. I repo clonati, i plugin installati, le voci aggiunte a Codex, i log e i backup restano disponibili.

Per ricollegare tutto dopo `detach all`, riporta nell’archivio le modifiche fatte alle copie locali. Esegui `~/engramma/bin/sync.sh setup ~/engramma-dati` per collegare di nuovo l’archivio e ripristinare il comando, poi `eng sync` per ricollegare i workspace presenti.

## Come aggiorno il programma?

```bash
git -C ~/engramma pull --ff-only
```

`eng sync` aggiorna solo l'archivio, mai il programma.

## Il completamento con Tab non funziona

`eng setup` collega il completamento di bash in `~/.local/share/bash-completion/completions/`, che bash carica da solo. Per zsh lo collega in `~/.local/share/zsh/site-functions/`: quella cartella deve stare in `fpath` prima di `compinit`.

## Limiti

- Linux e WSL. macOS non è verificato.
- Le cartelle di workspace e repo non possono contenere spazi. L'archivio sì.
- I file uniti funzionano solo con JSON, e un array conta come un valore unico.
