# Comandi

```
eng [--data-dir <archivio>] [comando] [workspace | global] [opzioni]
```

`init`, `sync`, `setup`, `save`, `detach` e `tools install` applicano modifiche. `new` e `add` scrivono nell'archivio. `session-start`, lanciato dall'hook di Claude Code, aggiorna l'archivio e unisce i file configurati con `unisci`. I controlli mostrano lo stato e registrano il risultato nel log.

## Controllare

| Comando | Cosa fa |
|---|---|
| `eng` | Controlla il computer e i workspace presenti su questo computer. Uguale a `eng check`. |
| `eng <ws>` | Controlla solo quel workspace, con tutti i dettagli. Uguale a `eng check <ws>`. |
| `eng global` | Controlla solo la configurazione del computer. Uguale a `eng check global`. |
| `eng list [ws...]` | I workspace dell'archivio, con cartella e repo (● clonato, ○ non ancora). |
| `eng tools [ws \| global]` | I programmi di mise e di `requires.txt`: quanti installati, quanti mancanti. Vedi [Programmi](tools.md). |
| `eng integrations` | Le integrazioni degli agenti attive e cosa manca. Vedi [Agenti](agents.md#integrazioni). |
| `eng log` | Il log completo dell'ultima esecuzione. |

Il controllo elenca anche il lavoro da non perdere: file non committati, commit non inviati, branch che esistono solo su questo computer. È il controllo da fare prima di cambiare computer.

## Cambiare

| Comando | Cosa fa |
|---|---|
| `eng sync [ws...]` | Scarica l'archivio, sistema il computer, clona e aggiorna i repo, collega appunti e memoria, poi salva e invia note e memoria dei workspace. Senza nome: i workspace presenti su questo computer. |
| `eng sync global` | Scarica l'archivio e sistema solo il computer. Non salva niente. |
| `eng init [cartella]` | Crea un archivio nuovo da un esempio (default `~/engramma-dati`): repo Git con il primo commit, e salva il percorso in `~/.config/engramma/archive`. Rifiuta una cartella non vuota e non cambia un archivio già salvato. Poi si collega un repository privato. |
| `eng setup` | Primo avvio su un computer nuovo. Uguale a `eng sync global`. |
| `eng setup <cartella>` | Collega un archivio esistente: controlla che sia valido, salva il percorso e poi fa il setup. |
| `eng setup <indirizzo Git> [cartella]` | Clona l'archivio (default `~/engramma-dati`), controlla che sia valido, salva il percorso e poi fa il setup. Se qualcosa fallisce, non resta niente. |
| `eng save <ws>` | Commit dei soli file del workspace, con il messaggio `docs(<ws>): update notes and memory` (o quello passato dopo il nome), poi push. Non scarica e non tocca i repo. |
| `eng save global` | Lo stesso per `global/` e `skills/`, con il messaggio `chore(global): update global configuration`. |
| `eng tools install [ws \| global]` | mise installa i programmi mancanti, alla versione richiesta. Per quelli fuori da mise mostra il comando. |
| `eng new <ws> [cartella]` | Crea `workspaces/<ws>/` nell'archivio. La cartella è relativa a `~/workspace` (default: il nome) e nasce al primo `eng sync`. |
| `eng add <ws> <url> [branch]` | Aggiunge un repo a `repos.txt`. Il nome della cartella viene dall'URL. Il repo viene clonato al successivo `eng sync`. |
| `eng detach <ws \| global \| all>` | Sostituisce i collegamenti con copie indipendenti sul computer corrente. Vedi [Domande frequenti](faq.md#scollegare-engramma). |

> [!NOTE]
> `eng sync` salva da solo i workspace, con il messaggio `Update workspace context`. La configurazione del computer e le skill generali si salvano solo con `eng save global`.

## Opzioni

| Opzione | Con | Cosa fa |
|---|---|---|
| `--data-dir <dir>` | tutti, prima del comando | Usa un altro archivio solo per questa esecuzione. |
| `-n`, `--dry-run` | `init`, `sync`, `setup`, `detach` | Mostra cosa farebbe, senza farlo. |
| `-v`, `--verbose` | tutti tranne `save`, `new` e `add` | Output completo: logo, ogni controllo andato bene, etichette `[ OK ]` e `[ WARN ]`. |
| `--path <dir>` | `sync` di un solo workspace | Dove stanno i suoi repo su questo computer. Viene ricordato in `~/.config/engramma/paths`. |
| `-j`, `--jobs <n>` | `sync` | Quanti repo clonare o aggiornare insieme (default 3, o il valore di `~/.config/engramma/config`). |
| `--prune` | `sync` | Cancella senza chiedere i branch locali già mergiati o rimossi dal remoto, **anche quelli con commit solo locali**. |
| `--version` | in qualsiasi posizione | Mostra la versione ed esce prima di leggere l’archivio o eseguire il comando. |
| `-h`, `--help` | da solo | L'aiuto. |

`~/.config/engramma/config` accetta:

```
parallel = true   # false: un repo alla volta
threads = 3
icons = nerd      # nerd, unicode o ascii
```

## Output

L'output standard è breve: una riga di titolo, una riga per sezione con l'icona dell'esito (`✔` a posto, `▲` avviso, `✖` problema, `+` fatto, `◇` prova), poi in fondo l'elenco di ciò che va sistemato, ognuno con il comando che lo risolve. Una sezione senza modifiche non ripete i problemi: li elenca solo il riepilogo. Il logo compare solo con `eng setup`. Con `-v` si vede tutto: logo, ogni controllo e i dettagli di ogni sezione. `eng <ws>` mostra per esteso solo quel workspace.

Le icone hanno tre set. `nerd` usa i glifi dei Nerd Font ed è il default in un terminale: se nel terminale non c'è un Nerd Font compaiono quadratini vuoti. `unicode` usa simboli comuni. `ascii` usa lettere e segni (`o`, `!`, `x`) ed è il default fuori da un terminale, nei log e nelle pipe. Si sceglie con `ENGRAMMA_ICONS=nerd|unicode|ascii` oppure con la riga `icons = unicode` in `~/.config/engramma/config`.

La zona animata in fondo allo schermo (spinner, avanzamento, tempo) compare solo in un terminale con i colori.

## Nomi riservati

Un workspace non può chiamarsi come un comando (`check`, `sync`, `setup`, `init`, `list`, `tools`, `integrations`, `save`, `new`, `add`, `log`, `detach`, `help`, `session-start`) né `global` o `all`. `eng new` li rifiuta.

## Codici di uscita

| Codice | Quando |
|---|---|
| `0` | Tutto a posto. |
| `1` | Resta qualcosa da sistemare (il riepilogo dice cosa e con quale comando), oppure il comando è scritto male. Senza un archivio valido l'uscita è sempre `1`. |

`eng list` esce sempre con `0`.

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

Il riepilogo finale raccoglie cosa sistemare, con il comando sotto ogni voce. Ogni esecuzione scrive il log completo in `~/.local/state/engramma/logs/`; restano gli ultimi 20.

## Variabili d'ambiente

| Variabile | Effetto |
|---|---|
| `ENGRAMMA_DATA_DIR` | Archivio da usare, prima di `~/.config/engramma/archive`. Viene accettato anche `ENGRAMMA_DIR`, che vale per ultimo. |
| `ENGRAMMA_CLAUDE_HOME` | Cartella di Claude Code (default `~/.claude`). |
| `CODEX_HOME` | Cartella di Codex (default `~/.codex`). |
| `XDG_CONFIG_HOME`, `XDG_STATE_HOME`, `XDG_DATA_HOME` | Dove stanno configurazione, stato, log, backup e completamenti. |
| `ENGRAMMA_MISE` | Il mise da usare, al posto di quello nel `PATH`. |
| `ENGRAMMA_THEME` | Colori: `mocha` o `basic`. |
| `ENGRAMMA_ICONS` | Icone: `nerd`, `unicode` o `ascii`. Vince sul file di configurazione. |
| `ENGRAMMA_SLOW_REPO_SECONDS` | Dopo quanti secondi un repo è "lento" nel riepilogo (default 30). |
| `NO_COLOR` | Output senza colori né zona animata. |
| `PAGER` | Programma per `eng log` (default `less`). |

Senza archivio valido `eng` mostra comunque la schermata, segnala il problema e controlla solo i comandi `eng`, mise e git; `eng setup` e `eng sync` creano i comandi `eng` ed `engramma`. Gli altri comandi si fermano con lo stesso messaggio.

Ordine di scelta dell'archivio: `--data-dir`, poi `ENGRAMMA_DATA_DIR`, poi la prima riga di `~/.config/engramma/archive`, poi `ENGRAMMA_DIR`. Il file contiene un percorso letterale, anche con spazi, senza virgolette.
