# shellcheck shell=bash
# shellcheck disable=SC2153 # FILE, REF, CMD and the other colors come from lib/theme.sh

# What eng does when the archive is missing or invalid: the same screen as every
# other run, the problem reported once, and the steps that need only the program
# itself (the eng commands, mise, git, SSH). Anything that reads or writes the
# archive is not run: with no archive ENGRAMMA_DIR is empty.
run_without_archive() {
	local command="${1:-check}"
	[[ "$command" != -* ]] || command=check
	if [[ "$command" == session-start ]]; then
		echo "$ARCHIVE_ERROR" >&2
		exit 1
	fi

	# shellcheck disable=SC2034 # read by the output and link modules
	MODE=check
	local argument
	case "$command" in
		sync | setup)
			MODE=run
			for argument in "$@"; do
				# shellcheck disable=SC2034 # read by the output and link modules
				[[ "$argument" == -n || "$argument" == --dry-run ]] && MODE=dry
			done
			;;
	esac

	for argument in "$@"; do
		# shellcheck disable=SC2034 # read by the output module
		[[ "$argument" == -v || "$argument" == --verbose ]] && VERBOSE=true
	done
	use_output_style

	start_log
	print_header "$command"
	heading "ARCHIVIO"
	block "archivio" "${ARCHIVE_PATH:+$(tilde "$ARCHIVE_PATH")}" "controlli"
	problem "$ARCHIVE_ERROR"

	case "$command" in
		check | sync | setup)
			heading "POSTAZIONE"
			block "programma" "$(tilde "$PROGRAM_DIR")" "controlli"
			ensure_engramma_command
			use_mise_tools
			load_ssh_agent
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

remember_archive() {
	local staging
	mkdir -p -- "$(dirname "$ARCHIVE_CONFIG_FILE")" || return 1
	staging="$(mktemp -- "$ARCHIVE_CONFIG_FILE.XXXXXXXX")" || return 1
	if ! printf '%s\n' "$1" >"$staging" || ! mv -T -- "$staging" "$ARCHIVE_CONFIG_FILE"; then
		rm -f -- "$staging"
		return 1
	fi
}

# eng init [folder]: a new archive from the example, a Git repo with its first commit.
init_archive() {
	local destination="" dry=false argument staging parent
	for argument in "$@"; do
		case "$argument" in
			-n | --dry-run) dry=true ;;
			-*) fail_usage "eng init non accetta l'opzione $argument" ;;
			*)
				[[ -z "$destination" ]] || fail_usage "Uso: eng init [cartella]"
				destination="$argument"
				;;
		esac
	done
	destination="$(realpath -m -- "${destination:-$DEFAULT_ARCHIVE_DIR}")" || return 1
	[[ -d "$ARCHIVE_TEMPLATE" ]] || { say_fail "manca l'archivio di esempio $(path "$ARCHIVE_TEMPLATE")"; return 1; }
	is_free_folder "$destination" || { say_fail "$(path "$destination") esiste e non è vuota: non la tocco"; return 1; }
	check_saved_archive "$destination" || return 1
	if $dry; then
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
	remember_archive "$destination" || { say_fail "percorso non salvato in $(path "$ARCHIVE_CONFIG_FILE")"; return 1; }
	say_done "percorso salvato in $(path "$ARCHIVE_CONFIG_FILE")"
	echo "   ${DIM}poi, con un repository privato vuoto:${RESET}"
	echo "   ${CMD}git -C $(tilde "$destination") remote add origin <indirizzo del repository>${RESET}"
	echo "   ${CMD}git -C $(tilde "$destination") push -u origin main${RESET}"
	echo "   ${DIM}infine:${RESET} ${CMD}eng setup${RESET}"
}

is_git_address() {
	[[ "$1" =~ ^[a-z][a-z0-9+.-]*:// || "$1" =~ ^[^/@[:space:]]+@[^:/[:space:]]+: ]]
}

# eng setup <folder or address> [folder]: connects an existing archive, then runs
# the normal setup.
attach_archive() {
	local source="" destination="" dry=false argument staging directory setup_args=()
	for argument in "$@"; do
		case "$argument" in
			-n | --dry-run) dry=true ;;
			-*) fail_usage "Opzione sconosciuta: $argument" ;;
			*)
				if [[ -z "$source" ]]; then
					source="$argument"
				elif [[ -z "$destination" ]]; then
					destination="$argument"
				else
					fail_usage "Uso: eng setup <indirizzo o cartella> [cartella]"
				fi
				;;
		esac
	done
	$dry && setup_args=(-n)

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
		if $dry; then
			echo " ${CYAN}◇${RESET} clonerei $source in $(path "$directory") e salverei il percorso in $(path "$ARCHIVE_CONFIG_FILE")"
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

	if $dry; then
		echo " ${CYAN}◇${RESET} salverei $(path "$directory") in $(path "$ARCHIVE_CONFIG_FILE")"
	else
		remember_archive "$directory" || { say_fail "percorso non salvato in $(path "$ARCHIVE_CONFIG_FILE")"; return 1; }
		say_done "percorso salvato in $(path "$ARCHIVE_CONFIG_FILE")"
	fi
	exec "$PROGRAM_DIR/bin/sync.sh" --data-dir "$directory" setup "${setup_args[@]}"
}
