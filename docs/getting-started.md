# Primi passi

Ti servono Linux o WSL, Bash 5, Python 3.10, Git e OpenSSH. Configura il tuo nome e indirizzo email in Git per il primo commit. Per seguire la guida sulla memoria, installa [Claude Code](https://code.claude.com/docs/en/setup).

## 1. Scaricare Engramma

```bash
git clone git@github.com:nikazzio/engramma-cli.git ~/engramma
~/engramma/bin/sync.sh setup --wizard
```

Il programma e l’archivio sono due repository separati. L’archivio contiene le tue regole, gli appunti e la memoria che decidi di sincronizzare. Usa sempre un repository **privato** per l’archivio remoto.

## 2. Installare su un computer

La guida chiede le scelte in sequenza.

1. **Archivio.** Crea un archivio locale, collega una cartella esistente oppure clona un indirizzo Git privato. La cartella proposta per un archivio nuovo o da clonare è `~/engramma-dati`. Se hai già un archivio selezionato, la guida ti propone di riusarlo. Per collegarne un altro, prima [scollega quello salvato](faq.md#scollegare-engramma).
2. **Agenti.** Scegli `claude`, `codex` e `copilot` separati da virgole, oppure `none`. La guida indica quali comandi sono installati.
3. **Memoria di Claude.** Questa domanda compare se scegli Claude. Per un archivio nuovo il default è «no».
4. **Anteprima.** Rivedi il riepilogo. Premi `s` per applicare, `i` per cambiare le scelte o Invio per annullare. Puoi digitare `q` anche nelle domande precedenti. Se stai clonando un archivio, i suoi file vengono controllati dopo il clone.
5. **Primo workspace.** Quando il setup riesce con un archivio esistente, la guida propone uno dei workspace disponibili. Scegli un nome per sincronizzarlo oppure premi Invio per rimandare.

Prima della conferma Engramma non crea, clona o collega l’archivio e non applica la configurazione. Dopo la conferma collega i comandi `eng` ed `engramma` in `~/.local/bin`, controlla Git e mise e prepara gli agenti selezionati. Se manca mise, può chiederti se vuoi installarlo. Se trova un conflitto, ti fa vedere cosa è diverso e ti lascia decidere quale copia conservare.

Su un computer senza un archivio configurato, `setup` apre la guida automaticamente in un terminale. Lo stesso vale dopo `init`, alla prima scelta degli agenti del nuovo archivio. Per riaprirla usa `eng setup --wizard`. Se il terminale non trova ancora `eng`, richiama `~/engramma/bin/sync.sh setup --wizard` e verifica che `~/.local/bin` sia nel `PATH`.

### Collegare il remoto di un archivio appena creato

Crea un repository Git **privato e vuoto**, poi collega il remoto sostituendo `ACCOUNT/ARCHIVIO-PRIVATO` e, se serve, il percorso dell’archivio.

```bash
git -C ~/engramma-dati remote add origin git@github.com:ACCOUNT/ARCHIVIO-PRIVATO.git
git -C ~/engramma-dati push -u origin main
```

`git push -u` imposta il branch remoto. Finché è assente, Engramma conserva il lavoro in locale. Il significato di ogni file è in [Formato dell’archivio](archive-format.md).

### Setup senza domande

In uno script o quando conosci già le scelte puoi usare i comandi diretti.

```bash
~/engramma/bin/sync.sh init
~/engramma/bin/sync.sh setup --agents codex,copilot --dry-run
~/engramma/bin/sync.sh setup --agents codex,copilot --non-interactive
```

Per collegare un archivio esistente passa a `setup` la cartella o l’indirizzo Git. Se l’archivio è già collegato e la configurazione si ferma, correggi l’errore indicato e rilancia `setup` con le stesse opzioni. Dopo il setup, puoi installare i programmi richiesti con `eng tools install` e verificare le scelte con `eng agents`.

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
~/engramma/bin/sync.sh setup --wizard
```

Nella guida scegli di clonare l’archivio privato e, a fine setup, seleziona il workspace da portare sul computer. `eng sync` senza nome lavora solo sui workspace già presenti sul computer. `eng` elenca gli altri con il comando per portarli. Come tenere allineati i computer è spiegato in [Più computer](multi-computer.md).

Dopo il primo `eng sync acme`, controlla che il riepilogo confermi il clone del progetto e che `eng check acme` mostri i collegamenti creati. Per controllare anche lo stato remoto dell’archivio, usa `eng check --refresh`.
