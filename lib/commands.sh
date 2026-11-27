# shellcheck shell=bash
# shellcheck disable=SC2153 # FILE, REF, CMD and the other colors come from lib/theme.sh

# Small commands that act on engramma itself and print a few lines, without the
# header and the blocks of sync and check: save, new, add, log.

say_done() { echo " ${GREEN}✓${RESET} $*"; }
say_fail() { echo " ${RED}✗${RESET} $*" >&2; }

# Commits, and pushes, only the files of one workspace (or of the global part):
# the notes of different sessions stay in separate commits.
save_engramma() {
	local area="${1:-}" message="${2:-}" paths=() changed ahead
	[[ -n "$area" ]] || fail_usage "eng save vuole un workspace, oppure global"
	if [[ "$area" == global ]]; then
		paths=(global)
		[[ -d "$ENGRAMMA_DIR/skills" ]] && paths+=(skills)
		message="${message:-chore(global): update global configuration}"
	else
		is_workspace "$area" || fail_usage "Workspace sconosciuto: '$area' (ci sono: $(available_workspaces), oppure global)"
		paths=("workspaces/$area")
		message="${message:-docs($area): update notes and memory}"
	fi
	is_engramma_repo || { say_fail "$(path "$ENGRAMMA_DIR") non è un repo git"; return 1; }
	MODE=run check_git_lock "$ENGRAMMA_DIR"
	changed="$(engramma_git status --porcelain -- "${paths[@]}" | wc -l)"
	if ((changed == 0)); then
		echo " ${DIM}niente da salvare in ${paths[*]}${RESET}"
		has_engramma_remote || return 0
		ahead="$(engramma_git rev-list --count '@{upstream}..HEAD' 2>/dev/null)" || {
			say_fail "impossibile verificare i commit da inviare al remoto"
			return 1
		}
		((ahead)) || return 0
		echo " $ahead commit già salvati da inviare al remoto"
	else
		if ! engramma_git add -A -- "${paths[@]}" || ! engramma_git commit -q -m "$message" -- "${paths[@]}"; then
			say_fail "commit fallito"
			return 1
		fi
		say_done "$changed file in un commit ${REF}$(engramma_git rev-parse --short HEAD)${RESET} ${DIM}· $message${RESET}"
	fi
	has_engramma_remote || return 0
	load_ssh_agent
	if GIT_SSH_COMMAND="ssh -o BatchMode=yes -o ConnectTimeout=10" engramma_git push -q 2>/dev/null; then
		say_done "push fatto: gli altri computer lo ricevono con ${CMD}eng sync${RESET}"
	else
		say_fail "push fallito ${DIM}(chiave SSH nell'agent? poi ${CMD}git -C $(tilde "$ENGRAMMA_DIR") push${RESET}${DIM})${RESET}"
		return 1
	fi
}

# Exchange only the selected workspace data. Git pushes earlier commits on
# the same branch too, including a commit left by an interrupted sync.
send_workspace_updates() {
	local area paths=() changed ahead behind
	[[ "$(engramma_git rev-parse --show-toplevel 2>/dev/null)" == "$ENGRAMMA_DIR" ]] || return 0
	for area in "$@"; do paths+=("workspaces/$area"); done
	if [[ -n "$(engramma_git ls-files -u)" ]] || engramma_git rev-parse -q --verify MERGE_HEAD >/dev/null; then
		problem "Merge pendente nell'archivio: completalo prima di ripetere eng sync"
		return
	fi
	if ((${#paths[@]})); then
		changed="$(engramma_git status --porcelain -- "${paths[@]}")" || { problem "Impossibile leggere le modifiche dell'archivio"; return; }
		if [[ -n "$changed" ]]; then
			if ! engramma_git add -A -- "${paths[@]}" || ! engramma_git commit -q -m "Update workspace context" -- "${paths[@]}"; then
				problem "Salvataggio locale fallito: verifica l'archivio prima di cambiare computer"
				return
			fi
			ok "Contesto salvato su questo computer"
		fi
	fi
	if ! has_engramma_remote; then
		problem "Archivio solo locale: configura il branch remoto per inviare il contesto"
		return
	fi
	if [[ "$ENGRAMMA_FETCH" != ok ]]; then
		problem "Archivio conservato su questo computer: ricezione e invio non confermati. Riprova con eng sync"
		return
	fi
	behind="$(engramma_git rev-list --count 'HEAD..@{upstream}')" || { problem "Stato remoto non verificato"; return; }
	if ((behind)); then
		problem "Aggiornamenti remoti non applicati: contesto locale conservato, invio sospeso"
		return
	fi
	ahead="$(engramma_git rev-list --count '@{upstream}..HEAD')" || { problem "Commit da inviare non verificati"; return; }
	((ahead)) || return 0
	if GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="ssh -o BatchMode=yes -o ConnectTimeout=10" engramma_git push --quiet 2>/dev/null; then
		ok "$ahead commit dell'archivio inviati"
	else
		problem "Commit salvati su questo computer, invio fallito: riprova con eng sync"
	fi
}

# The skeleton of a new workspace: README, folder and an empty list of repos.
new_workspace() (
	local name="${1:-}" location="${2:-}" dir staging root destination
	(( $# <= 2 )) || fail_usage "Uso: eng new <workspace> [cartella]"
	[[ "$name" =~ ^[a-z0-9][a-z0-9._-]*$ ]] || fail_usage "eng new vuole un nome di workspace (minuscole, cifre, - . _)"
	# "eng <name>" must stay unambiguous: a command or "global" always wins.
	[[ " $RESERVED_NAMES " != *" $name "* ]] || fail_usage "'$name' è un nome riservato ai comandi di eng: scegline un altro"
	if [[ -n "$location" ]]; then
		root="$(realpath -m -- "$DEFAULT_WORKSPACES_ROOT")" || return 1
		destination="$(realpath -m -- "$root/$location")" || return 1
		if [[ "$location" = /* || "$location" =~ [[:space:]#] || "/$location/" = */../* || "$destination" != "$root/"* ]]; then
			fail_usage "La cartella deve essere relativa a ~/workspace, senza spazi, # o .."
		fi
	fi
	dir="$ENGRAMMA_DIR/workspaces/$name"
	[[ ! -e "$dir" && ! -L "$dir" ]] || { say_fail "il workspace $name esiste già"; return 1; }
	staging="$(mktemp -d -- "$ENGRAMMA_DIR/workspaces/.new-XXXXXXXX")" || { say_fail "impossibile preparare $name"; return 1; }
	trap 'rm -rf -- "$staging"' EXIT
	if [[ -n "$location" ]]; then
		printf '%s\n' "$location" >"$staging/location.txt" || { say_fail "scrittura della cartella fallita"; return 1; }
	fi
	printf '# <cartella> <url git> [branch principale]\n' >"$staging/repos.txt" || { say_fail "scrittura della lista dei repo fallita"; return 1; }
	if ! cat >"$staging/README.md" <<EOF
# $name

<cosa contiene il workspace, in una riga>

## Repo

| Repo | Cosa | Branch principale |
|---|---|---|

Cartella: \`~/workspace/${location:-$name}\`.
EOF
	then
		say_fail "scrittura della descrizione del workspace fallita"
		return 1
	fi
	if ! mv -Tn -- "$staging" "$dir" || [[ -e "$staging" ]]; then
		say_fail "creazione del workspace $name fallita"
		return 1
	fi
	say_done "workspace ${REPO}$name${RESET} creato in $(path "$dir")"
	echo "   ${DIM}poi:${RESET} ${CMD}eng add $name <url git>${RESET}${DIM}, la descrizione nel README, e ${RESET}${CMD}eng sync $name${RESET}"
)

# Adds a repo to the list of a workspace; eng sync clones it.
add_repo() (
	local name="${1:-}" url="${2:-}" branch="${3:-}" folder file staging newline=""
	(( $# <= 3 )) || fail_usage "Uso: eng add <workspace> <url git> [branch principale]"
	[[ -n "$name" && -n "$url" ]] || fail_usage "Uso: eng add <workspace> <url git> [branch principale]"
	[[ "$name" =~ ^[a-z0-9][a-z0-9._-]*$ ]] || fail_usage "Nome di workspace non valido: '$name'"
	is_workspace "$name" || fail_usage "Workspace sconosciuto: '$name' (ci sono: $(available_workspaces))"
	folder="${url%.git}" folder="${folder##*[/:]}"
	[[ -n "$folder" && "$folder" != . && "$folder" != .. && "$folder" != .git && "$folder" != -* && ! "$url" =~ [[:space:]#] ]] || fail_usage "URL o nome della cartella del repo non valido"
	[[ -z "$branch" || ( ! "$branch" =~ [[:space:]#] && "$branch" != -* ) ]] || fail_usage "Nome del branch non valido"
	if is_reserved_repo_folder "$folder"; then
		fail_usage "'$folder' è una cartella riservata al workspace"
	fi
	file="$ENGRAMMA_DIR/workspaces/$name/repos.txt"
	if [[ "$(realpath -- "${file%/*}")" != "$ENGRAMMA_DIR/workspaces/"* ]]; then
		say_fail "la cartella del workspace deve stare nell'archivio"
		return 1
	fi
	if ! exec 9<"$ENGRAMMA_DIR/workspaces/$name" || ! flock -x 9; then
		say_fail "impossibile bloccare la lista dei repo"
		return 1
	fi
	if [[ -L "$file" || ( -e "$file" && ! -f "$file" ) ]]; then
		say_fail "la lista dei repo deve essere un file regolare"
		return 1
	fi
	if [[ -f "$file" ]] && awk -v name="$folder" '$1 == name { found=1 } END { exit !found }' "$file"; then
		say_fail "$folder è già in $(path "$file")"
		return 1
	fi
	# A last line without its newline would swallow the new entry.
	staging="$(mktemp -- "${file%/*}/.repos-XXXXXXXX")" || { say_fail "impossibile preparare la lista dei repo"; return 1; }
	trap 'rm -f -- "$staging"' EXIT
	if [[ -f "$file" ]]; then
		cp -p -- "$file" "$staging" || { say_fail "copia della lista dei repo fallita"; return 1; }
		[[ -s "$staging" && "$(tail -c 1 "$staging")" != "" ]] && newline=$'\n'
	fi
	if ! printf '%s%s %s%s\n' "$newline" "$folder" "$url" "${branch:+ $branch}" >>"$staging" || ! mv -T -- "$staging" "$file"; then
		say_fail "scrittura della lista dei repo fallita"
		return 1
	fi
	say_done "${TEXT}$folder${RESET} aggiunto a $(path "$file")"
	echo "   ${DIM}poi:${RESET} ${CMD}eng sync $name${RESET} ${DIM}lo clona; aggiungilo anche alla tabella del README del workspace${RESET}"
)

# The log of the last run: in the pager in a terminal, printed otherwise.
show_last_log() {
	local last
	last="$(find "$LOG_DIR" -maxdepth 1 -name '*.log' 2>/dev/null | sort | tail -n 1)"
	[[ -n "$last" ]] || { say_fail "nessun log in $(path "$LOG_DIR")"; return 1; }
	if $IS_INTERACTIVE; then
		${PAGER:-less} "$last"
	else
		cat "$last"
	fi
}
