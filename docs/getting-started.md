# Primi passi

Tre situazioni: crei l'archivio la prima volta, installi su un computer, aggiungi un altro computer.

## 1. Creare l'archivio

L'archivio è un repo Git privato. Scarica il programma e parti dal suo esempio:

```bash
git clone <url di Engramma> ~/engramma
cp -r ~/engramma/examples/archive ~/engramma-dati
cd ~/engramma-dati
git init -b main
git add -A && git commit -m "archivio iniziale"
git remote add origin git@github.com:<tu>/<archivio-privato>.git
git push -u origin main
```

> [!IMPORTANT]
> Il repo remoto deve essere **privato**: contiene le tue regole, i tuoi appunti e la memoria degli agenti. `git push -u` imposta il branch remoto: senza, `eng` salva solo in locale e lo segnala.

L'esempio contiene un workspace `demo` e una cartella `global/` minima. Il significato di ogni file è in [Formato dell'archivio](archive-format.md).

## 2. Installare su un computer

Se hai appena creato l'archivio, il programma è già in `~/engramma`; altrimenti scaricalo con `git clone <url di Engramma> ~/engramma`.

```bash
mkdir -p ~/.config/engramma && echo ~/engramma-dati > ~/.config/engramma/archive
~/engramma/bin/sync.sh setup -n     # cosa cambierebbe
~/engramma/bin/sync.sh setup
```

`setup` fa queste cose:

- collega i comandi `eng` ed `engramma` in `~/.local/bin`, che deve stare nel `PATH`;
- controlla mise e, se manca, propone di installarlo;
- collega o unisce i file di `global/links.txt`;
- collega le skill generali e controlla plugin e integrazioni degli agenti.

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
git clone git@github.com:<tu>/<archivio-privato>.git ~/engramma-dati
git clone <url di Engramma> ~/engramma
mkdir -p ~/.config/engramma && echo ~/engramma-dati > ~/.config/engramma/archive
~/engramma/bin/sync.sh setup
eng sync acme
```

`eng sync` senza nome lavora solo sui workspace già presenti sul computer. `eng` elenca gli altri con il comando per portarli. Come tenere allineati i computer è spiegato in [Più computer](multi-computer.md).
