# Guida di engramma

Come funziona ogni parte del comando `eng`, con esempi. Per l'uso di tutti i giorni basta il [README](../README.md).

## Archivio e programma

Il programma carica codice e completamenti dal proprio checkout. I dati personali arrivano da un archivio Git con la cartella `workspaces/`; `global/` e `skills/` sono facoltativi. Il percorso viene scelto in quest'ordine: `--data-dir <cartella>` prima del comando, `ENGRAMMA_DATA_DIR`, prima riga di `~/.config/engramma/archive` (sotto `XDG_CONFIG_HOME`, se configurato), infine `ENGRAMMA_DIR` per compatibilità. Il file contiene un percorso letterale, anche con spazi, senza virgolette o comandi shell.

Per impostare il predefinito: `mkdir -p ~/.config/engramma`, poi `printf '%s\n' '/percorso/archivio' > ~/.config/engramma/archive`. Una scelta temporanea non cambia questo valore. Senza selezione, o con un archivio non valido, il comando si ferma senza crearne uno. `eng --help` resta disponibile. Il vecchio uso di `ENGRAMMA_DIR` accetta anche una cartella dati senza Git; le nuove selezioni richiedono la radice di un repo Git.

`eng sync` e l'avvio di sessione Claude aggiornano i dati senza aggiornare o riavviare il programma. Il programma si aggiorna esplicitamente dal suo checkout con `git pull --ff-only`. Comando e completamenti sono collegati al programma; memorie e istruzioni all'archivio. L'hook Claude che invoca `~/.local/bin/engramma session-start` usa il predefinito della postazione. `eng detach all` converte i dati collegati in copie e rimuove i collegamenti locali a comando e completamenti, conservando il programma.

## 1. Workspace

Un workspace è un cliente o un progetto, con uno o più repo. Sta in `workspaces/<nome>/`:

```
repos.txt              obbligatorio: "<cartella> <url git> [branch principale]"
location.txt           cartella di default sotto ~/workspace (es. "atlas/acme")
requires.txt           comandi necessari: "<comando> [facoltativo]  # a cosa serve"
hosts.txt              hostname di sviluppo che devono stare nel file hosts
excludes.txt           "<repo> <file>": file solo locali da escludere dal git del repo (es. ".env")
AGENTS.md              regole del workspace per Claude e Codex, collegato in <cartella del workspace>/AGENTS.md
.claude/               collegata in <cartella del workspace>/.claude (CLAUDE.md che importa AGENTS.md, settings.json)
docs/                  collegata in <cartella del workspace>/docs
repo-notes/<repo>.md   note personali di un repo
repo-files/<repo>/     file personali collegati nella radice del repo (es. compose.yaml)
memory/_workspace/     memoria di Claude Code per la cartella del workspace
memory/<repo>/         memoria di Claude Code per un repo
README.md              guida del progetto
```

Il branch principale, se non indicato in `repos.txt`, è `develop` quando esiste, altrimenti `main`. Il primo campo di `repos.txt` è il nome della cartella, scelto liberamente: `docs`, `.claude` e `AGENTS.md` sono riservati agli appunti e vengono rifiutati, quindi un repo come `bedita/docs` si clona per esempio in `bedita-docs`.

### Dove vengono clonati i repo

In quest'ordine: `--path <cartella>` (salvato in `~/.config/engramma/paths` per le volte successive), poi la cartella salvata, poi `~/workspace/<location.txt>` o `~/workspace/<nome>`. `--path` indica la cartella che contiene i repo; cambiarlo non sposta né cancella la cartella precedente.

### Cosa fa `eng sync <workspace>`

1. Scarica gli aggiornamenti dell'archivio privato (solo in avanti), mantenendo la versione del programma.
2. Sistema la postazione (sezione 3).
3. Controlla i comandi di `requires.txt`, la versione di node rispetto ai `.nvmrc`, l'accesso SSH a ogni server dei repo, gli hostname nel file hosts (su WSL quello di Windows).
4. Collega `.claude/`, `docs/` e la memoria di Claude.
5. Per ogni repo: lo clona se manca, collega note e file personali, poi lo porta sul branch principale aggiornato. Salta i repo con modifiche non salvate o con un branch ancora in corso. Elenca i branch locali mergiati o il cui branch remoto è stato rimosso. Per quelli con tutti i commit sul remoto, alla fine del workspace chiede se cancellarli; fuori da un terminale li lascia. I branch con commit assenti dal remoto restano fuori dalla domanda: possono essere commit mai pushati oppure unificati con uno squash. `--prune` cancella senza chiedere tutti i branch elencati, anche quelli con commit solo locali.

Il comando salva le modifiche dei workspace selezionati e invia i commit del branch privato, inclusi quelli già presenti. Se l’invio fallisce, rilancia lo stesso comando. Le modifiche al codice dei clienti restano locali.

Senza nome, `eng sync` fa lo stesso per tutti i workspace la cui cartella esiste già su questo computer. Rilanciarlo è sicuro: fa solo ciò che manca.

### Repo in parallelo

Clone, fetch e allineamento dei repo partono subito, per tutti i workspace, mentre si controlla la postazione: 3 repo alla volta, ognuno in un processo separato. Collegamenti e controlli locali restano uno alla volta, e i risultati compaiono nell'ordine di `repos.txt`, uguali a quelli di un'esecuzione senza parallelo. Il fetch avviene anche nei repo con modifiche non salvate: aggiorna solo i branch remoti, non i file. Alla fine il riepilogo elenca i repo falliti e quelli che hanno impiegato più di 30 secondi.

Il numero si sceglie con `-j <n>` (o `--jobs <n>`), che vale più del file locale `~/.config/engramma/config` (non versionato):

```
parallel = true   # false: un repo alla volta
threads = 3
```

### Salvare e creare workspace

- `eng save <workspace>` fa commit dei soli file di `workspaces/<workspace>/`, con il messaggio `docs(<workspace>): update notes and memory` (o un messaggio passato dopo il nome), poi invia i commit del branch al remoto. `eng save global` fa lo stesso per `global/` e `skills/`. Se il push fallisce, rilanciare `eng save` riprova a inviare i commit anche senza nuove modifiche.
- `eng new <workspace> [cartella]` crea `workspaces/<workspace>/` con README, `repos.txt` vuoto e, se data, la cartella sotto `~/workspace`.
- `eng add <workspace> <url> [branch]` aggiunge il repo a `repos.txt`, con il nome della cartella preso dall'indirizzo; `eng sync <workspace>` poi lo clona.
- `eng log` apre il log dell'ultima esecuzione (fuori da un terminale lo stampa).

### Blocchi di git rimasti

Un git interrotto a metà (capita con gli editor che lanciano git in background) lascia `.git/index.lock`, e da lì ogni commit e checkout fallisce. `eng` lo segnala, in engramma e nei repo, quando il file ha più di un minuto e nessun git sta lavorando in quel repo; `eng sync` lo toglie.

### Elenco dei workspace

`eng list` mostra i workspace di engramma: cartella, se c'è su questo computer, e i repo con branch principale e indirizzo (● clonato, ○ non ancora). `eng list <workspace>` solo quelli nominati. Legge solo engramma: niente rete, niente modifiche.

### Output e log

I risultati sono divisi in tre parti: **POSTAZIONE** (engramma, programmi, file globali), **AGENTI** (Claude Code, Codex) e **WORKSPACE**. Senza `-v` ogni blocco è una riga con il suo esito; si apre solo se c'è qualcosa da sistemare o se l'esecuzione ha cambiato qualcosa. Con un workspace nominato (`eng demo`) quel workspace si vede per intero; con `-v` si vede tutto, anche ciò che è a posto.

Il riepilogo finale raccoglie tutto in tre liste: **da sistemare**, con sotto il comando che lo risolve; **modifiche locali e repo non aggiornati** (file non committati, branch mai pushati, repo lasciati com'erano); **avvisi**. Seguono gli **altri comandi** non legati a un messaggio, e i repo falliti o lenti. La riga finale mostra quanti problemi restano; `[ FAIL ]` segnala un repo fallito.

In un terminale il fondo dello schermo è una zona che si ridisegna, separata dai risultati da una linea nei colori del logo: una riga con cosa sta facendo, l'avanzamento (`14/38 repo`) e il tempo trascorso, sotto le ultime 5 righe di output. Ogni riga finisce con l'esito: `[  OK  ]` già a posto, `[ DONE ]` fatto adesso, `[ INFO ]`, `[ DRY  ]`, `[ SKIP ]`, `[ WARN ]`, `[ FAIL ]`. Sopra scorrono il logo e i risultati di ogni blocco, che restano nella cronologia del terminale. Prima di una domanda la zona si ferma e la domanda compare con il suo blocco. Fuori da un terminale, o con `NO_COLOR`, l'output è riga per riga, senza codici di controllo.

Ogni esecuzione scrive il log completo in `~/.local/state/engramma/logs/<data-ora>.log`: anche le righe nascoste senza `-v` e gli errori di git, claude e codex. Restano gli ultimi 20; il riepilogo finale dice quale.

Se l'accesso SSH a un server non funziona, i suoi repo non vengono né clonati né scaricati, e il comando dice di caricare la chiave. Senza agente SSH, il comando usa da solo quello di keychain o del portachiavi del desktop, se sono attivi. git non chiede mai una password a metà (resterebbe in attesa per sempre), e quando fallisce viene mostrato il suo errore.

### Come vengono collegati gli appunti

| In engramma | Sul computer | Come |
|---|---|---|
| `AGENTS.md` | `<cartella del workspace>/AGENTS.md` | link al file |
| `.claude/`, `docs/` | `<cartella del workspace>/.claude`, `/docs` | link alla cartella |
| `memory/<repo>/` | `~/.claude/projects/<chiave>/memory` | link alla cartella |
| `repo-notes/<repo>.md` | `<repo>/CLAUDE.local.md` | file di una riga che importa la nota |
| `repo-files/<repo>/<file>` | `<repo>/<file>` | link al file |

- I file creati o collegati dentro un repo vengono esclusi dal suo git tramite `.git/info/exclude`: vale solo su questo computer e non modifica il repo.
- La chiave della memoria è il percorso del repo con ogni carattere non alfanumerico sostituito da `-` (es. `/home/utente/dev/acme/api` → `-home-utente-dev-acme-api`).
- Claude Code non modifica un file raggiunto tramite link, ma lavora normalmente dentro una cartella collegata: per questo le note passano da un `CLAUDE.local.md` che le importa. I file di `repo-files/` fanno eccezione: per modificarli con Claude va indicato il file in engramma.

### Cartelle e file già presenti

Il comando non sovrascrive mai niente. Dove dovrebbe esserci un collegamento e trova altro:

| Sul computer | Cosa fa |
|---|---|
| copia identica a engramma (file o cartella) | la sostituisce con il collegamento |
| memoria di Claude scritta prima del collegamento | verifica il backup e i file copiati in engramma, poi collega; conserva il backup in `backup/adopted/` (non versionato) |
| cartella con file diversi da engramma | non tocca niente e dice cosa confrontare |
| clone git (es. `bedita/docs` clonato a mano in `docs/`) | non tocca niente e dà il `mv` e la riga di `repos.txt` per spostarlo |
| cartella non di engramma con file che engramma non ha | non tocca niente |
| `CLAUDE.local.md` con un contenuto suo | non tocca niente |

### Aggiungere un workspace

1. Crea `workspaces/<nome>/` con `repos.txt` ed eventualmente gli altri file.
2. Copia in engramma gli appunti esistenti; la memoria di Claude il comando la sposta da solo.
3. Lancia `eng sync <nome>`, poi `eng`.

## 2. Regole e memorie: chi legge cosa

Ogni regola sta in un solo livello; i livelli più specifici aggiungono o restringono, non ridefiniscono. Claude Code e Codex vanno avviati dalla cartella del workspace per lavorare su più repo, o dentro un repo per lavorare solo su quello.

| Livello | Cosa ci va | In engramma | Claude Code | Codex |
|---|---|---|---|---|
| Generale | come si lavora, valido ovunque | `global/claude/CLAUDE.md` | `~/.claude/CLAUDE.md` (collegato) | `~/.codex/AGENTS.md`, scritto da engramma con le regole di boost |
| Workspace | regole del cliente o del team | `workspaces/<ws>/AGENTS.md` | importato da `.claude/CLAUDE.md` (`@../AGENTS.md`) | letto se avviato dalla cartella del workspace |
| Repo, del team | istruzioni committate nel repo | — | `CLAUDE.md` del repo, caricato da solo | `AGENTS.md` o `CLAUDE.md` del repo: da solo se avviato nel repo, per istruzione se avviato dal workspace |
| Repo, personali | note tue su un repo | `repo-notes/<repo>.md` | `CLAUDE.local.md`, caricato da solo | per istruzione |
| Memoria | quello che Claude impara lavorando | `memory/` | memoria automatica | — |

"Per istruzione": Codex carica da solo solo le istruzioni delle cartelle dalla radice del repo fino a quella di avvio. Le istruzioni globali che engramma scrive per Codex gli dicono di leggere quelle del repo in cui lavora, `CLAUDE.local.md` compreso, e di seguire i rimandi `@file`. Codex legge al massimo 32 KB di istruzioni: `eng` avvisa quando le regole del workspace, quelle globali o quelle del team di un repo superano questo limite.

Le regole del workspace si scrivono per tutti e due gli agenti: dentro `AGENTS.md` un rimando `@docs/file.md` Claude lo importa, Codex lo legge come indicazione del file da aprire. Claude non modifica un file raggiunto tramite collegamento: per cambiare `AGENTS.md` con Claude va indicato il file in engramma. La memoria automatica di Codex resta spenta: è sperimentale e legata al computer.

## 3. Postazione

`global/` contiene la configurazione che non appartiene a un workspace. `eng setup` (e ogni `eng sync`) la mette al suo posto.

```
global/
  links.txt      "<file in global/> <destinazione> [unisci]": cosa portare e dove
  requires.txt   programmi della postazione: "<comando> [facoltativo]  # come installarlo"
  claude/ ...    i file veri e propri
```

Le destinazioni ammettono solo `${HOME}`, `${CLAUDE_HOME}` (default `~/.claude`, oppure `ENGRAMMA_CLAUDE_HOME`) e `${XDG_CONFIG_HOME}` (default `~/.config`); qualsiasi altro `$` viene rifiutato.

### File collegati

Il file sul computer è un collegamento a quello di engramma: ogni modifica, da qualunque programma, finisce in engramma. Se un programma ha messo un file suo al posto del collegamento, in un terminale `eng setup` mostra le differenze e chiede quale tenere: quello del computer (copiato in engramma) o quello di engramma (il file del computer resta in `backup/global/<data>/`).

### File uniti: le impostazioni di Claude Code

Claude Code riscrive `~/.claude/settings.json` per intero a ogni modifica, e boost lo riscrive quando si aggiorna: un collegamento si romperebbe. Con `unisci` in `links.txt` il file resta una copia sul computer, unita a engramma in tutte e due le direzioni, voce per voce:

- cambiata solo sul computer (per esempio un plugin attivato con `/plugin`): copiata in engramma;
- cambiata solo in engramma (per esempio arrivata dall'altro computer): portata sul computer;
- cambiata da tutte e due le parti in modo diverso: resta com'è, e in un terminale `eng setup` chiede quale valore tenere.

Il comando ricorda cosa avevano in comune engramma e computer dopo l'ultima unione (in `~/.local/state/engramma/`), per capire da che parte è avvenuta ogni modifica. L'unione avviene anche all'avvio di ogni sessione di Claude Code, che riceve una riga su cosa è cambiato.

### Plugin

Claude Code installa da solo, all'avvio, i marketplace e i plugin dichiarati nelle impostazioni; `eng setup` installa subito quelli che mancano e mostra gli errori che Claude Code segnala. `eng` controlla anche che ogni marketplace dichiarato sia registrato in Claude Code (`eng setup` lo registra prima di installarne i plugin) e segnala quelli con l'aggiornamento automatico spento. I marketplace con `"autoUpdate": true` si aggiornano da soli (per quelli non ufficiali di default è spento). Il marketplace privato via SSH funziona solo con la chiave già caricata nell'agente. I plugin di Codex sono a parte, vedi sotto.

### Codex

Se `codex` è in `global/requires.txt`, `eng setup`:

- scrive le istruzioni globali di Codex dalle regole globali, dalla regola sulle istruzioni dei repo (sezione 2) e da boost; un file scritto a mano non viene mai toccato;
- collega le skill di `skills/` anche in `~/.agents/skills`, dove le legge Codex;
- spegne `shell_snapshot`, così Codex usa la node di ogni cartella;
- aggiunge `project_doc_fallback_filenames = ["CLAUDE.md"]`, così Codex legge i `CLAUDE.md` dei repo che non hanno un `AGENTS.md`;
- installa i plugin di `global/codex/plugins.txt` che vengono da un marketplace, e per gli altri (caveman, la skill di repomix) controlla che ci siano e dà il comando ufficiale per installarli.

```
# global/codex/plugins.txt
plugin aglebert@aglebert   git@gitlab.com:iebook/aglebert-claude-marketplace.git
path ~/.codex/caveman      # npx -y github:JuliusBrussee/caveman -- --only codex, poi /hooks in Codex
skill repomix-explorer     # npx skills add yamadashy/repomix --skill repomix-explorer --agent codex -g
```

La configurazione di Codex contiene dati del computer (cartelle fidate, hook approvati): engramma aggiunge solo queste voci. Gli hook di Codex vanno riapprovati con `/hooks` dopo ogni modifica, per questo engramma non li gestisce.

### Programmi

Un programma di `requires.txt` mancante è un problema, tranne se marcato `facoltativo`. Il comando non installa niente da solo: alla fine, nel riepilogo, dà i comandi nell'ordine giusto (prima i programmi, poi la shell, poi i file diversi, poi i doppioni da togliere). Segnala anche i programmi installati in più copie (anche con il nome che dà Ubuntu, come `fdfind` per `fd`), con il comando per togliere quelle in più, il comando `z` di zoxide non attivato nella shell e gli hook di Claude Code che richiamano script inesistenti.

Claude Code e Codex fotografano l'ambiente all'avvio: un hook nelle impostazioni di Claude e `shell/zprofile` mettono i rimandi di mise davanti a ogni comando, così ogni cartella usa la sua versione di node.

### Completamento nella shell

Ogni `eng sync` o `eng setup` collega il completamento di `eng` ed `engramma` (comandi, workspace, opzioni, cartelle dopo `--path`): per bash in `~/.local/share/bash-completion/completions/`, caricato da solo; per zsh in `~/.local/share/zsh/site-functions/`, che deve stare in `fpath` prima di `compinit` (lo aggiunge `global/shell/zprofile`).

### Percorsi negli appunti

Un percorso assoluto (`/home/<utente>/...`) vale solo sul computer dove è stato scritto. Negli appunti, nelle impostazioni e negli import si scrive `~/...` o un percorso relativo, che Claude Code legge sia nei permessi sia negli `@import`. `eng` segnala ogni percorso assoluto sotto `/home` o `/Users` con la forma `~/` da usare, e dice se su questo computer non esiste. Nei permessi di Claude Code una sola `/` iniziale non è assoluta ma relativa al file di impostazioni: `eng` la segnala a parte. Restano fuori le memorie, scritte da Claude, e i file `unisci`, che i loro programmi riscrivono.

## 4. Più computer

Le modifiche arrivano sull'altro computer solo con commit, push e pull di engramma.

- **All'avvio di Claude Code** l'hook di engramma scarica gli aggiornamenti, unisce le impostazioni e, se engramma ha modifiche non salvate o non inviate, lo dice a Claude in una riga.
- **Ogni `eng`** elenca, per ogni repo di ogni workspace, i file non salvati, i commit non inviati e i branch che esistono solo su questo computer: è il controllo da fare prima di cambiare computer.
- Se engramma ha commit non inviati e insieme commit nuovi sul remoto, non unisce da solo: suggerisce `git pull --rebase` e `git push`.

## 5. Segreti

Nessun segreto va in engramma. Un file personale con valori sensibili si versiona con variabili al loro posto, e i valori vanno in un file locale escluso con `excludes.txt`:

```yaml
# repo-files/api/compose.yaml (versionato)
environment:
  API_KEY: "${API_KEY}"
```

```
# excludes.txt
api .env
```

La CI di engramma passa tutta la storia a gitleaks, che fallisce se trova un segreto committato.

`eng` controlla che le variabili usate senza valore predefinito nei file Docker Compose di `repo-files/` siano presenti e non vuote nel `.env` del repo, e mostra solo i nomi, mai i valori.

## 6. Skill

Ogni cartella di `skills/` viene collegata in `~/.claude/skills/` e in `~/.agents/skills/` (Codex): il formato è lo stesso. Quando una skill esce da `skills/`, `eng sync` toglie il suo collegamento; tocca solo i collegamenti che puntano a una skill di engramma non più esistente. `eng` segnala, senza considerarle un problema, le skill in `~/.claude/skills` non versionate; quelle installate da uno strumento vanno in `skills-ignore.txt`. Una skill legata a un solo repo sta in `repo-files/<repo>/.claude/skills/`.

## 7. Scollegare engramma

```bash
eng detach all -n   # cosa verrebbe sostituito
eng detach all      # ogni collegamento diventa una copia indipendente
```

Dopo, engramma si può cancellare e progetti, Claude Code e Codex continuano a funzionare. Tocca solo i collegamenti che puntano dentro engramma, copia prima in un file temporaneo e sostituisce solo a copia riuscita. `eng detach <workspace>` fa lo stesso per un solo workspace. Per tornare: rimettere in engramma il contenuto aggiornato e lanciare `eng sync`, che sostituisce da solo le copie identiche.

## Limiti

- I nomi di cartella con spazi non sono supportati.

## Skill di progetto

Nell’archivio privato crea `workspaces/<gruppo>/skills/<repo>/<nome>/SKILL.md`. Conserva nella stessa cartella gli eventuali script della skill. Con `eng sync <gruppo>` la skill diventa disponibile in `.agents/skills/<nome>` nel progetto scelto. Puoi modificarla da lì e inviarla con `eng sync <gruppo>`. Una skill locale con lo stesso nome richiede una scelta manuale. Gli agenti che leggono questa cartella possono scoprirla.
