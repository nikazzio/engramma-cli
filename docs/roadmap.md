# Roadmap

Passi verso la prima versione stabile, nell'ordine in cui si fanno.

| # | Passo | Quando è completo | Stato |
|---|---|---|---|
| 1 | Avvio senza archivio | `eng` parte con la schermata completa e segnala che manca l'archivio. Il livello base (comandi `eng` ed `engramma`, completamenti, mise, git) funziona comunque. | fatto |
| 2 | `eng init` | Crea un archivio nuovo da un esempio, con Git e primo commit, e ne ricorda il percorso. Non scrive in una cartella non vuota. | fatto |
| 3 | `eng setup <indirizzo o cartella>` | Collega o clona un archivio esistente, lo valida e ne ricorda il percorso. Un errore non lascia file a metà. | fatto |
| 4 | Coerenza dei comandi | `init` è un nome riservato. Completamenti, aiuto e guide descrivono i nuovi comandi. `eng` ed `engramma` danno lo stesso risultato. | fatto |
| 5 | Prove | La suite completa e i controlli di sviluppo passano. Test su copia, backup, conflitti e interruzioni. | fatto |
| 6 | Prova reale | Un utente segue la guida da un'installazione pulita. Due installazioni di Claude ritrovano una memoria scritta dall'altra. [Procedura](development.md#prova-della-memoria-fra-due-computer) | da fare |
| 7 | Scollegare l'archivio | Dopo `eng detach all` si toglie anche il percorso salvato in `~/.config/engramma/archive`: il programma torna allo stato senza archivio. | da fare |
| 8 | Passaggio dal programma vecchio | Un archivio con dentro anche il programma diventa solo dati, e i comandi globali usano il programma nuovo. Richiede autorizzazione esplicita. | da fare |
| 9 | Pubblicazione | Contenuti e cronologia destinati al pubblico sono stati esaminati. La CI passa su Ubuntu 22.04 e 24.04, i controlli sono richiesti su `main`, il pacchetto è verificato. [Release](development.md#release) | da fare |

Dopo la versione stabile: liste di esempio più ricche (programmi richiesti e integrazioni) e un comando che disinstalla tutto ciò che Engramma ha creato.

## Proposte da valutare: motore e grafica

Nate dalla lettura del codice. Nessuna voce di velocità è stata ancora misurata: prima di cambiare, si misura.

### Affidabilità

| Cosa si vede oggi | Proposta |
|---|---|
| Un file di configurazione, `~/.config/engramma/paths`, è riscritto direttamente: un'interruzione lo lascia a metà. `new`, `add` e `detach` usano già un file temporaneo e un rename. | Un solo modo per scrivere ogni file del programma: temporaneo e rename. |
| Due `eng` insieme (per esempio l'hook di sessione e un `eng sync`) non si bloccano a vicenda. Il blocco esiste solo in `eng add`. | Un blocco per archivio: il secondo `eng` aspetta o dice che un altro è in corso. |
| I risultati dei repo passano da file di shell rieletti con `source`. | Un formato a righe lette con `read`, senza eseguire niente. |
| Un errore di mise o di git è mostrato in punti diversi, ognuno a modo suo. | Un unico punto che lancia i comandi esterni, ne registra esito e messaggio nel log e lo riporta con lo stesso formato. |
| Il Makefile controlla ShellCheck, sintassi zsh e Python, non la formattazione. | `shfmt` fra i controlli, fissato in `tools.lock.json` come gli altri strumenti. |

### Velocità

| Cosa si vede oggi | Proposta |
|---|---|
| Le attese sono cicli con `sleep 0.05`: distribuzione dei job, attesa del risultato di un repo, sonde SSH. Il disegno della zona animata ridisegna ogni 0,08 s. | Attese su eventi (`wait -n`, pipe), così il programma reagisce subito e consuma meno. |
| Il controllo delle integrazioni lancia un processo Python per ogni verifica di plugin. | Leggere `settings.json` una volta sola per esecuzione. |
| `lib/repos.sh` chiama git in molti punti per ogni repo. | Contare le chiamate reali con `GIT_TRACE` su un archivio di prova e unire quelle che leggono lo stesso stato (`git status --porcelain=v2 --branch`). |
| Il log segnala solo i repo lenti. | Il tempo di ogni blocco nel log e nel riepilogo: si vede dove va il tempo. |
| Nessun test con molti workspace. | Un archivio di prova con 50 workspace: il test segnala se l'esecuzione rallenta. |

### Grafica

| Cosa si vede oggi | Proposta |
|---|---|
| Ogni lancio spinge fuori schermo un'intera schermata e disegna il logo di quattro righe, anche per un controllo di routine. | Un'intestazione di una riga di default. Il logo resta per `setup`, `init` e `--version`. |
| Spinner e linee usano caratteri Unicode, senza controllo del locale. | Una versione ASCII quando il terminale non è UTF-8. |
| I temi sono due: `mocha` (scuro) e `basic`, scelti con `ENGRAMMA_THEME`. | Un tema chiaro, scelta automatica dal terminale e impostazione nel file di configurazione. |
| Nella zona animata, i caratteri non latini diventano `?`. | Gestire la larghezza dei caratteri, così i nomi non latini restano leggibili. |
| Non esiste un'uscita per le macchine. | `--json` per CI e hook, e `--plain` per avere in un terminale l'output senza zona animata. |

Ordine consigliato: prima l'affidabilità (scritture atomiche, blocco, risultati senza `source`), poi le misure di velocità, infine la grafica.
