# Strumenti del repository

Il programma usa Bash e la standard library Python. Gli strumenti di sviluppo sono separati dal runtime.

| Strumento | Uso |
|---|---|
| Bats | Test dei comandi con archivi, remoti Git e configurazioni temporanei |
| ShellCheck e zsh | Controlli statici Bash e sintassi dei completamenti |
| OpenSpec | Contratto corrente in `openspec/specs/`, proposte in `openspec/changes/` |
| actionlint | Verifica dei workflow GitHub Actions |
| Gitleaks | Scansione di contenuti e cronologia prima della pubblicazione |

OpenSpec, actionlint e Gitleaks sono fissati in `tools.lock.json` per Linux x64 e arm64. `scripts/devtools.py install` verifica il checksum prima di installare l'eseguibile sotto `.tools/bin`. Per aggiornare uno strumento, verificare release e checksum ufficiali, aggiornare il lock e ripetere i controlli pertinenti. Dependabot propone gli aggiornamenti delle Actions, fissate a commit verificati.

CI usa runner Ubuntu 22.04 e 24.04, permessi in lettura e credenziali Git non persistenti. Solo il workflow manuale di release ottiene il permesso di creare una bozza. I test non richiedono accesso a Claude o ai repository personali.

Le issue raccolgono bug riproducibili e proposte di comportamento. Le PR riportano risultato e verifica; le label standard `bug`, `enhancement` e `documentation` organizzano le note di release. Per la fase locale, le proposte OpenSpec sono già utilizzabili senza un servizio remoto.

Fonti: [release OpenSpec](https://github.com/Fission-AI/OpenSpec/releases), [Bats](https://github.com/bats-core/bats-core), [workflow sicuri](https://docs.github.com/en/actions/reference/security/secure-use), [note di release](https://docs.github.com/en/repositories/releasing-projects-on-github/automatically-generated-release-notes).
