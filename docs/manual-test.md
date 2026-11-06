# Prova con Claude

Usare un progetto Git nuovo e un archivio fittizio dedicato, fuori dai repository già gestiti dal vecchio Engramma. Il programma è verificato automaticamente con directory Claude simulate; il caricamento effettivo va controllato nell'app.

1. Copiare `examples/archive/` in una nuova cartella e inizializzarla come repo Git. Registrare in `workspaces/demo/repos.txt` un solo repository fittizio locale. Non copiare workspace o configurazioni personali.
2. Preparare una HOME e directory XDG temporanee per i comandi Engramma. Impostare `ENGRAMMA_CLAUDE_HOME` sulla directory Claude dedicata alla prova. Eseguire il comando del nuovo programma con `--data-dir`, prima in dry run e poi in sync. Ogni percorso deve restare dentro l'ambiente di prova.
3. Aprire Claude direttamente dal terminale nel progetto fittizio con `CLAUDE_CONFIG_DIR` uguale alla directory di prova. Potrebbe essere necessario autenticare questa configurazione. Non avviare Claude annidato dentro una sessione di un agente.
4. Usare `/memory` per verificare la posizione effettiva. Deve coincidere con quella gestita da Engramma; se differisce, fermare la prova e annotare la versione di Claude e i due percorsi. Non forzare collegamenti alle memorie abituali.
5. Chiedere a Claude di ricordare una frase inventata; chiudere e aprire una sessione nuova nello stesso ambiente. Verificare che recuperi il ricordo. Eseguire nuovamente sync se la prima memoria è stata creata dopo il precedente sync.
6. Salvare nel solo archivio fittizio e verificare il trasferimento verso un secondo ambiente isolato; successivamente concordare una prova su due computer reali.

Questa prova non cambia l'installazione quotidiana. Il passaggio dei progetti reali avverrà uno alla volta dopo una decisione esplicita.

Riferimenti: [memoria Claude](https://code.claude.com/docs/en/memory), [configurazione dedicata](https://code.claude.com/docs/en/env-vars).
