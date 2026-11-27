# shellcheck shell=bash
# shellcheck disable=SC2153 # FILE, REF, CMD and the other colors come from lib/theme.sh

# What eng does when the archive is missing or invalid: the same screen as every
# other run, the problem reported once, and the steps that need only the program
# itself (the eng commands, mise and git). Anything that reads or writes the
# archive is not run: with no archive ENGRAMMA_DIR is empty.
run_without_archive() {
	local command="$COMMAND"
	if [[ "$command" == session-start ]]; then
		echo "$ARCHIVE_ERROR" >&2
		exit 1
	fi

	start_log
	print_header "$command"
	heading "ARCHIVIO"
	block "archivio" "${ARCHIVE_PATH:+$(tilde "$ARCHIVE_PATH")}" "controlli"
	problem "$ARCHIVE_ERROR"
	if [[ -z "$ARCHIVE_PATH" ]]; then
		fix_with 5 "$(shell_path "$PROGRAM_DIR/bin/sync.sh") init"
	fi

	case "$command" in
		check | sync | setup)
			heading "POSTAZIONE"
			block "programma" "$(tilde "$PROGRAM_DIR")" "controlli"
			ensure_engramma_command
			use_mise_tools
			block "programmi" "mise · git" "programmi"
			ensure_mise
			if command -v git >/dev/null; then
				fine "${REF}git${RESET} $(path "$(command -v git)")"
			else
				problem "${REF}git${RESET} non installato"
				next_step 10 "${CMD}sudo apt install git${RESET}"
			fi
			;;
	esac

	print_summary
	((PROBLEM_COUNT)) && exit 1
	exit 0
}

# ── creating and connecting an archive ────────────────────────────────────────

DEFAULT_ARCHIVE_DIR="$HOME/engramma-dati"
ARCHIVE_CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/engramma/archive"
ARCHIVE_TEMPLATE="$PROGRAM_DIR/examples/archive"

# A path where an archive can be created: missing, or an empty folder.
is_free_folder() {
	[[ ! -e "$1" && ! -L "$1" ]] && return 0
	[[ -d "$1" && ! -L "$1" && -z "$(ls -A -- "$1")" ]]
}

# The saved archive is never replaced by another one: changing it is a deliberate
# edit of the file.
check_saved_archive() {
	local current=""
	[[ -f "$ARCHIVE_CONFIG_FILE" ]] || return 0
	IFS= read -r current <"$ARCHIVE_CONFIG_FILE" || true
	[[ -z "$current" || "$(realpath -m -- "$current")" == "$1" ]] && return 0
	say_fail "è già salvato un altro archivio: $current"
	echo "   ${DIM}per cambiarlo modifica o cancella ${RESET}$(path "$ARCHIVE_CONFIG_FILE")" >&2
	return 1
}

# Recheck the choice while holding the workstation configuration lock.
remember_archive() (
	local staging
	lock_config || return 1
	check_saved_archive "$1" || return 1
	staging="$(mktemp -- "$ARCHIVE_CONFIG_FILE.XXXXXXXX")" || return 1
	trap 'rm -f -- "$staging"' EXIT
	printf '%s\n' "$1" >"$staging" && mv -T -- "$staging" "$ARCHIVE_CONFIG_FILE"
)

has_other_saved_archive() {
	local current=""
	[[ -f "$ARCHIVE_CONFIG_FILE" ]] || return 1
	IFS= read -r current <"$ARCHIVE_CONFIG_FILE" || true
	[[ -n "$current" && "$(realpath -m -- "$current")" != "$ENGRAMMA_DIR" ]]
}

forget_archive() {
	local current=""
	[[ -f "$ARCHIVE_CONFIG_FILE" ]] || return 0
	IFS= read -r current <"$ARCHIVE_CONFIG_FILE" || true
	[[ -n "$current" && "$(realpath -m -- "$current")" == "$ENGRAMMA_DIR" ]] || return 0
	if [[ "$MODE" == dry ]]; then
		would "dimenticherei l’archivio in $(path "$ARCHIVE_CONFIG_FILE")"
	elif forget_saved_archive; then
		ok "archivio scollegato da questa postazione"
	else
		problem "impossibile dimenticare l’archivio in $(path "$ARCHIVE_CONFIG_FILE")"
	fi
}

forget_saved_archive() (
	local current=""
	lock_config || return 1
	[[ -f "$ARCHIVE_CONFIG_FILE" ]] || return 0
	IFS= read -r current <"$ARCHIVE_CONFIG_FILE" || true
	[[ -n "$current" && "$(realpath -m -- "$current")" == "$ENGRAMMA_DIR" ]] || return 0
	rm -- "$ARCHIVE_CONFIG_FILE"
)

shell_path() {
	local value="$1"
	if [[ "$value" == "$HOME/"* ]]; then
		# shellcheck disable=SC2088 # Print a literal tilde for the command to paste.
		printf '~/%q' "${value#"$HOME/"}"
	else
		printf '%q' "$value"
	fi
}

# eng init [folder]: a new archive from the example, a Git repo with its first commit.
init_archive() {
	local destination="$1" staging parent
	destination="$(realpath -m -- "${destination:-$DEFAULT_ARCHIVE_DIR}")" || return 1
	[[ -d "$ARCHIVE_TEMPLATE" ]] || { say_fail "manca l'archivio di esempio $(path "$ARCHIVE_TEMPLATE")"; return 1; }
	is_free_folder "$destination" || { say_fail "$(path "$destination") esiste e non è vuota: non la tocco"; return 1; }
	check_saved_archive "$destination" || return 1
	if [[ "$MODE" == dry ]]; then
		echo " ${CYAN}◇${RESET} creerei l'archivio in $(path "$destination") e salverei il percorso in $(path "$ARCHIVE_CONFIG_FILE")"
		return 0
	fi
	parent="$(dirname "$destination")"
	mkdir -p -- "$parent" || { say_fail "impossibile creare $(path "$parent")"; return 1; }
	staging="$(mktemp -d -- "$parent/.engramma-init-XXXXXXXX")" || { say_fail "impossibile preparare l'archivio"; return 1; }
	if ! cp -a -- "$ARCHIVE_TEMPLATE/." "$staging/" ||
		! git -C "$staging" init -q -b main ||
		! git -C "$staging" add -A; then
		rm -rf -- "$staging"
		say_fail "preparazione dell'archivio fallita"
		return 1
	fi
	if ! git -C "$staging" commit -q -m "archivio iniziale"; then
		rm -rf -- "$staging"
		say_fail "primo commit fallito ${DIM}(imposta user.name e user.email di git: non li modifico io)${RESET}"
		return 1
	fi
	if ! mv -T -- "$staging" "$destination"; then
		rm -rf -- "$staging"
		say_fail "impossibile creare $(path "$destination")"
		return 1
	fi
	say_done "archivio creato in $(path "$destination")"
	if ! remember_archive "$destination"; then
		say_fail "archivio creato, percorso non salvato. Per collegarlo: $(shell_path "$PROGRAM_DIR/bin/sync.sh") setup $(shell_path "$destination")"
		return 1
	fi
	say_done "percorso salvato in $(path "$ARCHIVE_CONFIG_FILE")"
	echo "   ${DIM}poi, con un repository privato vuoto:${RESET}"
	echo "   ${CMD}git -C $(shell_path "$destination") remote add origin git@github.com:ACCOUNT/ARCHIVIO-PRIVATO.git${RESET}"
	echo "   ${CMD}git -C $(shell_path "$destination") push -u origin main${RESET}"
	echo "   ${DIM}infine:${RESET} ${CMD}$(shell_path "$PROGRAM_DIR/bin/sync.sh") setup${RESET}"
}

is_git_address() {
	[[ "$1" =~ ^[a-z][a-z0-9+.-]*:// || "$1" =~ ^[^/@[:space:]]+@[^:/[:space:]]+: ]]
}

# eng setup <folder or address> [folder]: connects an existing archive, then runs
# the normal setup.
attach_archive() {
	local source="$1" destination="${2:-}" staging directory setup_args=() status
	[[ "$MODE" == dry ]] && setup_args+=(-n)
	$VERBOSE && setup_args+=(-v)
	$PLAIN && setup_args+=(--plain)
	$NON_INTERACTIVE && setup_args+=(--non-interactive)
	[[ -z "$REQUESTED_AGENTS" ]] || setup_args+=(--agents "$REQUESTED_AGENTS")
	[[ -z "$REQUESTED_CLAUDE_MEMORY" ]] || setup_args+=(--claude-memory "$REQUESTED_CLAUDE_MEMORY")

	if [[ -d "$source" ]]; then
		[[ -z "$destination" ]] || fail_usage "La cartella di destinazione serve solo con un indirizzo Git"
		directory="$(realpath -m -- "$source")" || return 1
		# shellcheck disable=SC2034 # read by validate_archive
		ENGRAMMA_DIR="$directory" ARCHIVE_LEGACY=false
		validate_archive || { say_fail "$ARCHIVE_ERROR"; return 1; }
		check_saved_archive "$directory" || return 1
	elif is_git_address "$source"; then
		directory="$(realpath -m -- "${destination:-$DEFAULT_ARCHIVE_DIR}")" || return 1
		is_free_folder "$directory" || { say_fail "$(path "$directory") esiste e non è vuota: non la tocco"; return 1; }
		check_saved_archive "$directory" || return 1
		if [[ "$MODE" == dry ]]; then
			echo " ${CYAN}◇${RESET} clonerei $source in $(path "$directory") e salverei il percorso in $(path "$ARCHIVE_CONFIG_FILE")"
			[[ -z "$REQUESTED_AGENTS" ]] || echo "   agenti richiesti: $REQUESTED_AGENTS"
			[[ -z "$REQUESTED_CLAUDE_MEMORY" ]] || echo "   memoria di Claude richiesta: $REQUESTED_CLAUDE_MEMORY"
			return 0
		fi
		load_ssh_agent
		mkdir -p -- "$(dirname "$directory")" || { say_fail "impossibile creare $(path "$(dirname "$directory")")"; return 1; }
		staging="$(mktemp -d -- "$(dirname "$directory")/.engramma-clone-XXXXXXXX")" || { say_fail "impossibile preparare il clone"; return 1; }
		if ! GIT_SSH_COMMAND="ssh -o BatchMode=yes -o ConnectTimeout=10" GIT_TERMINAL_PROMPT=0 \
			git clone --quiet -- "$source" "$staging" 2>/dev/null; then
			rm -rf -- "$staging"
			say_fail "clone di $source fallito ${DIM}(indirizzo giusto? chiave SSH nell'agent?)${RESET}"
			return 1
		fi
		if [[ ! -d "$staging/workspaces" ]]; then
			rm -rf -- "$staging"
			say_fail "$source non è un archivio Engramma: manca workspaces/ nella radice"
			return 1
		fi
		if ! mv -T -- "$staging" "$directory"; then
			rm -rf -- "$staging"
			say_fail "impossibile creare $(path "$directory")"
			return 1
		fi
		say_done "archivio clonato in $(path "$directory")"
	else
		say_fail "'$source' non è una cartella né un indirizzo Git"
		return 1
	fi

	if [[ "$MODE" == dry ]]; then
		echo " ${CYAN}◇${RESET} salverei $(path "$directory") in $(path "$ARCHIVE_CONFIG_FILE")"
	else
		if ! remember_archive "$directory"; then
			say_fail "archivio disponibile in $(path "$directory"), percorso non salvato. Per collegarlo: $(shell_path "$PROGRAM_DIR/bin/sync.sh") setup $(shell_path "$directory")"
			return 1
		fi
		say_done "percorso salvato in $(path "$ARCHIVE_CONFIG_FILE")"
	fi
	"$PROGRAM_DIR/bin/sync.sh" --data-dir "$directory" setup "${setup_args[@]}"
	status=$?
	if ((status == 1)) && [[ "$MODE" == run ]]; then
		say_fail "archivio collegato, configurazione da completare. Riprova con: $(shell_path "$PROGRAM_DIR/bin/sync.sh") setup"
	fi
	return "$status"
}
