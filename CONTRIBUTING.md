# Contribuire

Usare Linux/WSL con Bash 5, Python 3.10+, Git, Bats, ShellCheck, zsh e Make. `python3 scripts/devtools.py install` aggiunge actionlint e Gitleaks soltanto a `.tools/bin`, con versioni e checksum registrati in `tools.lock.json`.

Per segnalare un bug, descrivi cosa succede, cosa ti aspettavi e come riprodurlo con dati fittizi. Per proporre una funzione o cambiare un comportamento, apri una issue con il risultato atteso.

Nella PR spiega cosa cambia per chi usa il programma e come l’hai verificato. Aggiorna i test e la guida interessata. Durante il lavoro esegui i test mirati e prima della consegna lancia `make check`. I test usano archivi e remoti Git temporanei. Usa esempi inventati anche nelle segnalazioni e nei log allegati.

Usa commit chiari, preferibilmente `fix:`, `feat:`, `docs:` e `test:`. Per le release segui la [procedura](docs/development.md#release).
