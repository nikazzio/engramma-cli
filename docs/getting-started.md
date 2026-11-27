# Primi passi

Tre situazioni: crei l'archivio la prima volta, installi su un computer, aggiungi un altro computer.

## 1. Creare l'archivio

L'archivio è un repo Git privato. Scarica il programma e fallo creare:

```bash
git clone git@github.com:nikazzio/engramma-cli.git ~/engramma
~/engramma/bin/sync.sh init        # crea ~/engramma-dati; con una cartella: init <cartella>
```

`init` copia un archivio di esempio (un workspace `demo` e una cartella `global/` minima), lo trasforma in un repo Git con il primo commit e salva il suo percorso in `~/.config/engramma/archive`. Non scrive in una cartella non vuota e non cambia un archivio già salvato. Con `-n` mostra cosa farebbe.

Poi collega un repository **privato** vuoto, sostituendo `ACCOUNT/ARCHIVIO-PRIVATO`:

```bash
git -C ~/engramma-dati remote add origin git@github.com:ACCOUNT/ARCHIVIO-PRIVATO.git
git -C ~/engramma-dati push -u origin main
```

> [!IMPORTANT]
> Il repo remoto deve essere **privato**: contiene le tue regole, i tuoi appunti e la memoria degli agenti. `git push -u` imposta il branch remoto: senza, `eng` salva solo in locale e lo segnala.

Il significato di ogni file è in [Formato dell'archivio](archive-format.md).

## 2. Installare su un computer

Con l'archivio appena creato, o con il programma già scaricato in `~/engramma`:

```bash
~/engramma/bin/sync.sh setup -n     # cosa cambierebbe
~/engramma/bin/sync.sh setup
```

Con un archivio che esiste già, `setup` lo collega: accetta la cartella oppure l'indirizzo Git, che viene clonato in `~/engramma-dati` (o nella cartella indicata dopo l'indirizzo):

```bash
~/engramma/bin/sync.sh setup git@github.com:ACCOUNT/ARCHIVIO-PRIVATO.git
```

`setup` controlla che sia un archivio valido, salva il suo percorso e poi fa queste cose:

- collega i comandi `eng` ed `engramma` in `~/.local/bin`, che deve stare nel `PATH`;
- controlla mise e, se manca, propone di installarlo;
- collega o unisce i file di `global/links.txt`;
- collega le skill generali e controlla plugin e integrazioni degli agenti.

Senza archivio, `eng` parte lo stesso: segnala che manca, dice come crearlo o collegarlo, e controlla comunque i comandi `eng`, mise e git. `eng setup` crea i comandi anche in quel caso.

> [!WARNING]
> Se sul computer c'è già un file diverso da quello dell'archivio (per esempio `~/.claude/CLAUDE.md`), `setup` non lo tocca: lo segnala e, in un terminale, chiede quale tenere. Se tieni quella dell'archivio, la copia del computer finisce in `~/.local/state/engramma/backup/`.

Poi installa i programmi e controlla che tutto sia a posto:

```bash
eng tools install
eng
```

## 3. Aggiungere un workspace

```bash
eng new acme clienti/acme                       # cartella: ~/workspace/clienti/acme
eng add acme git@github.com:acme/api.git        # nome della cartella: api
eng sync acme                                   # clona, collega, salva
```

`eng new` scrive solo nell'archivio. La cartella sul computer nasce al primo `eng sync`. Aggiungi le regole del cliente in `workspaces/acme/AGENTS.md` (vedi [Agenti](agents.md)).

## 4. Un secondo computer

```bash
git clone git@github.com:nikazzio/engramma-cli.git ~/engramma
~/engramma/bin/sync.sh setup git@github.com:ACCOUNT/ARCHIVIO-PRIVATO.git
eng sync acme
```

`eng sync` senza nome lavora solo sui workspace già presenti sul computer. `eng` elenca gli altri con il comando per portarli. Come tenere allineati i computer è spiegato in [Più computer](multi-computer.md).
