# Engramma

Engramma tiene le regole, gli appunti, la memoria e la configurazione degli agenti di sviluppo (Claude Code e Codex) in un **archivio Git privato**, e li collega ai tuoi progetti su ogni computer. Su un computer nuovo bastano due comandi per ritrovare tutto com'era.

```mermaid
flowchart LR
    A[(archivio Git privato)] -- eng sync --> C1[computer 1]
    A -- eng sync --> C2[computer 2]
    C1 -- eng save --> A
    C2 -- eng save --> A
```

## Requisiti

Linux o WSL, Bash 5+, Python 3.10+, Git, OpenSSH e [mise](https://mise.jdx.dev), che installa i programmi di ogni progetto. Se mise manca, `eng setup` propone di installarlo.

## Installazione

```bash
git clone <url di questo repo> ~/engramma            # il programma
git clone <url del tuo archivio> ~/engramma-dati     # i tuoi dati
mkdir -p ~/.config/engramma && echo ~/engramma-dati > ~/.config/engramma/archive
~/engramma/bin/sync.sh setup -n                      # mostra cosa cambierebbe
~/engramma/bin/sync.sh setup                         # collega eng e la configurazione
```

> [!WARNING]
> `setup` cambia la configurazione del computer: `~/.claude/CLAUDE.md`, le impostazioni di Claude Code e di Codex, i plugin. Lancia prima `setup -n`. Non sovrascrive mai un file diverso: lo segnala.

Non hai ancora un archivio? [Primi passi](docs/getting-started.md) spiega come crearlo.

## Comandi essenziali

| Comando | Cosa fa |
|---|---|
| `eng` | Controlla il computer e i workspace, senza cambiare niente |
| `eng sync <ws>` | Scarica l'archivio, aggiorna i repo del workspace, salva e invia note e memoria |
| `eng save <ws>` | Salva e invia subito un workspace, senza toccare i repo |
| `eng sync global` / `eng save global` | Lo stesso per la configurazione del computer |
| `eng tools` | Programmi installati e mancanti; `eng tools install` li installa con mise |
| `eng integrations` | Integrazioni degli agenti attive (boost, caveman, code-review-graph, repomix) |

Elenco completo in [Comandi](docs/commands.md).

## Documentazione

[Indice](docs/README.md) · [Primi passi](docs/getting-started.md) · [Concetti](docs/concepts.md) · [Problemi comuni](docs/troubleshooting.md) · [Contribuire](CONTRIBUTING.md) · [Licenza MIT](LICENSE)
