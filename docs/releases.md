# Release

`VERSION` contiene la versione del programma. Usare SemVer; le versioni di prova hanno un suffisso come `0.1.0-alpha.1`. `CHANGELOG.md` raccoglie le modifiche destinate alla prossima release.

Prima di una release: aggiornare versione e changelog, eseguire `make check` e `make dist`, controllare il contenuto dell'archivio prodotto. La distribuzione contiene soltanto programma, licenza e documentazione essenziale; i dati personali sono esterni.

Dopo la pubblicazione del repo e solo su decisione del maintainer, il workflow **Draft release** viene avviato manualmente indicando un tag già esistente che corrisponda a `v<VERSION>`. Verifica nuovamente il contenuto, produce un archivio con checksum e crea una release in bozza. La pubblicazione resta manuale. Le note GitHub sono organizzate per label di PR.

Quando si attiverà il repository remoto: abilitare PR e controlli richiesti sul branch principale, Dependabot per le Actions, segnalazioni private di vulnerabilità e protezione dei tag. Valutare release immutabili e attestazioni quando il flusso di distribuzione sarà usato; nessuna impostazione remota viene applicata dalla preparazione locale.
