# Comandi

```
eng [--data-dir <archivio>] [comando] [workspace | global] [opzioni]
```

`init`, `sync`, `setup`, `save`, `detach` e `tools install` applicano modifiche. `new` e `add` scrivono nell'archivio. `session-start`, lanciato dall'hook di Claude Code, aggiorna l'archivio e unisce i file configurati con `unisci`. I controlli prendono lo stato dalle copie locali e scrivono un log. Con `--refresh`, `check` scarica lo stato dell’archivio remoto e verifica l’accesso SSH dei repo. Le anteprime usano le informazioni già disponibili sul computer.

## Controllare

| Comando | Cosa fa |
|---|---|
| `eng` | Controlla il computer e i workspace presenti su questo computer. Uguale a `eng check`. |
| `eng check --refresh` | Aggiorna lo stato dell’archivio remoto senza applicarne i commit e verifica SSH. Funziona anche con un workspace specifico. |
| `eng <ws>` | Controlla solo quel workspace, con tutti i dettagli. Uguale a `eng check <ws>`. |
| `eng global` | Controlla solo la configurazione del computer. Uguale a `eng check global`. |
| `eng list [ws...]` | I workspace dell'archivio, con cartella e repo (● clonato, ○ non ancora). |
| `eng tools [ws \| global]` | I programmi di mise e di `requires.txt`: quanti installati, quanti mancanti. Vedi [Programmi](tools.md). |
| `eng agents` | Mostra gli agenti gestiti e lo stato della memoria per l’archivio su questa postazione. |
| `eng integrations` | Le integrazioni degli agenti attive e cosa manca. Vedi [Agenti](agents.md#integrazioni). |
| `eng log` | Il log dell’ultimo controllo, setup, sync, save o detach. |

Il controllo elenca anche il lavoro da non perdere: file non committati, commit non inviati, branch che esistono solo su questo computer. È il controllo da fare prima di cambiare computer.

## Cambiare

| Comando | Cosa fa |
|---|---|
| `eng sync [ws...]` | Scarica l'archivio, sistema il computer, clona e aggiorna i repo, collega appunti e memoria, poi salva e invia note e memoria dei workspace. Senza nome: i workspace presenti su questo computer. |
| `eng sync global` | Scarica l'archivio e sistema solo il computer. Non salva niente. |
| `eng init [cartella]` | Crea un archivio nuovo da un esempio (default `~/engramma-dati`): repo Git con il primo commit, e salva il percorso in `~/.config/engramma/archive`. Rifiuta una cartella non vuota e non cambia un archivio già salvato. Poi si collega un repository privato. |
| `eng setup` | Prepara la postazione. Apre la guida al primo avvio in un terminale oppure dopo `init` finché manca la scelta degli agenti. |
| `eng setup --wizard` | Apre la guida anche su una postazione già configurata. Chiede archivio, agenti e memoria, poi mostra l’anteprima. |
| `eng setup <cartella>` | Collega un archivio esistente: controlla che sia valido, salva il percorso e poi fa il setup. |
| `eng setup <indirizzo Git> [cartella]` | Clona l'archivio (default `~/engramma-dati`), controlla che sia valido, salva il percorso e poi fa il setup. Una copia non valida viene scartata. Se il setup successivo fallisce, l’archivio resta collegato e il comando indica come riprendere. |
| `eng save <ws>` | Commit dei soli file del workspace, con il messaggio `docs(<ws>): update notes and memory` (o quello passato dopo il nome), poi push. Non scarica e non tocca i repo. |
| `eng save global` | Lo stesso per `global/` e `skills/`, con il messaggio `chore(global): update global configuration`. |
| `eng tools install [ws \| global]` | mise installa i programmi mancanti, alla versione richiesta. Per quelli fuori da mise mostra il comando. |
| `eng new <ws> [cartella]` | Crea `workspaces/<ws>/` nell'archivio. La cartella è relativa a `~/workspace` (default: il nome) e nasce al primo `eng sync`. |
| `eng add <ws> <url> [branch]` | Aggiunge un repo a `repos.txt`. Il nome della cartella viene dall'URL. Il repo viene clonato al successivo `eng sync`. |
| `eng detach <ws \| global \| all>` | Sostituisce i collegamenti con copie indipendenti sul computer corrente. Vedi [Domande frequenti](faq.md#scollegare-engramma). |

> **Nota.** `eng sync` salva da solo i workspace, con il messaggio `Update workspace context`. La configurazione del computer e le skill generali si salvano solo con `eng save global`.

## Opzioni

| Opzione | Con | Cosa fa |
|---|---|---|
| `--data-dir <dir>` | tutti, prima del comando | Usa un altro archivio solo per questa esecuzione. |
| `-n`, `--dry-run` | `init`, `sync`, `setup`, `detach` | Mostra il piano basato sullo stato locale. Le verifiche di rete avvengono quando applichi le modifiche. |
| `--wizard` | `setup` | Apre la guida interattiva. Con `-n` si ferma all’anteprima. Archivio e agenti si scelgono nel menu. |
| `--agents <elenco>` | `setup` | Salva gli agenti da gestire su questa postazione. Usa `claude`, `codex` e `copilot` separati da virgole, oppure `none`. |
| `--claude-memory on\|off` | `setup` | Attiva o disattiva la sincronizzazione della memoria di Claude per questa postazione. Serve selezionare Claude per usare `on`. |
| `-v`, `--verbose` | `check`, `sync`, `setup`, `detach` | Output completo: logo, ogni controllo andato bene, etichette `[ OK ]` e `[ WARN ]`. |
| `--path <dir>` | `sync` di un solo workspace | Dove stanno i suoi repo su questo computer. Viene ricordato in `~/.config/engramma/paths`. |
| `-j`, `--jobs <n>` | `sync` | Quanti repo clonare o aggiornare insieme (default 3, o il valore di `~/.config/engramma/config`). |
| `--prune` | `sync` | Cancella senza chiedere i branch conclusi i cui commit risultano presenti su `origin`. I branch con commit solo locali restano disponibili. |
| `--plain` | tutti | Produce output statico, senza colori né animazione. |
| `--non-interactive` | tutti | Salta guida e domande. I conflitti restano da risolvere e il riepilogo indica come. |
| `--version` | in qualsiasi posizione | Mostra la versione ed esce prima di leggere l’archivio o eseguire il comando. |
| `-h`, `--help` | generale o dopo il comando | Mostra il riepilogo o un esempio per quel comando, anche senza archivio. |

`~/.config/engramma/config` accetta:

```
parallel = true   # false: un repo alla volta
threads = 3
icons = nerd      # nerd, unicode o ascii
```

## Output

L'output standard è breve: una riga di titolo, una riga per sezione con l'icona dell'esito (`✔` a posto, `▲` avviso, `✖` problema, `+` fatto, `◇` prova), poi in fondo l'elenco di ciò che va sistemato, ognuno con il comando che lo risolve. Una sezione senza modifiche non ripete i problemi: li elenca solo il riepilogo. Il logo compare solo con `eng setup`. Con `-v` si vede tutto: logo, ogni controllo e i dettagli di ogni sezione. `eng <ws>` mostra per esteso solo quel workspace.

Le icone degli esiti usano Unicode comune nei terminali e ASCII fuori dal terminale o con `--plain`. Per usare un Nerd Font, imposta `ENGRAMMA_ICONS=nerd` o `icons = nerd` nella configurazione. Il riepilogo usa anche etichette testuali, per esempio «operazione conclusa con avvisi». Se l’output è reindirizzato, gli errori d’uso e le diagnosi finali dei problemi vanno su `stderr`.

La zona animata mostra avanzamento e tempo in un terminale con i colori. `--plain` o `NO_COLOR` la disattivano.

## Nomi riservati

Un workspace non può chiamarsi come un comando (`check`, `sync`, `setup`, `init`, `list`, `tools`, `integrations`, `agents`, `save`, `new`, `add`, `log`, `detach`, `help`, `session-start`) né `global` o `all`. `eng new` li rifiuta.

## Codici di uscita

| Codice | Quando |
|---|---|
| `0` | Operazione riuscita, anche se ci sono avvisi da leggere. |
| `1` | C’è un problema operativo o qualcosa da sistemare. |
| `2` | Argomenti non validi o opzioni sconosciute. |
| `130` | Operazione interrotta con Ctrl+C. |

## Output e log

Senza `-v` ogni blocco è una riga con il suo esito. Si apre solo se c'è qualcosa da sistemare o se l'esecuzione ha cambiato qualcosa. Gli esiti sono:

| Etichetta | Significato |
|---|---|
| `[  OK  ]` | già a posto |
| `[ DONE ]` | fatto adesso |
| `[ DRY  ]` | cosa farebbe con `-n` |
| `[ INFO ]` | da sapere |
| `[ SKIP ]` | saltato |
| `[ WARN ]` | da sistemare o da controllare |
| `[ FAIL ]` | un repo è fallito |

Il riepilogo finale raccoglie cosa sistemare, con il comando sotto ogni voce. `check`, `setup`, `sync`, `save` e `detach` scrivono un log in `~/.local/state/engramma/logs/` (oppure in `$XDG_STATE_HOME/engramma/logs/`). I nuovi log sono leggibili dal proprietario e vengono conservati gli ultimi 20. `eng log` apre quello aggiornato più di recente.

### Inventario della memoria

Il riepilogo conta i file di memoria di Claude per operazione. Distingue ciò che è stato copiato o collegato sulla postazione, ricevuto nell’archivio dal remoto, salvato con un commit locale e inviato al remoto. Lo stesso file può comparire in più operazioni. Se un invio fallisce, compare da riprovare.

`-v` e `eng log` mostrano l’esito per file, con ambito e motivo delle esclusioni o dei blocchi. Il log riporta i nomi e gli esiti, senza il testo dei ricordi. L’anteprima usa lo stato locale e l’ultimo riferimento Git noto. La ricezione e l’invio riportano le differenze fra le versioni Git coinvolte, comprese le eliminazioni e le modifiche di altri workspace sullo stesso branch.

## Variabili d'ambiente

| Variabile | Effetto |
|---|---|
| `ENGRAMMA_DATA_DIR` | Archivio da usare, prima di `~/.config/engramma/archive`. Viene accettato anche `ENGRAMMA_DIR`, che vale per ultimo. |
| `ENGRAMMA_CLAUDE_HOME` | Cartella di Claude Code (default `~/.claude`). |
| `CODEX_HOME` | Cartella di Codex (default `~/.codex`). |
| `COPILOT_HOME` | Cartella di Copilot CLI (default `~/.copilot`). |
| `XDG_CONFIG_HOME`, `XDG_STATE_HOME`, `XDG_DATA_HOME` | Dove stanno configurazione, stato, log, backup e completamenti. |
| `ENGRAMMA_MISE` | Il mise da usare, al posto di quello nel `PATH`. |
| `ENGRAMMA_THEME` | Colori: `mocha` o `basic`. |
| `ENGRAMMA_ICONS` | Icone: `nerd`, `unicode` o `ascii`. Vince sul file di configurazione. |
| `ENGRAMMA_SLOW_REPO_SECONDS` | Dopo quanti secondi un repo è "lento" nel riepilogo (default 30). |
| `NO_COLOR` | Output senza colori né zona animata. |
| `PAGER` | Programma per `eng log` (default `less`). |

Senza archivio valido `eng` mostra comunque la schermata, segnala il problema e controlla solo i comandi `eng`, mise e git; `eng setup` e `eng sync` creano i comandi `eng` ed `engramma`. Gli altri comandi si fermano con lo stesso messaggio.

Ordine di scelta dell'archivio: `--data-dir`, poi `ENGRAMMA_DATA_DIR`, poi la prima riga di `~/.config/engramma/archive`, poi `ENGRAMMA_DIR`. Il file contiene un percorso letterale, anche con spazi, senza virgolette.
