# Formato dell'archivio

L'archivio è un repo Git privato. `eng` lo accetta se è la radice di un repo e contiene `workspaces/`.

```
archivio/
├── workspaces/
│   └── <ws>/                 un workspace (vedi sotto)
├── global/                   configurazione del computer (vedi sotto)
├── skills/
│   └── <skill>/SKILL.md      skill generali per gli agenti selezionati
└── skills-ignore.txt         skill installate da altri strumenti, da non segnalare
```

## Regole comuni dei file `.txt`

- Una voce per riga, campi separati da spazi.
- Le righe vuote e quelle che iniziano con `#` sono ignorate.
- Un `#` dopo i campi apre un commento. In alcuni file il commento ha un ruolo, indicato sotto.

## Workspace: `workspaces/<ws>/`

| File o cartella | Obbligatorio | Contenuto | Sul computer |
|---|---|---|---|
| `repos.txt` | sì | `<cartella> <url git> [branch principale]` | ogni repo clonato in `<cartella del ws>/<cartella>` |
| `location.txt` | no | cartella sotto `~/workspace`, per esempio `clienti/acme` | cartella del workspace |
| `AGENTS.md` | no | regole del workspace per gli agenti selezionati | collegato in `<ws>/AGENTS.md` |
| `.claude/` | no | `CLAUDE.md` (di solito solo `@../AGENTS.md`), `settings.json` | collegata in `<ws>/.claude` |
| `docs/` | no | appunti del workspace | collegata in `<ws>/docs` |
| `mise.toml` | no | programmi e versioni del workspace (vedi [Programmi](tools.md)) | collegato in `<ws>/mise.toml` |
| `requires.txt` | no | `<comando> [facoltativo]  # a cosa serve` | controllato |
| `hosts.txt` | no | un hostname per riga | controllato nel file hosts (su WSL quello di Windows) |
| `excludes.txt` | no | `<repo> <file>`: file solo locali, come `.env` | aggiunti a `.git/info/exclude` del repo |
| `repo-notes/<repo>.md` | no | note personali su un repo | importate da `<repo>/CLAUDE.local.md` |
| `repo-files/<repo>/<file>` | no | file personali, come `compose.yaml` | collegati in `<repo>/<file>` |
| `skills/<repo>/<skill>/` | no | skill di un solo repo | collegate in `<repo>/.agents/skills/<skill>` |
| `memory/_workspace/` | no | memoria di Claude Code per la cartella del workspace | collegata nella cartella della memoria |
| `memory/<repo>/` | no | memoria di Claude Code per un repo | collegata nella cartella della memoria |
| `README.md` | no | descrizione del workspace, per te | — |

Regole sui nomi:

- **Workspace:** `[a-z0-9][a-z0-9._-]*`, esclusi i [nomi riservati](commands.md#nomi-riservati).
- **Cartella di un repo:** libera, tranne `docs`, `.claude` e `AGENTS.md`, che sono degli appunti. Un repo `org/docs` si clona per esempio come `org-docs`.
- **Skill:** `[a-z0-9][a-z0-9-]*`.
- **Branch principale:** se `repos.txt` non lo indica, è `develop` quando esiste, altrimenti `main`. Per un repo con `master` va scritto.

Dove finisce la cartella del workspace, in quest'ordine: `--path` (ricordato in `~/.config/engramma/paths`), poi la cartella già ricordata, poi `~/workspace/<location.txt>`, poi `~/workspace/<ws>`. Le cartelle di workspace e repo non possono contenere spazi.

## Global: `global/`

| File | Contenuto |
|---|---|
| `agents-defaults.txt` | Valori iniziali per le postazioni senza una scelta salvata. Un nuovo archivio usa `none off`. |
| `AGENTS.md` | Regole generali per Codex e Copilot CLI. Per usarle anche in Claude, dichiarale in `links.txt`. |
| `links.txt` | `<file in global/> <destinazione> [unisci]`: cosa portare sul computer e dove |
| `requires.txt` | `<comando> [facoltativo]  # come installarlo`: programmi che mise non gestisce. Il commento diventa il comando proposto nel riepilogo. |
| `integrations.txt` | `<integrazione>  # come installarla`: integrazioni degli agenti attive (vedi [Agenti](agents.md#integrazioni)) |
| `mise/config.toml` | programmi di tutti i giorni, di solito collegato in `~/.config/mise/config.toml` |
| `claude/` | `CLAUDE.md` (regole generali), `settings.json` (impostazioni e plugin di Claude Code) |
| `codex/plugins.txt` | plugin e skill di Codex (vedi [Agenti](agents.md#codex)) |
| altri | qualsiasi file citato in `links.txt` |

### `links.txt`

```
# <file in global/>      <destinazione>                        [unisci]
claude/CLAUDE.md          ${CLAUDE_HOME}/CLAUDE.md
claude/settings.json      ${CLAUDE_HOME}/settings.json          unisci
mise/config.toml          ${XDG_CONFIG_HOME}/mise/config.toml
```

- I segnaposto ammessi sono `${HOME}`, `${CLAUDE_HOME}`, `${CODEX_HOME}`, `${COPILOT_HOME}` e `${XDG_CONFIG_HOME}`. I collegamenti di un agente esplicitamente disattivato vengono saltati.
- Senza terzo campo il file è **collegato**: ogni modifica sul computer finisce nell'archivio.
- Con `unisci` il file è **unito**: resta una copia sul computer e viene unito all'archivio voce per voce. Funziona solo con file JSON. Vedi [Più computer](multi-computer.md#file-uniti).

## Percorsi negli appunti

Un percorso assoluto (`/home/<utente>/...`) vale solo sul computer dove è stato scritto. Negli appunti, nelle impostazioni e negli `@import` si scrive `~/...` o un percorso relativo. `eng` segnala ogni percorso assoluto sotto `/home` o `/Users`, con la forma `~/` da usare. Non controlla le memorie, scritte da Claude, né i file uniti.
