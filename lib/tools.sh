# shellcheck shell=bash
# shellcheck disable=SC2153 # FILE, REF, CMD and the other colors come from lib/theme.sh

# mise installs the programs of the workstation (global/mise/config.toml) and of
# each workspace (workspaces/<ws>/mise.toml, linked into its folder), each at the
# version the file asks for. requires.txt lists the programs mise does not manage:
# those are only checked, with the command to install them.

MISE_INSTALL_COMMAND="curl https://mise.run | sh"

# The mise to use: ENGRAMMA_MISE when set, otherwise the one on PATH or the one
# its installer puts in ~/.local/bin. Prints nothing when there is none.
mise_command() {
	if [[ -n "${ENGRAMMA_MISE:-}" ]]; then
		[[ -x "$ENGRAMMA_MISE" ]] && echo "$ENGRAMMA_MISE"
		return 0
	fi
	if command -v mise; then
		return 0
	fi
	[[ -x "$HOME/.local/bin/mise" ]] && echo "$HOME/.local/bin/mise"
	return 0
}

# mise is required: in a terminal setup offers to install it, otherwise it is a
# problem with the official command to run.
ensure_mise() {
	local mise output
	mise="$(mise_command)"
	if [[ -n "$mise" ]]; then
		fine "${REF}mise${RESET} $(path "$mise")"
		check_mise_activation
		return 0
	fi
	case "$MODE" in
		dry) would "installa mise: $MISE_INSTALL_COMMAND" ;;
		run)
			ask "mise non c'è: installo mise ora con il suo installer ufficiale? [s/N]"
			if [[ "$ASK_ANSWER" == s ]]; then
				if output="$(sh -c "$MISE_INSTALL_COMMAND" 2>&1 </dev/null)" && [[ -n "$(mise_command)" ]]; then
					log_output "$output"
					ok "mise installato in $(path "$(mise_command)")"
					check_mise_activation
					return 0
				fi
				log_output "$output"
			fi
			;;
	esac
	[[ "$MODE" == dry ]] && return 0
	problem "mise non installato: installa i programmi e le versioni di ogni workspace"
	next_step 5 "${CMD}$MISE_INSTALL_COMMAND${RESET}, poi apri un terminale nuovo"
}

# One area (global or a workspace): the tools of its mise file, then the
# programs of its requires.txt. Adds to the TOOLS_* counters and lists.
tools_area() {
	local title="$1" config="$2" folder="$3" requires="$4" mise="$5"
	local name version installed command optional hint shown=false
	echo ""
	echo " ${REPO}$title${RESET}  ${DIM}$(tilde "$config")${RESET}"

	if [[ -f "$config" ]]; then
		while IFS=$'\t' read -r name version installed; do
			shown=true
			if ((installed)); then
				printf '   %s %s%-20s%s %s\n' "${GREEN}●${RESET}" "$TEXT" "$name" "$RESET" "${DIM}$version${RESET}"
				TOOLS_INSTALLED=$((TOOLS_INSTALLED + 1))
			else
				printf '   %s %s%-20s%s %s\n' "${RED}○${RESET}" "$TEXT" "$name" "$RESET" "${DIM}$version · da installare${RESET}"
				TOOLS_MISSING=$((TOOLS_MISSING + 1))
				TOOLS_TO_INSTALL+=("$folder"$'\t'"$name@$version")
			fi
		done < <(cd "$folder" && "$mise" ls --current --json 2>/dev/null | "$PYTHON" "$LIB_DIR/mise_tools.py" "$config")
	fi

	while IFS= read -r command; do
		[[ -n "$command" ]] || continue
		shown=true
		optional="" hint=""
		read -r _ optional _ <<<"$(read_list_file "$requires" | awk -v c="$command" '$1 == c' | sed 's/#.*//' | head -n 1)"
		[[ "$title" == global ]] && hint="$(read_list_file "$requires" | awk -v c="$command" '$1 == c' | head -n 1 | sed -nE 's/^[^#]*#[[:space:]]*//p')"
		if command -v "$command" >/dev/null; then
			printf '   %s %s%-20s%s %s\n' "${GREEN}●${RESET}" "$TEXT" "$command" "$RESET" "${DIM}requires.txt${RESET}"
			TOOLS_INSTALLED=$((TOOLS_INSTALLED + 1))
		elif [[ "$optional" == facoltativo ]]; then
			printf '   %s %s%-20s%s %s\n' "${DIM}○${RESET}" "$TEXT" "$command" "$RESET" "${DIM}requires.txt · facoltativo${RESET}"
		else
			printf '   %s %s%-20s%s %s\n' "${RED}○${RESET}" "$TEXT" "$command" "$RESET" "${DIM}requires.txt · da installare${RESET}"
			TOOLS_MISSING=$((TOOLS_MISSING + 1))
			TOOLS_HINTS+=("${hint:-installa $command a mano}"$'\t'"$command")
		fi
	done < <(read_list_file "$requires" 2>/dev/null | sed 's/#.*//' | awk 'NF { print $1 }')

	$shown || echo "   ${DIM}nessun programma dichiarato${RESET}"
}

# eng tools [install] [ws... | global]: the programs each area asks for, how many
# are installed and how many are missing; with install, mise installs the missing
# versions. Without a name: global and the workspaces present on this computer.
tools_command() {
	local install="$1" only_global="$2"
	shift 2
	local mise names=("$@")
	TOOLS_INSTALLED=0 TOOLS_MISSING=0 TOOLS_TO_INSTALL=() TOOLS_HINTS=()

	mise="$(mise_command)"
	if [[ -z "$mise" ]]; then
		say_fail "mise non installato: installa i programmi e le versioni di ogni workspace"
		echo "   ${DIM}poi:${RESET} ${CMD}$MISE_INSTALL_COMMAND${RESET}"
		return 1
	fi

	local show_global=false
	if $only_global; then
		show_global=true
	elif ((${#names[@]} == 0)); then
		show_global=true
		mapfile -t names < <(present_workspaces)
	fi

	if $install; then
		tools_areas "$show_global" "$mise" "${names[@]}" >/dev/null
		install_missing_tools "$mise"
		return
	fi
	tools_areas "$show_global" "$mise" "${names[@]}"
	echo ""
	echo " ${BOLD}$TOOLS_INSTALLED installati · $TOOLS_MISSING mancanti${RESET}"
	((${#TOOLS_TO_INSTALL[@]})) && echo "   ${CMD}eng tools install${RESET}  ${DIM}installa con mise: $(tools_names)${RESET}"
	print_tools_hints
	((TOOLS_MISSING == 0))
}

tools_areas() {
	local show_global="$1" mise="$2" name folder
	shift 2
	$show_global && tools_area global "$GLOBAL_DIR/mise/config.toml" "$HOME" "$GLOBAL_REQUIRES_FILE" "$mise"
	for name in "$@"; do
		load_workspace "$name"
		folder="$WORKSPACE_NOTES_DIR"
		[[ -d "$WORKSPACE_DIR" ]] && folder="$WORKSPACE_DIR"
		tools_area "$name" "$WORKSPACE_NOTES_DIR/mise.toml" "$folder" "$WORKSPACE_NOTES_DIR/requires.txt" "$mise"
	done
	return 0
}

# The names of the tools mise has to install, without their versions.
tools_names() {
	local entry names=()
	for entry in "${TOOLS_TO_INSTALL[@]}"; do
		entry="${entry#*$'\t'}"
		names+=("${entry%@*}")
	done
	local IFS=, joined
	joined="${names[*]}"
	echo "${joined//,/, }"
}

print_tools_hints() {
	local entry
	for entry in "${TOOLS_HINTS[@]}"; do
		echo "   ${CMD}${entry%%$'\t'*}${RESET}  ${DIM}(installa ${entry#*$'\t'}, fuori da mise)${RESET}"
	done
	return 0
}

# mise installs the missing versions, folder by folder: each version is the one
# its file asks for. The programs outside mise are only listed.
install_missing_tools() {
	local mise="$1" entry folder status=0 folders=() tools
	for entry in "${TOOLS_TO_INSTALL[@]}"; do
		folder="${entry%%$'\t'*}"
		[[ " ${folders[*]} " == *" $folder "* ]] || folders+=("$folder")
	done
	((${#folders[@]})) || echo " ${DIM}niente da installare con mise${RESET}"
	for folder in "${folders[@]}"; do
		tools=()
		for entry in "${TOOLS_TO_INSTALL[@]}"; do
			[[ "${entry%%$'\t'*}" == "$folder" ]] && tools+=("${entry#*$'\t'}")
		done
		if (cd "$folder" && "$mise" install "${tools[@]}"); then
			say_done "installati con mise: ${tools[*]}"
		else
			say_fail "mise install ${tools[*]} fallito"
			status=1
		fi
	done
	if ((${#TOOLS_HINTS[@]})); then
		echo " ${#TOOLS_HINTS[@]} da installare a mano:"
		print_tools_hints
		status=1
	fi
	return $status
}
