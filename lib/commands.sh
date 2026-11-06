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
		paths=(global skills)
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

# The skeleton of a new workspace: README, folder and an empty list of repos.
new_workspace() {
	local name="${1:-}" location="${2:-}" dir
	[[ "$name" =~ ^[a-z0-9][a-z0-9._-]*$ ]] || fail_usage "eng new vuole un nome di workspace (minuscole, cifre, - . _)"
	dir="$ENGRAMMA_DIR/workspaces/$name"
	[[ ! -e "$dir" ]] || { say_fail "il workspace $name esiste già"; return 1; }
	mkdir -p "$dir"
	[[ -n "$location" ]] && echo "$location" >"$dir/location.txt"
	printf '# <cartella> <url git> [branch principale]\n' >"$dir/repos.txt"
	cat >"$dir/README.md" <<EOF
# $name

<cosa contiene il workspace, in una riga>

## Repo

| Repo | Cosa | Branch principale |
|---|---|---|

Cartella: \`~/workspace/${location:-$name}\`.
EOF
	say_done "workspace ${REPO}$name${RESET} creato in $(path "$dir")"
	echo "   ${DIM}poi:${RESET} ${CMD}eng add $name <url git>${RESET}${DIM}, la descrizione nel README, e ${RESET}${CMD}eng sync $name${RESET}"
}

# Adds a repo to the list of a workspace; eng sync clones it.
add_repo() {
	local name="${1:-}" url="${2:-}" branch="${3:-}" folder file
	[[ -n "$name" && -n "$url" ]] || fail_usage "Uso: eng add <workspace> <url git> [branch principale]"
	is_workspace "$name" || fail_usage "Workspace sconosciuto: '$name' (ci sono: $(available_workspaces))"
	folder="${url%.git}" folder="${folder##*[/:]}"
	file="$ENGRAMMA_DIR/workspaces/$name/repos.txt"
	if read_list_file "$file" | awk '{ print $1 }' | grep -qxF "$folder"; then
		say_fail "$folder è già in $(path "$file")"
		return 1
	fi
	echo "$folder $url${branch:+ $branch}" >>"$file"
	say_done "${TEXT}$folder${RESET} aggiunto a $(path "$file")"
	echo "   ${DIM}poi:${RESET} ${CMD}eng sync $name${RESET} ${DIM}lo clona; aggiungilo anche alla tabella del README del workspace${RESET}"
}

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
