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

## Prova con un Claude Code vero

I test non avviano Claude. Per verificare che Claude legga davvero regole e memoria:

1. Copia `examples/archive/` in una cartella nuova, inizializzala come repo Git e metti in `workspaces/demo/repos.txt` un repo fittizio locale.
2. Prepara una HOME e cartelle XDG temporanee. Imposta `ENGRAMMA_CLAUDE_HOME` su una cartella di Claude dedicata alla prova. Lancia `eng --data-dir <archivio> sync demo -n`, poi senza `-n`.
3. Avvia Claude nel repo fittizio con `CLAUDE_CONFIG_DIR` uguale alla cartella di prova, da un terminale e non da dentro un'altra sessione di agente.
4. Con `/memory` controlla che la posizione della memoria coincida con quella gestita da engramma.
5. Chiedi a Claude di ricordare una frase inventata, apri una sessione nuova e verifica che la ricordi.

Riferimenti: [memoria di Claude Code](https://code.claude.com/docs/en/memory), [variabili d'ambiente](https://code.claude.com/docs/en/env-vars).

## Modifiche al comportamento

Il comportamento è descritto in `docs/` e garantito dai test. Una funzione nuova parte da una issue con il risultato atteso; la PR porta test e documentazione aggiornati insieme al codice.

## CI

GitHub Actions esegue lint, test e pacchetto su Ubuntu 22.04 e 24.04, poi i controlli su workflow e segreti, compresa la cronologia Git. Le azioni sono fissate a commit verificati e aggiornate da Dependabot. I permessi sono in sola lettura; solo il workflow di release crea una bozza.

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
