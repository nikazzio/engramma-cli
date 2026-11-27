# Problemi comuni

Ogni voce: il messaggio di `eng`, la causa, cosa fare. Il riepilogo finale di `eng` dà già il comando per quasi tutti i problemi; `eng log` mostra il dettaglio dell'ultima esecuzione, compresi gli errori di git, claude e codex.

## Archivio

| Messaggio | Causa | Cosa fare |
|---|---|---|
| `Archivio non valido: … (manca workspaces/)` | la cartella scelta non è un archivio | controlla `~/.config/engramma/archive` o `--data-dir` |
| `Archivio non valido: … (serve la radice di un repository Git)` | la cartella è dentro un repo, non la sua radice | indica la radice del repo dell'archivio |
| `Archivio solo locale: configura il branch remoto…` | l'archivio non ha un branch remoto | `git -C <archivio> push -u origin main` |
| `engramma: N commit solo su questo computer e M solo sul remoto; serve un rebase` | due computer hanno salvato senza ricevere | nell'archivio: `git pull --rebase`, poi `git push` |
| `Merge pendente nell'archivio…` | un merge dell'archivio è rimasto a metà | completalo o annullalo con Git, poi rilancia |
| `Commit salvati su questo computer, invio fallito…` | push non riuscito (rete, chiave SSH) | carica la chiave SSH e rilancia lo stesso comando |
| `blocco di git rimasto da un'operazione interrotta…` | un git interrotto ha lasciato `.git/index.lock` | `eng sync` lo toglie se nessun git sta lavorando |

## Collegamenti

| Messaggio | Causa | Cosa fare |
|---|---|---|
| `…: file locale diverso da engramma, non lo sovrascrivo` | sul computer c'è un file diverso da quello dell'archivio | confronta con il `diff` proposto, porta nell'archivio quello che serve, cancella il file locale, rilancia |
| `…: un programma ha sostituito il symlink con un file diverso` | un programma ha riscritto un file globale collegato | in un terminale `eng setup` chiede quale tenere |
| `…: cartella locale con file diversi da engramma` | una cartella di appunti o memoria esiste già, con altro contenuto | confronta i file elencati e allinea a mano |
| `…: acquisizione interrotta; cartella originale conservata in …` | `eng` è stato interrotto mentre spostava una memoria nell'archivio | controlla la cartella indicata, rimettila al suo posto, rilancia |
| `… è un clone git…, non gli appunti di engramma` | un repo è stato clonato dove vanno gli appunti (es. `docs/`) | spostalo con il `mv` proposto e aggiungilo a `repos.txt` |
| `CLAUDE.md residuo nella cartella del workspace…` | c'è un `CLAUDE.md` vecchio accanto a `.claude/CLAUDE.md` | cancellalo: Claude leggerebbe le regole due volte |
| `…: versionato nel repo, non lo collego` | il team versiona un file con lo stesso nome di un tuo file personale | rinomina il tuo file in `repo-files/` o usa quello del team |

## Repo e SSH

| Messaggio | Causa | Cosa fare |
|---|---|---|
| `ssh <host> non autenticato` | la chiave SSH non è caricata nell'agente | apri un terminale, carica la chiave (`ssh-add`), rilancia. I repo di quel server non vengono né clonati né aggiornati |
| `<hostname> non è nel file hosts…` | manca un hostname di `hosts.txt` | aggiungi la riga proposta da amministratore (su WSL nel file hosts di Windows) |
| repo lasciato com'è | modifiche non salvate o branch di lavoro in corso | normale: `eng` non tocca il lavoro in corso |
| branch principale sbagliato | il repo usa `master` o un altro nome | scrivi il branch come terzo campo in `repos.txt` |

## Programmi e agenti

| Messaggio | Causa | Cosa fare |
|---|---|---|
| `mise non installato…` | mise manca | `curl https://mise.run \| sh`, poi apri un terminale nuovo |
| `mise non attivato in ~/.zshrc…` | la shell non attiva mise | aggiungi la riga proposta, poi apri un terminale nuovo |
| `<comando> non installato` | manca un programma di `requires.txt` | il comando è nel riepilogo; per quelli di mise `eng tools install` |
| `…: abilitato in settings.json, non installato` | un plugin dichiarato non è installato | `eng setup` |
| `marketplace … dichiarato in settings.json ma non registrato…` | il marketplace non è registrato in Claude Code | `eng setup` |
| `MCP code-review-graph non registrato…` | l'integrazione è attiva ma il server MCP non è registrato | il comando `claude mcp add …` o `codex mcp add …` proposto |
| `skill <nome> non versionata` | una skill in `~/.claude/skills` non viene dall'archivio | spostala in `skills/` dell'archivio, o aggiungila a `skills-ignore.txt` |
| `…: conflitto, modificato su entrambi i lati` | una voce di un file unito è cambiata in due modi | `eng setup` in un terminale chiede quale tenere |
