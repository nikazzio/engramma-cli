# Estrazione iniziale — 6 novembre 2026

## Consegna

- Repository locale indipendente, ramo `main`, cronologia nuova, nessun remote configurato.
- Programma Bash/Python, completamenti, test operativi e documentazione generica. Prototipo di memoria esterna escluso; rimane in pausa nell'archivio di origine.
- Licenza MIT scelta dal maintainer. Esempi esclusivamente fittizi; dati, istruzioni e configurazioni personali non importati.
- Contratto corrente OpenSpec separato dalla proposta aperta per estendere gli agenti.
- CI predisposta per Ubuntu 22.04 e 24.04; controlli di workflow, specifiche, segreti e pacchetto. Release manuali in bozza e aggiornamenti mensili delle Actions tramite Dependabot.
- OpenSpec 1.16.0, actionlint 1.7.12 e Gitleaks 8.30.1 verificati dalle release ufficiali e fissati con checksum. Nessun requisito Node aggiunto al programma.

## Prove locali

- `make test`: 142 test Bats e 4 test Python passati.
- `make lint`: ShellCheck, sintassi zsh e parsing Python passati.
- `make check-tools`: workflow validi, 5 specifiche/proposte OpenSpec valide in modalità strict, scansione dei contenuti senza segreti rilevati.
- `make dist`: archivio sorgenti e checksum generati. Prove di riproducibilità, esclusione dei dati privati e rifiuto di collegamenti a contenuti esterni coperte dai test Python.
- GitHub Actions e creazione della release non eseguite su GitHub: il repository è locale.

## Ripresa

Il prossimo lavoro è preparare un solo progetto nuovo con archivio e configurazione Claude dedicati, seguendo `docs/manual-test.md`. Poi verificare l'app Claude e lo scambio fra computer. Il trasferimento dei progetti esistenti sarà graduale e richiederà una decisione esplicita; l'installazione quotidiana resta quella precedente.

Il repository privato di origine verrà in seguito dedicato all'archivio di memorie native, istruzioni, note e configurazioni. Pubblicazione del programma, attivazione delle impostazioni GitHub e conversione dell'archivio restano operazioni successive.
