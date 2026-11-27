# shellcheck shell=bash

# The wizard only collects choices. The ordinary commands validate and apply the
# plan, so the guided and scripted paths share the same safety checks.
automatic_setup_wizard() {
	$IS_INTERACTIVE && [[ "$MODE" == run ]] &&
		[[ -z "$REQUESTED_AGENTS$REQUESTED_CLAUDE_MEMORY" ]] &&
		((${#WORKSPACES[@]} == 0)) && ! $EXPLICIT_ARCHIVE || return 1
	if ! $HAS_ARCHIVE; then
		[[ -z "$ARCHIVE_PATH" ]]
	else
		[[ -f "$GLOBAL_DIR/agents-defaults.txt" && ! -e "$(agent_profile_path "$ENGRAMMA_DIR")" ]]
	fi
}

wizard_read() {
	printf '%s ' "$1"
	IFS= read -r -u "$wizard_tty" wizard_answer || return 1
	[[ "$wizard_answer" != q ]]
}

wizard_profile_defaults() {
	local ENGRAMMA_DIR="$1" GLOBAL_DIR="$1/global"
	# shellcheck disable=SC2034 # Scoped to the called profile helpers.
	local GLOBAL_REQUIRES_FILE="$1/global/requires.txt" AGENT_PROFILE=""
	local ACTIVE_AGENTS=claude CLAUDE_MEMORY=on EXPLICIT_AGENTS=false
	load_agent_profile || return 1
	wizard_agents="$ACTIVE_AGENTS"
	if ! $EXPLICIT_AGENTS && agent_enabled codex; then wizard_agents+=,codex; fi
	wizard_memory="$CLAUDE_MEMORY"
}

wizard_archive() {
	local choice input
	printf '\n%s\n' "1. Archivio"
	if $HAS_ARCHIVE; then
		printf '   Archivio selezionato: %s\n' "$(tilde "$ENGRAMMA_DIR")"
		echo "   [1] Usa questo archivio"
		if [[ -e "$ARCHIVE_CONFIG_FILE" ]]; then
			echo "   Per collegarne un altro, scollega l’archivio salvato con eng detach all."
		else
			echo "   [2] Collega una cartella   [3] Clona un repository privato   [4] Crea un archivio"
		fi
	else
		[[ -z "$ARCHIVE_PATH" ]] || echo "   $ARCHIVE_ERROR"
		echo "   [1] Crea un archivio   [2] Collega una cartella   [3] Clona un repository privato"
	fi

	while wizard_read "Scelta [1, q annulla]"; do
		choice="${wizard_answer:-1}"
		if $HAS_ARCHIVE && [[ "$choice" == 1 ]]; then
			wizard_kind=reuse
			wizard_destination="$ENGRAMMA_DIR"
			wizard_source=""
			wizard_profile_defaults "$wizard_destination" || return 2
			return 0
		fi
		if $HAS_ARCHIVE && [[ -e "$ARCHIVE_CONFIG_FILE" ]]; then
			echo "   Scegli 1 per usare l’archivio selezionato."
			continue
		fi
		case "$choice" in
			1 | 4)
				if [[ "$choice" == 4 ]] && ! $HAS_ARCHIVE; then
					echo "   Scegli una delle voci del menu."
					continue
				fi
				wizard_read "Cartella da creare [$(tilde "$DEFAULT_ARCHIVE_DIR"), i indietro, q annulla]" || return 1
				[[ "$wizard_answer" != i ]] || continue
				wizard_kind=new
				wizard_source=""
				input="${wizard_answer:-$DEFAULT_ARCHIVE_DIR}"
				;;
			2)
				wizard_read "Cartella dell’archivio [i indietro, q annulla]" || return 1
				[[ "$wizard_answer" != i ]] || continue
				wizard_kind=local
				wizard_source=""
				input="$wizard_answer"
				;;
			3)
				wizard_read "Indirizzo Git del repository privato [i indietro, q annulla]" || return 1
				[[ "$wizard_answer" != i ]] || continue
				if ! is_git_address "$wizard_answer"; then
					echo "   Inserisci un indirizzo Git, per esempio git@github.com:account/archivio.git."
					continue
				fi
				wizard_kind=remote
				wizard_source="$wizard_answer"
				wizard_read "Cartella di destinazione [$(tilde "$DEFAULT_ARCHIVE_DIR"), i indietro, q annulla]" || return 1
				[[ "$wizard_answer" != i ]] || continue
				input="${wizard_answer:-$DEFAULT_ARCHIVE_DIR}"
				;;
			*) echo "   Scegli una delle voci del menu."; continue ;;
		esac
		[[ -n "$input" ]] || { echo "   Indica la cartella dell’archivio."; continue; }
		case "$input" in \~/*) input="$HOME/${input:2}" ;; esac
		wizard_destination="$(realpath -m -- "$input")" || continue
		check_saved_archive "$wizard_destination" || continue
		wizard_agents=none
		wizard_memory=off
		if [[ "$wizard_kind" == local ]]; then
			"$wizard_program" --data-dir "$wizard_destination" --print-data-dir >/dev/null || continue
			wizard_profile_defaults "$wizard_destination" || continue
		elif ! is_free_folder "$wizard_destination"; then
			echo "   La cartella esiste e non è vuota. Scegli un’altra destinazione."
			continue
		fi
		return 0
	done
	return 1
}

wizard_choose_agents() {
	local agent state
	printf '\n%s\n' "2. Agenti"
	for agent in "${KNOWN_AGENTS[@]}"; do
		state="da installare"
		command -v "$agent" >/dev/null && state="installato"
		printf '   %-8s %s\n' "$agent" "$state"
	done
	echo "   Scrivi i nomi separati da virgole, oppure none."
	while wizard_read "Agenti [$wizard_agents, i indietro, q annulla]"; do
		[[ "$wizard_answer" != i ]] || return 2
		wizard_answer="${wizard_answer:-$wizard_agents}"
		if valid_agent_list "$wizard_answer"; then
			wizard_agents="$wizard_answer"
			return 0
		fi
		echo "   Scegli tra claude, codex, copilot e none."
	done
	return 1
}

wizard_choose_memory() {
	local default=N
	agent_in_list "$wizard_agents" claude || return 0
	[[ "$wizard_memory" != on ]] || default=S
	printf '\n%s\n' "3. Memoria di Claude"
	echo "   Puoi conservare nell’archivio privato i ricordi che Claude scrive per i tuoi progetti."
	while wizard_read "Sincronizzare la memoria? [s/n, invio=$default, i indietro, q annulla]"; do
		case "${wizard_answer:-$default}" in
			s | S) wizard_memory=on; return 0 ;;
			n | N) wizard_memory=off; return 0 ;;
			i) return 2 ;;
			*) echo "   Rispondi s oppure n." ;;
		esac
	done
	return 1
}

wizard_setup_command() {
	local memory="$wizard_memory"
	local -a invocation=("$wizard_program") options=()
	$PLAIN && options+=(--plain)
	$VERBOSE && options+=(-v)
	agent_in_list "$wizard_agents" claude || memory=off
	options+=(--agents "$wizard_agents" --claude-memory "$memory")
	case "$wizard_kind" in
		remote) invocation+=(setup "$wizard_source" "$wizard_destination") ;;
		local) invocation+=(setup "$wizard_destination") ;;
		reuse)
			$ARCHIVE_LEGACY || invocation+=(--data-dir "$wizard_destination")
			invocation+=(setup)
			;;
		new) invocation+=(--data-dir "$wizard_destination" setup) ;;
	esac
	if [[ "$1" == preview ]]; then
		ENGRAMMA_LOG_FILE=/dev/null "${invocation[@]}" "${options[@]}" --plain --non-interactive --dry-run
	else
		"${invocation[@]}" "${options[@]}"
	fi
}

wizard_preview() {
	local memory="disattivata"
	if agent_in_list "$wizard_agents" claude && [[ "$wizard_memory" == on ]]; then memory="attiva"; fi
	printf '\n%s\n' "4. Anteprima"
	printf '   Archivio: %s\n   Agenti: %s\n   Memoria di Claude: %s\n' "$(tilde "$wizard_destination")" "$wizard_agents" "$memory"
	case "$wizard_kind" in
		new)
			"$wizard_program" init "$wizard_destination" --dry-run || return
			echo "   Poi collegherei il comando eng, controllerei Git e mise e preparerei gli agenti scelti."
			;;
		remote)
			echo "   Dopo il clone Engramma può verificare i file dell’archivio e della postazione."
			wizard_setup_command preview
			;;
		*) wizard_setup_command preview ;;
	esac
}

wizard_offer_workspace() {
	local ENGRAMMA_DIR="$wizard_destination" workspace candidate list=()
	[[ "$wizard_kind" != new ]] || return 0
	for candidate in "$ENGRAMMA_DIR"/workspaces/*/; do
		workspace="${candidate%/}"; workspace="${workspace##*/}"
		[[ " $RESERVED_NAMES " != *" $workspace "* ]] && is_workspace "$workspace" && list+=("$workspace")
	done
	((${#list[@]})) || return 0
	printf '\n%s\n' "5. Primo workspace"
	printf '   Disponibili: %s\n' "${list[*]}"
	echo "   La sincronizzazione può clonare o aggiornare i repo e inviare note e memoria al remoto dell’archivio."
	while wizard_read "Workspace da sincronizzare [invio per rimandare]"; do
		[[ -n "$wizard_answer" ]] || return 0
		if [[ " ${list[*]} " == *" $wizard_answer "* ]] && is_workspace "$wizard_answer"; then
			local -a invocation=("$wizard_program")
			if [[ "$wizard_kind" != reuse ]] || ! $ARCHIVE_LEGACY; then
				invocation+=(--data-dir "$wizard_destination")
			fi
			invocation+=(sync "$wizard_answer")
			$PLAIN && invocation+=(--plain)
			$VERBOSE && invocation+=(-v)
			"${invocation[@]}"
			return
		fi
		echo "   Scegli un workspace dell’elenco."
	done
	return 0
}

run_setup_wizard() (
	local wizard_tty wizard_answer="" wizard_program="$PROGRAM_DIR/bin/sync.sh"
	local wizard_kind="" wizard_source="" wizard_destination="" wizard_agents=none wizard_memory=off
	local step=archive result
	if ! { exec {wizard_tty}<>/dev/tty; } 2>/dev/null; then
		say_fail "la configurazione guidata richiede un terminale interattivo"
		return 2
	fi
	echo "Configurazione guidata di Engramma"
	while :; do
		case "$step" in
			archive)
				wizard_archive
				case $? in 0) step=agents ;; 2) return 1 ;; *) break ;; esac
				;;
			agents)
				wizard_choose_agents
				case $? in 0) step=memory ;; 2) step=archive ;; *) break ;; esac
				;;
			memory)
				wizard_choose_memory
				case $? in 0) step=review ;; 2) step=agents ;; *) break ;; esac
				;;
			review)
				wizard_preview
				result=$?
				[[ "$MODE" != dry ]] || return "$result"
				if ((result > 1)); then return "$result"; fi
				while wizard_read "Applicare la configurazione? [s applica, i modifica, N annulla]"; do
					case "$wizard_answer" in
						s | S)
							if [[ "$wizard_kind" == new ]]; then "$wizard_program" init "$wizard_destination" || return; fi
							wizard_setup_command apply || return
							wizard_offer_workspace
							return
							;;
						i) step=agents; break ;;
						"" | n | N) break 2 ;;
						*) echo "   Rispondi s, i oppure n." ;;
					esac
				done
				[[ "$step" == agents ]] || break
				;;
		esac
	done
	echo "Configurazione annullata."
	return 0
)
