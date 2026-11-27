# shellcheck shell=bash
# shellcheck disable=SC2153 # FILE, REF, CMD and the other colors come from lib/theme.sh

ENGRAMMA_FETCH_TIMEOUT_SECONDS=20
ENGRAMMA_COMMAND_LINK="$HOME/.local/bin/engramma"
ENGRAMMA_SHORT_LINK="$HOME/.local/bin/eng"
# Completion of the names in the shell: "<file in completions/> <link>". bash-completion
# loads by itself what is in its folder; zsh needs the folder in fpath before compinit.
ENGRAMMA_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
ENGRAMMA_COMPLETIONS=(
	"eng.bash $ENGRAMMA_DATA_HOME/bash-completion/completions/eng"
	"eng.bash $ENGRAMMA_DATA_HOME/bash-completion/completions/engramma"
	"_eng $ENGRAMMA_DATA_HOME/zsh/site-functions/_eng"
)

engramma_git() {
	git -C "$ENGRAMMA_DIR" "$@"
}

is_engramma_repo() {
	engramma_git rev-parse --git-dir >/dev/null 2>&1
}

has_engramma_remote() {
	engramma_git rev-parse --abbrev-ref '@{upstream}' >/dev/null 2>&1
}

# Never asks for a password: without a working key the download fails at once.
fetch_engramma() {
	GIT_SSH_COMMAND="ssh -o BatchMode=yes -o ConnectTimeout=10" GIT_TERMINAL_PROMPT=0 \
		timeout "$ENGRAMMA_FETCH_TIMEOUT_SECONDS" git -C "$ENGRAMMA_DIR" fetch --quiet 2>/dev/null
}

engramma_count() {
	engramma_git rev-list --count "$1" 2>/dev/null || echo 0
}

engramma_changed_files() {
	if is_engramma_repo; then
		engramma_git status --porcelain | wc -l
	else
		echo 0
	fi
}

# Brings the archive up to date without updating or restarting the program.
# The fetch is done once per run: report_engramma reads its outcome.
ENGRAMMA_FETCH=""

pull_engramma() {
	[[ -z "${ENGRAMMA_UPDATED:-}" && "$MODE" == run ]] || return 0
	has_engramma_remote || return 0
	start_activity
	activity "engramma › git fetch"
	if fetch_engramma; then
		ENGRAMMA_FETCH=ok
	else
		ENGRAMMA_FETCH=failed
		return 0
	fi

	local behind
	behind="$(engramma_count 'HEAD..@{upstream}')"
	((behind)) || return 0
	engramma_git merge --ff-only --quiet '@{upstream}' 2>/dev/null || return 0

	stop_activity
	put " engramma: fast-forward di $behind commit da $(engramma_git rev-parse --abbrev-ref '@{upstream}')$BADGE_MARK${BADGES[ok]}"
	ENGRAMMA_UPDATED=$behind
}

report_engramma() {
	check_git_lock "$ENGRAMMA_DIR"
	report_engramma_updates
	report_engramma_unsaved
	[[ "${1:-}" == read-only ]] || ensure_engramma_command
}

report_engramma_updates() {
	if ! has_engramma_remote; then
		info "nessun branch remoto configurato per engramma: aggiornamento automatico non disponibile"
		return
	fi
	if [[ -n "${ENGRAMMA_UPDATED:-}" ]]; then
		ok "fast-forward di $ENGRAMMA_UPDATED commit da upstream"
		return
	fi
	activity "engramma › git fetch"
	[[ -n "$ENGRAMMA_FETCH" ]] || { fetch_engramma && ENGRAMMA_FETCH=ok || ENGRAMMA_FETCH=failed; }
	if [[ "$ENGRAMMA_FETCH" == failed ]]; then
		warn "git fetch fallito: impossibile verificare gli aggiornamenti di engramma; uso la copia locale ${DIM}(controlla rete e chiave SSH)${RESET}"
		return
	fi

	local behind ahead
	behind="$(engramma_count 'HEAD..@{upstream}')"
	ahead="$(engramma_count '@{upstream}..HEAD')"
	if ((behind && ahead)); then
		problem "engramma: $ahead commit solo su questo computer e $behind solo sul remoto; serve un rebase"
		fix_with 5 "${CMD}git -C $(tilde "$ENGRAMMA_DIR") pull --rebase && git -C $(tilde "$ENGRAMMA_DIR") push${RESET}"
	elif ((behind)); then
		if [[ "$MODE" == run ]]; then
			warn "engramma: $behind commit sul remoto non applicati; git non ha potuto aggiornare la copia locale"
		else
			warn "engramma: $behind commit sul remoto da scaricare ${DIM}(eng sync aggiorna la copia locale)${RESET}"
		fi
		next_step 5 "${CMD}git -C $(tilde "$ENGRAMMA_DIR") pull${RESET}"
	else
		fine "allineato a upstream"
	fi
}

report_engramma_unsaved() {
	local changed ahead
	changed="$(engramma_changed_files)"
	if ((changed)); then
		if ((changed == 1)); then
			local_work "1 file non committato ${DIM}(gli altri computer non lo vedono)${RESET}"
		else
			local_work "$changed file non committati ${DIM}(gli altri computer non li vedono)${RESET}"
		fi
		fix_with 60 "$(engramma_save_commands)"
	fi
	has_engramma_remote || return 0
	ahead="$(engramma_count '@{upstream}..HEAD')"
	if ((ahead)); then
		local_work "$ahead commit non inviati al remoto"
		fix_with 61 "push di engramma: ${CMD}git -C $(tilde "$ENGRAMMA_DIR") push${RESET}"
	fi
}

ensure_engramma_command() {
	ensure_link "$PROGRAM_DIR/bin/sync.sh" "$ENGRAMMA_COMMAND_LINK" "comando engramma"
	ensure_link "$PROGRAM_DIR/bin/sync.sh" "$ENGRAMMA_SHORT_LINK" "comando eng"
	local entry file link
	for entry in "${ENGRAMMA_COMPLETIONS[@]}"; do
		read -r file link <<<"$entry"
		[[ -f "$PROGRAM_DIR/completions/$file" ]] || continue
		ensure_link "$PROGRAM_DIR/completions/$file" "$link" "completamento $(basename "$link")"
	done
	if [[ -L "$ENGRAMMA_COMMAND_LINK" && ":$PATH:" != *":$(dirname "$ENGRAMMA_COMMAND_LINK"):"* ]]; then
		warn "$(path "$(dirname "$ENGRAMMA_COMMAND_LINK")") non è nel PATH: eng ed engramma non si trovano"
	fi
}

# The links would point into the engramma folder about to be deleted.
detach_engramma_command() {
	local link entry
	local links=("$ENGRAMMA_COMMAND_LINK" "$ENGRAMMA_SHORT_LINK")
	for entry in "${ENGRAMMA_COMPLETIONS[@]}"; do
		links+=("${entry#* }")
	done
	for link in "${links[@]}"; do
		[[ -L "$link" && "$(readlink "$link")" == "$PROGRAM_DIR/"* ]] || continue
		if [[ "$MODE" == dry ]]; then
			would "rimuoverei il symlink $(path "$link")"
		elif rm -- "$link"; then
			ok "rimosso il symlink $(path "$link")"
		else
			problem "impossibile rimuovere il symlink $(path "$link")"
		fi
	done
}

# One line per thing to know, for Claude Code at the start of a session: nothing
# when engramma is up to date, saved, and its merged settings already agree.
session_start_report() {
	MODE=run
	ENGRAMMA_FETCH_TIMEOUT_SECONDS=8
	load_ssh_agent
	if has_engramma_remote && fetch_engramma; then
		local behind
		behind="$(engramma_count 'HEAD..@{upstream}')"
		if ((behind)); then
			if engramma_git merge --ff-only --quiet '@{upstream}' 2>/dev/null; then
				echo "engramma: scaricati $behind commit dall'altro computer."
			else
				echo "engramma: $behind commit nuovi sul remoto non scaricati (conflitto con modifiche locali o commit non inviati)."
			fi
		fi
	fi

	session_merge_report

	local changed ahead=0
	changed="$(engramma_changed_files)"
	has_engramma_remote && ahead="$(engramma_count '@{upstream}..HEAD')"
	((changed)) && echo "engramma ($ENGRAMMA_DIR): $changed file con modifiche non salvate."
	((ahead)) && echo "engramma ($ENGRAMMA_DIR): $ahead commit non inviati."
	return 0
}

# Merges the settings marked "unisci" in links.txt, without asking anything.
session_merge_report() {
	[[ -n "$PYTHON" ]] && has_global_config || return 0
	local source destination how kind path applied=() adopted=() conflicts=()
	while read -r source destination how _; do
		[[ "$how" == unisci && -f "$GLOBAL_DIR/$source" ]] || continue
		destination="$(expand_global_destination "$destination")" || continue
		[[ -L "$destination" ]] && continue
		while IFS=$'\t' read -r kind path _; do
			case "$kind" in
				applied) applied+=("$path") ;;
				adopted) adopted+=("$path") ;;
				*) conflicts+=("${path:-$source}") ;;
			esac
		done < <("$PYTHON" "$LIB_DIR/json_merge.py" "$GLOBAL_DIR/$source" "$destination" "$ENGRAMMA_STATE_DIR/global/$source" run)
	done < <(global_entries)

	local IFS=,
	((${#applied[@]})) && echo "engramma: impostazioni portate da engramma su questo computer: ${applied[*]}."
	((${#adopted[@]})) && echo "engramma: impostazioni cambiate su questo computer copiate in engramma: ${adopted[*]}."
	((${#conflicts[@]})) && echo "engramma: impostazioni cambiate sia qui sia in engramma (${conflicts[*]}): l'utente deve lanciare eng setup in un terminale per scegliere."
	return 0
}

# The commands that save the changed files of engramma, one per area: a
# workspace, the global part, or a plain commit for the files of engramma itself.
engramma_save_commands() {
	local file areas=() other=false commands=() area
	while IFS= read -r file; do
		file="${file:3}"
		file="${file#\"}"
		case "$file" in
			workspaces/*/*) area="${file#workspaces/}" area="${area%%/*}" ;;
			global/* | skills/*) area=global ;;
			*) other=true; continue ;;
		esac
		[[ " ${areas[*]} " == *" $area "* ]] || areas+=("$area")
	done < <(engramma_git status --porcelain)
	for area in "${areas[@]}"; do
		commands+=("${CMD}eng save $area${RESET}")
	done
	$other && commands+=("aggiungi e committa manualmente i file di engramma fuori dai workspace in $(tilde "$ENGRAMMA_DIR")")
	local text="" command
	for command in "${commands[@]}"; do
		text+="${text:+ ${DIM}·${RESET} }$command"
	done
	echo "$text"
}

# Work that would be lost by switching computer now, one line per item.
repo_unsaved_work() {
	local repo="$1" changed branch upstream track
	changed="$(git -C "$repo" status --porcelain 2>/dev/null | wc -l)"
	((changed == 1)) && echo "1 file non committato"
	((changed > 1)) && echo "$changed file non committati"
	while IFS='|' read -r branch upstream track; do
		if [[ -z "$upstream" ]]; then
			is_on_any_remote "$repo" "$branch" || echo "branch $branch solo locale, mai pushato"
		elif [[ "$track" == *ahead* ]]; then
			echo "branch $branch: $(sed -E 's/.*ahead ([0-9]+).*/\1/' <<<"$track") commit non pushati"
		fi
	done < <(git -C "$repo" for-each-ref --format='%(refname:short)|%(upstream)|%(upstream:track,nobracket)' refs/heads/)
	return 0
}

# A branch without upstream whose commits are all on some remote branch is safe.
is_on_any_remote() {
	[[ -z "$(git -C "$1" rev-list "refs/heads/$2" --not --remotes 2>/dev/null | head -n 1)" ]]
}
