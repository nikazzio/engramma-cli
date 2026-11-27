# Programmi

[mise](https://mise.jdx.dev) installa i programmi e ne sceglie la versione in base alla cartella. Engramma lo usa per tutti i programmi che servono al computer e ai workspace.

| Dove | File nell'archivio | Vale |
|---|---|---|
| Computer | `global/mise/config.toml` | ovunque (di solito collegato in `~/.config/mise/config.toml`) |
| Workspace | `workspaces/<ws>/mise.toml` | nella cartella del workspace e in tutti i suoi repo |
| Repo | `mise.toml` o `.tool-versions` del team, nel repo | solo in quel repo, sopra quello del workspace |

```toml
# workspaces/acme/mise.toml
[tools]
node = "22"
php = "8.3"
```

Un file con solo `[tools]` e versioni non richiede `mise trust`.

## mise è obbligatorio

`eng` controlla che mise ci sia e che la shell lo attivi (`mise activate` nel `.bashrc` o `.zshrc`). Se manca, in un terminale `eng setup` propone di installarlo con il comando ufficiale:

```bash
curl https://mise.run | sh
```

Fuori da un terminale mostra il comando e basta.

## `eng tools`

```
$ eng tools

 global  ~/engramma-dati/global/mise/config.toml
   ● node                 22
   ○ jq                   1.7.1 · da installare
   ● git                  requires.txt
   ○ docker               requires.txt · da installare

 acme  ~/engramma-dati/workspaces/acme/mise.toml
   ○ php                  8.3 · da installare

 2 installati · 3 mancanti
   eng tools install  installa con mise: jq, php
   sudo apt install docker.io  (installa docker, fuori da mise)
```

- `eng tools` mostra global e i workspace presenti sul computer. Usa `eng tools <ws>` o `eng tools global` per uno solo.
- `eng tools install` fa installare a mise le versioni mancanti, ognuna dalla cartella del suo file.
- Se mise restituisce un errore durante la lettura, Engramma mostra il motivo e termina con codice 1. In questo caso anche `eng tools install` si ferma prima di installare i programmi.
- Non cambia niente senza `install`, ed esce con `1` se manca qualcosa.

## `requires.txt`: programmi fuori da mise

Alcuni programmi non si installano con mise, per esempio git, ssh o docker. Vanno in `requires.txt`, globale o del workspace:

```
# <comando> [facoltativo]  # come installarlo
docker                     # sudo apt install docker.io
netlify    facoltativo     # npm install -g netlify-cli
```

Per questi programmi `eng` controlla che il comando esista e non li installa mai. Un programma `facoltativo` assente non è un problema.

- In `global/requires.txt` il commento è il comando per installarlo: `eng` lo mostra quando il programma manca. `eng` segnala anche i programmi installati in più copie, con il comando per togliere quelle in più.
- In `workspaces/<ws>/requires.txt` il commento dice a cosa serve il programma.
