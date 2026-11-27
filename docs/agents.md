# Agenti: Claude Code e Codex

## Regole e memoria: chi legge cosa

Ogni regola sta in un solo livello. I livelli più specifici aggiungono o restringono, non ridefiniscono.

| Livello | Cosa ci va | Nell'archivio | Claude Code | Codex |
|---|---|---|---|---|
| Generale | come lavori, valido ovunque | `global/claude/CLAUDE.md` | `~/.claude/CLAUDE.md` (collegato) | `~/.codex/AGENTS.md`, scritto da engramma |
| Workspace | regole del cliente | `workspaces/<ws>/AGENTS.md` | importato da `<ws>/.claude/CLAUDE.md` | letto se avviato nella cartella del workspace |
| Repo, del team | istruzioni committate nel repo | — | `CLAUDE.md` del repo | `AGENTS.md` o `CLAUDE.md` del repo |
| Repo, tue | note personali su un repo | `repo-notes/<repo>.md` | `CLAUDE.local.md`, che le importa | per istruzione (vedi [Codex](#codex)) |
| Memoria | quello che Claude impara lavorando | `memory/` | memoria automatica | — |

Avvia l'agente nella cartella del workspace per lavorare su più repo, o dentro un repo per lavorare solo su quello.

> [!TIP]
> Claude Code non modifica un file raggiunto tramite collegamento. Per cambiare `AGENTS.md` o un file di `repo-files/` con Claude, indicagli il file nell'archivio. Le note di `repo-notes/` passano per questo da un `CLAUDE.local.md` che le importa.

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

> [!NOTE]
> Due punti che la documentazione di Claude Code non chiarisce. Primo: se, avviato dentro un repo, Claude legge anche `<ws>/.claude/CLAUDE.md`, cioè le regole del workspace. Secondo: se legge le skill in `<repo>/.agents/skills/`, dove engramma collega le skill di un repo. Codex le legge.

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

Se `codex` è in `global/requires.txt` ed è installato, `eng setup` prepara Codex:

- scrive `~/.codex/AGENTS.md` dalle regole generali. Codex non segue gli `@import`, quindi le regole vengono copiate per intero. Si aggiunge la regola "leggi le istruzioni del repo in cui lavori, `CLAUDE.local.md` compreso". Succede solo se `links.txt` collega un file a `${CLAUDE_HOME}/CLAUDE.md`. Un `AGENTS.md` scritto a mano non viene mai toccato;
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

`eng integrations` mostra le integrazioni attive con lo stato del programma, di Claude e di Codex, e il comando del commento per quelle incomplete. Un'integrazione non elencata non viene né controllata né usata, anche se installata.
