# Claude Code, Codex e Copilot CLI

## Scegli gli agenti per questa postazione

```bash
eng setup --agents codex,copilot --dry-run
eng setup --agents codex,copilot
eng agents
```

L’elenco sostituisce la scelta precedente. Puoi usare un solo agente o `none`. La scelta vale per l’archivio selezionato su questo computer. I nuovi archivi partono senza agenti e con la memoria disattivata. Gli archivi precedenti conservano le impostazioni esistenti finché chiedi di cambiarle.

Per usare Claude e sincronizzarne la memoria, esegui `eng setup --agents claude --claude-memory on`. Per fermare la sincronizzazione, usa `eng setup --claude-memory off`. Engramma sostituisce i collegamenti alla memoria con copie locali indipendenti e lascia nell’archivio i ricordi già salvati. Le nuove modifiche alla memoria restano fuori dai commit di `eng sync` ed `eng save` su questo computer. L’archivio Git conserva la memoria già inclusa nei commit. Su una postazione con la memoria disattivata, quei file restano nell’archivio senza essere collegati a Claude.

Disattivando un agente, i suoi collegamenti gestiti diventano copie locali. Le regole e le skill condivise nel repo restano disponibili agli agenti che le leggono. Le impostazioni già scritte in locale restano sul computer.

## Regole e memoria: chi legge cosa

Ogni regola sta in un solo livello. I livelli più specifici aggiungono o restringono, non ridefiniscono.

| Livello | Cosa ci va | Nell'archivio | Claude Code | Codex |
|---|---|---|---|---|
| Generale | come lavori, valido ovunque | `global/claude/CLAUDE.md` | `~/.claude/CLAUDE.md` (collegato) | `~/.codex/AGENTS.md`, scritto da engramma |
| Workspace | regole del cliente | `workspaces/<ws>/AGENTS.md` | importato da `<ws>/.claude/CLAUDE.md` | letto se avviato nella cartella del workspace |
| Repo, del team | istruzioni committate nel repo | — | `CLAUDE.md` del repo | `AGENTS.md` o `CLAUDE.md` del repo |
| Repo, tue | note personali su un repo | `repo-notes/<repo>.md` | `CLAUDE.local.md`, che le importa | per istruzione (vedi [Codex](#codex)) |
| Memoria | quello che Claude impara lavorando | `memory/` | memoria automatica, con sincronizzazione abilitata | — |

Avvia l'agente nella cartella del workspace per lavorare su più repo, o dentro un repo per lavorare solo su quello.

> **Suggerimento.** Claude Code non modifica un file raggiunto tramite collegamento. Per cambiare `AGENTS.md` o un file di `repo-files/` con Claude, indicagli il file nell'archivio. Le note di `repo-notes/` passano per questo da un `CLAUDE.local.md` che le importa.

## Cosa legge Claude Code all'avvio

Claude Code legge i `CLAUDE.md` della cartella di avvio e di tutte quelle sopra, dalla più esterna alla più interna. La memoria segue il repo Git, o la cartella di avvio fuori da un repo ([documentazione di Claude Code](https://code.claude.com/docs/en/memory)).

**Avvio nella cartella del workspace**, per lavorare su più repo:

```
cd <ws> && claude
│
├── regole        1. ~/.claude/CLAUDE.md                     generali
│                 2. <ws>/.claude/CLAUDE.md                  del workspace
│                    └── @../AGENTS.md
├── memoria       memory/_workspace/MEMORY.md                prime 200 righe
├── skill         ~/.claude/skills/*  +  <ws>/.claude/skills/*
├── impostazioni  ~/.claude/settings.json  <  <ws>/.claude/settings.json
└── quando Claude apre un file in <ws>/<repo>/:
                  <repo>/CLAUDE.md (del team) e <repo>/CLAUDE.local.md (tue)
```

**Avvio dentro un repo**, per lavorare solo su quello:

```
cd <ws>/<repo> && claude
│
├── regole        1. ~/.claude/CLAUDE.md                     generali
│                 2. <ws>/CLAUDE.md, se c'è                  engramma non lo crea
│                 3. <repo>/CLAUDE.md                        del team
│                 4. <repo>/CLAUDE.local.md                  tue
│                    └── @ nota in repo-notes/<repo>.md
├── memoria       memory/<repo>/MEMORY.md                    prime 200 righe
├── skill         ~/.claude/skills/*  +  <repo>/.claude/skills/*
└── impostazioni  ~/.claude/settings.json  <  <repo>/.claude/settings.json
                  <  <repo>/.claude/settings.local.json
```

`<` indica la precedenza: a parità di impostazione vale quella più a destra. Le liste, come i permessi, si sommano ([documentazione](https://code.claude.com/docs/en/settings)).

> **Nota.** Due punti che la documentazione di Claude Code non chiarisce. Primo: se, avviato dentro un repo, Claude legge anche `<ws>/.claude/CLAUDE.md`, cioè le regole del workspace. Secondo: se legge le skill in `<repo>/.agents/skills/`, dove engramma collega le skill di un repo. Codex le legge.

## Skill

| Skill | Nell'archivio | Sul computer | Chi la legge |
|---|---|---|---|
| Generale | `skills/<skill>/SKILL.md` | `~/.claude/skills/<skill>` e `~/.agents/skills/<skill>` | Claude Code e Codex, in ogni progetto |
| Di un repo | `workspaces/<ws>/skills/<repo>/<skill>/SKILL.md` | `<repo>/.agents/skills/<skill>`, escluso dal Git del repo | Codex; Claude vedi la nota sopra |

- **Nuova skill generale:** creala in `skills/<nome>/` dell'archivio, lancia `eng sync global` per collegarla e `eng save global` per inviarla. Claude Code la vede anche a sessione aperta.
- **Skill creata da Claude in `~/.claude/skills/`:** `eng` la segnala come "non versionata". Spostala in `skills/` dell'archivio. Se l'ha installata un altro strumento, aggiungila a `skills-ignore.txt`.
- **Skill tolta dall'archivio:** `eng sync` toglie il suo collegamento. Non tocca le skill che non vengono dall'archivio.
- **Skill di un repo già presente nel repo del team:** `eng` non la collega e lo segnala.

## Plugin e marketplace di Claude Code

| Dove li dichiari | Valgono |
|---|---|
| `enabledPlugins` ed `extraKnownMarketplaces` in `global/claude/settings.json` | per te, in tutti i progetti |
| `workspaces/<ws>/.claude/settings.json` | avviando Claude nella cartella del workspace |
| `.claude/settings.json` committato nel repo | per il team, in quel repo |

Se `claude` è in `global/requires.txt` ed è installato, `eng setup` fa tre cose sui plugin generali:

- registra i marketplace dichiarati e installa i plugin che mancano;
- mostra gli errori di Claude Code;
- segnala i marketplace con l'aggiornamento automatico spento.

Quelli del workspace e del repo li installa Claude Code all'avvio. Un marketplace privato via SSH funziona solo con la chiave caricata nell'agente SSH.

## Codex

Se selezioni Codex ed è installato, `eng setup` prepara la postazione. Per gli archivi precedenti vale anche la dichiarazione di Codex in `global/requires.txt`:

- scrive `~/.codex/AGENTS.md` dalle regole generali. Codex non segue gli `@import`, quindi le regole vengono copiate per intero. Con una scelta esplicita le regole arrivano da `global/AGENTS.md` oppure dalle regole globali di Claude già dichiarate nell’archivio. Codex riceve anche l’indicazione di leggere le regole del workspace e la nota personale locale del repo. Gli archivi precedenti usano la sorgente già dichiarata e mantengono il riferimento a `CLAUDE.local.md`. Un `AGENTS.md` scritto a mano non viene mai toccato;
- collega le skill generali anche in `~/.agents/skills`;
- imposta `project_doc_fallback_filenames = ["CLAUDE.md"]`, così Codex legge i `CLAUDE.md` dei repo senza `AGENTS.md`;
- spegne `shell_snapshot`, così Codex usa la versione di node di ogni cartella;
- installa i plugin di `global/codex/plugins.txt`.

```
# global/codex/plugins.txt
plugin <plugin@marketplace>  <sorgente del marketplace>   installato da engramma
skill  <nome>                # comando per installarla     controllato, con il comando
path   <percorso>            # comando per installarlo     controllato, con il comando
```

Codex legge al massimo 32 KB di istruzioni: `eng` avvisa quando le regole generali, del workspace o del team superano il limite. La configurazione di Codex contiene anche dati del computer (cartelle fidate, hook approvati): engramma aggiunge solo le voci elencate sopra.

## Copilot CLI

Quando selezioni Copilot, Engramma prepara le istruzioni personali da `global/AGENTS.md` o dalle regole generali già presenti nell’archivio. Se hai scritto a mano le istruzioni di Copilot, il setup ti segnala il conflitto e conserva il tuo file. Le skill generali sono collegate nella cartella personale di Copilot. Le istruzioni e le skill già versionate dal team restano in uso.

Nel repo, le istruzioni personali gestite chiedono a Copilot di consultare le regole del workspace e la nota del repo. Questi due riferimenti sono esclusi dal Git del progetto. Una sessione nuova carica le istruzioni personali aggiornate. [Istruzioni di Copilot CLI](https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/add-custom-instructions) · [Skill di Copilot CLI](https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/add-skills)

Copilot Memory resta gestita da GitHub per account e repository. Per vederne lo stato in una sessione interattiva usa `/memory`. [Memoria di Copilot](https://docs.github.com/en/copilot/how-tos/use-copilot-agents/copilot-memory/manage-for-yourself)

## Integrazioni

Le integrazioni sono strumenti che cambiano il lavoro degli agenti. Sono attive solo se elencate in `global/integrations.txt`:

```
# <integrazione>     # come installarla
boost                # curl -fsSL https://boost.jfrog.com/install.sh | bash, poi boost init --claude
code-review-graph    # mise use -g code-review-graph
```

| Integrazione | Cosa controlla `eng` | Cosa cambia in engramma |
|---|---|---|
| `boost` | il programma, i suoi hook in Claude Code, `~/.codex/BOOST.md` | aggiunge le istruzioni di boost a `~/.codex/AGENTS.md` |
| `caveman` | il plugin in Claude Code, `~/.codex/caveman` | — |
| `code-review-graph` | il programma, il server MCP in Claude Code e in Codex | segnala il server MCP mancante, con il comando per registrarlo |
| `repomix` | un plugin `@repomix` in Claude Code, la skill `repomix-explorer` per Codex | — |

`eng integrations` mostra lo stato di ciascuna integrazione dichiarata. Per Claude installato controlla anche che i plugin richiesti siano abilitati. Se manca qualcosa, mostra il comando scritto nel commento di quella voce.
