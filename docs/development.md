# Sviluppo

Il programma usa solo Bash 5 e la libreria standard di Python. Gli strumenti di sviluppo restano separati dal runtime.

## Struttura

| Cartella | Contenuto |
|---|---|
| `bin/sync.sh` | il comando `eng`: legge gli argomenti e avvia i passi |
| `lib/` | i moduli: collegamenti, repo, global, Codex, programmi, integrazioni, output |
| `completions/` | completamento per bash e zsh |
| `tests/` | test Bats e Python, con archivi, remoti Git e configurazioni temporanei |
| `examples/archive/` | un archivio fittizio di partenza |

## Comandi

```bash
make test                            # Bats e unittest Python
make lint                            # ShellCheck, sintassi zsh e Python
python3 scripts/devtools.py install  # actionlint e Gitleaks in .tools/bin
make check-tools                     # workflow e scansione dei segreti
make check                           # tutto quanto sopra
make dist                            # archivio dei sorgenti e SHA256SUMS in dist/
```

Servono Bats, ShellCheck, zsh e Make. actionlint e Gitleaks sono fissati in `tools.lock.json`, con versione e checksum per Linux x64 e arm64. `scripts/devtools.py install` verifica il checksum prima di installarli. Il programma non richiede Node.

> [!IMPORTANT]
> I test usano sempre HOME, cartelle XDG, Claude e mise finti. Non lanciare mai `setup`, `sync` o `detach` sul tuo archivio vero per verificare una modifica.

## Prova della memoria fra due computer

Servono due installazioni Linux/WSL indipendenti, A e B. Su ciascuna usa un utente dedicato alla prova, con la propria HOME, configurazione XDG e sessione di Claude Code. Esegui Claude in un terminale del relativo utente. Annota la versione di Engramma e di Claude su entrambe.

1. **Prepara A.** Segui [Primi passi](getting-started.md) con un archivio Git privato di prova. Nel workspace `demo` registra un piccolo repo Git di nome `app`, accessibile anche da B. Esegui `eng sync demo -n`, poi `eng sync demo`. Verifica che l’archivio abbia un branch remoto e che il push sia riuscito.
2. **Scrivi un ricordo.** Avvia Claude nella cartella `app` del workspace su A. Chiedigli di salvare nella memoria automatica una convenzione inventata per questo repo, con un valore scelto al momento. Verifica con `/memory` dove l’ha scritta e chiudi Claude.
3. **Invia la memoria.** Esegui di nuovo `eng sync demo` su A. Questo passaggio acquisisce anche una memoria creata da Claude per la prima volta. Nell’archivio controlla che il commit inviato contenga la convenzione sotto `workspaces/demo/memory/app/`.
4. **Ricevila su B.** Da un’installazione con memoria vuota, clona lo stesso archivio. Esegui `eng setup` e `eng sync demo`. Controlla il testo ricevuto nell’archivio, poi avvia Claude nel repo `app`. In una sessione nuova chiedi quale sia la convenzione, senza suggerire il valore né mostrare la chat di A. Verifica che il valore coincida e che `/memory` mostri la memoria del repo.
5. **Controlla il ritorno.** Su B fai salvare una seconda convenzione, esegui `eng sync demo` su B e poi su A. In una nuova sessione di Claude su A verifica il secondo valore.

Per verificare anche le regole del workspace e le skill di repo, aggiungi un’istruzione riconoscibile e una skill fittizia al progetto di prova. Controlla cosa appare in Claude avviandolo prima nel workspace e poi nel repo. Registra l’esito insieme alle versioni usate. [Regole e skill](agents.md#skill)

## Modifiche al comportamento

Il comportamento è descritto in `docs/` e garantito dai test. Una funzione nuova parte da una issue con il risultato atteso; la PR porta test e documentazione aggiornati insieme al codice.

## CI

GitHub Actions esegue lint e test su Ubuntu 22.04 e 24.04 per ogni PR e push su `main`. Su entrambi costruisce il pacchetto, verifica il checksum e avvia il programma estratto per controllare la versione. Un job separato controlla i workflow e cerca segreti nei file e nella cronologia Git. Le azioni sono fissate a commit e aggiornate da Dependabot.

## Release

- `VERSION` contiene la versione, in SemVer. Le versioni di prova hanno un suffisso, come `0.1.0-alpha.1`.
- `CHANGELOG.md` raccoglie le modifiche della prossima release.
- Prima di una release: aggiorna versione e changelog, lancia `make check` e `make dist`, controlla il contenuto dell'archivio prodotto.
- Il workflow manuale **Draft release** parte da un tag `v<VERSION>` già esistente. Verifica di nuovo il contenuto, produce l'archivio con i checksum e crea una release in bozza. La pubblicazione resta manuale.
- Le note di release sono generate da GitHub e ordinate per label delle PR (`bug`, `enhancement`, `documentation`).

## Impostazioni del repository su GitHub

- branch principale protetto, con PR e controlli richiesti;
- Dependabot per le Actions;
- segnalazioni private di vulnerabilità;
- protezione dei tag.
