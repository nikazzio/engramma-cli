# Roadmap

| Passo | Quando è completo | Stato |
|---|---|---|
| **1. Affidabilità** | Un’operazione alla volta per archivio. I percorsi si salvano senza lasciare file a metà. Lo scollegamento riuscito dimentica l’archivio. La pulizia dei branch conserva il lavoro solo locale. | Implementato |
| **2. Primo utilizzo** | Il setup guidato chiede archivio, agenti e memoria, con anteprima e scelta del primo workspace. I comandi validano gli argomenti prima di agire, spiegano come riprendere e distinguono controllo locale, aggiornamento remoto, anteprima ed errori. L’output statico funziona anche nel terminale. | Implementato |
| **3. Documentazione** | Guida navigabile con ricerca, menu e build con verifica dei link. Deploy preparato per GitHub Pages. | Implementato |
| **4. Scelta degli agenti e Copilot CLI** | Ogni postazione sceglie Claude, Codex e Copilot. Copilot trova regole e skill tramite la sua CLI. La memoria di Claude si può disattivare preservando le copie. | Implementato |
| **5. Inventario della memoria** | I trasferimenti di Claude mostrano i totali per operazione e l’esito per file nel log. L’invio fallito è distinto dal salvataggio locale. | Implementato |
| **6. Prova reale** | Da due installazioni autenticate, la memoria scritta in Claude su A viene letta su B e torna su A con una seconda modifica. [Procedura di prova](development.md#prova-della-memoria-fra-due-computer) | Installazione e scambio Git verificati in locale. Prova autenticata da fare |
| **7. Beta pubblica** | Cronologia esaminata, CI verde su GitHub, controlli richiesti su `main`, segnalazioni private abilitate. Prerelease con pacchetto verificato, checksum e sito della guida. [Procedura di release](development.md#release) | Da fare |

## Memorie da estendere

- Claude. Verificare i percorsi della memoria configurati a mano.
- Codex. Profilo di prova dedicato, inventario dei formati v1, v2 e misti, verifica nativa di lettura e generazione dopo il trasferimento. I formati non verificati devono comparire come bloccati.
- Copilot. Importazione esplicita nell’account o nel repository GitHub scelto, anteprima completa e esito per ogni ricordo. Provare esiti misti e interruzioni prima di abilitare l’invio di dati reali.

## Dopo la beta

- Aggiungere `--json` a `check` e `list` per script e hook.
- Misurare tempi e chiamate Git su pochi workspace e su un archivio grande. Usare i risultati per decidere dove intervenire.
- Valutare temi chiari, raggruppamento dei problemi con la stessa causa, esempi aggiuntivi e rimozione completa della configurazione creata da Engramma.
- Preparare la migrazione dagli archivi che contengono ancora il programma. Ogni migrazione reale richiede autorizzazione esplicita.
