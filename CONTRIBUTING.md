# Contribuire

Usare Linux/WSL con Bash 5, Python 3.10+, Git, Bats, ShellCheck, zsh e Make. `python3 scripts/devtools.py install` aggiunge actionlint e Gitleaks soltanto a `.tools/bin`, con versioni e checksum registrati in `tools.lock.json`.

Per un bug, descrivere cosa succede, cosa ci si aspetta e come riprodurlo con dati fittizi. Per una nuova funzione, aprire prima una proposta sul comportamento. Non allegare memorie, configurazioni personali o segreti.

Il comportamento è descritto in `docs/` e garantito dai test. Per una funzione nuova o un cambio di comportamento, aprire prima una issue che descriva il risultato atteso; la PR aggiorna test e documentazione.

Una PR descrive il problema, il comportamento risultante e le prove eseguite. Test mirati durante il lavoro; prima della consegna eseguire `make check`. I test usano archivi e remoti Git temporanei e non richiedono account Claude o credenziali di rete.

Usare commit chiari, preferibilmente `fix:`, `feat:`, `docs:` e `test:`. Le release sono manuali e usano SemVer; [procedura](docs/development.md#release).
