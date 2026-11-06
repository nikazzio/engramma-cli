# Engramma

Engramma conserva istruzioni, note e memoria nativa di Claude in un archivio Git privato e le rende disponibili ai progetti su più computer. Il programma e l'archivio sono indipendenti.

## Requisiti

Linux o WSL, Bash 5+, Python 3.10+, Git, OpenSSH e strumenti GNU standard. Bash e zsh sono supportati per i completamenti. Le prove automatiche usano dati fittizi; l'integrazione effettiva con Claude va verificata con la [prova manuale](docs/manual-test.md).

## Avvio

Da questo checkout, scegli un archivio privato Git che contenga `workspaces/`:

```bash
./bin/sync.sh --data-dir /percorso/archivio list
./bin/sync.sh --data-dir /percorso/archivio sync demo --dry-run
```

Per l'uso quotidiano, salva il percorso letterale nel file `~/.config/engramma/archive`, poi esegui `./bin/sync.sh setup`: collega `eng` e i completamenti al programma. `XDG_CONFIG_HOME` permette di scegliere un'altra configurazione locale. [Guida completa](docs/guida.md).

## Comandi essenziali

| Comando | Risultato |
|---|---|
| `eng` | Controlla postazione e workspace presenti |
| `eng list` | Elenca workspace e progetti |
| `eng sync demo` | Riceve i dati, prepara i collegamenti e aggiorna i repo compatibili |
| `eng save demo` | Crea il commit del workspace e invia i commit del branch |
| `eng detach demo` | Trasforma i collegamenti personali in copie indipendenti |

`--data-dir` precede il comando e vale per una sola esecuzione. La sincronizzazione aggiorna l'archivio; il programma si aggiorna esplicitamente dal proprio checkout. File diversi e divergenze vengono segnalati senza sovrascriverli.

## Sviluppo

```bash
make test                 # Bats, con archivi temporanei
make lint                 # ShellCheck e sintassi zsh
python3 scripts/devtools.py install
make check-tools          # workflow, specifiche OpenSpec e scansione segreti
make dist                 # archivio sorgenti e SHA256SUMS locali
```

Servono Bats, ShellCheck, zsh e Make. Gli strumenti aggiuntivi sono fissati con checksum e installati soltanto in `.tools/`. OpenSpec usa il suo eseguibile autonomo; il programma non richiede Node.

`bin/`, `lib/`, `completions/` contengono il programma; `tests/` le prove; `examples/archive/` dati fittizi; `openspec/` il contratto e le proposte. [Contributi](CONTRIBUTING.md), [release](docs/releases.md), [licenza MIT](LICENSE).
