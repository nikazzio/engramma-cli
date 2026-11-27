# Roadmap della prima beta

| Passo | Quando è completo |
|---|---|
| Verificare i comandi | `eng` ed `engramma` danno lo stesso risultato. Il completamento Bash e zsh propone argomenti validi. La versione si può leggere senza configurare un archivio. |
| Rendere leggibile la diagnosi | Le colonne delle integrazioni sono allineate. Se mise fallisce, si vede l’errore e il comando esce segnalando il problema. Il suggerimento per attivarlo usa l’eseguibile presente sul computer. |
| Proteggere i dati | I test coprono copia, backup, conflitti e interruzioni. Un errore nello scollegamento viene segnalato e permette di recuperare gli originali. |
| Provare il flusso reale | Un utente segue la guida da un’installazione pulita. Due installazioni di Claude ritrovano una memoria scritta dall’altra. [Procedura](development.md#prova-della-memoria-fra-due-computer) |
| Pubblicare la beta | Contenuti e cronologia destinati al pubblico sono stati esaminati. La CI passa su entrambe le versioni di Ubuntu, i controlli sono richiesti su `main` e il pacchetto della beta è stato verificato. [Release](development.md#release) |
