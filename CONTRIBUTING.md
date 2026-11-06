# Contribuire

Usare Linux/WSL con Bash 5, Python 3.10+, Git, Bats, ShellCheck, zsh e Make. `python3 scripts/devtools.py install` aggiunge OpenSpec, actionlint e Gitleaks soltanto a `.tools/bin`, con versioni e checksum registrati in `tools.lock.json`.

Per un bug, descrivere cosa succede, cosa ci si aspetta e come riprodurlo con dati fittizi. Per una nuova funzione, aprire prima una proposta sul comportamento. Non allegare memorie, configurazioni personali o segreti.

Le specifiche correnti stanno in `openspec/specs/`. Per cambiare il contratto, creare una proposta in `openspec/changes/`, discuterla, implementarla e verificarla. OpenSpec è uno strumento di sviluppo: `OPENSPEC_TELEMETRY=0 .tools/bin/openspec validate --all --strict --no-interactive` verifica i documenti.

Una PR descrive il problema, il comportamento risultante e le prove eseguite. Test mirati durante il lavoro; prima della consegna eseguire `make check`. I test usano archivi e remoti Git temporanei e non richiedono account Claude o credenziali di rete.

Usare commit chiari, preferibilmente `fix:`, `feat:`, `docs:` e `test:`. Le release sono manuali e usano SemVer; [procedura](docs/releases.md).
