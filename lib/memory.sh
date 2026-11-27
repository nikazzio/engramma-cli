# shellcheck shell=bash

# Files are counted per operation: a file can be acquired locally, committed and
# sent during the same run. The terminal and the log share these records.
declare -A MEMORY_COUNTS=()
MEMORY_DETAILS=()
MEMORY_DIAGNOSTICS=()
MEMORY_LAST_COMMIT_BASE=""

memory_record() {
	local operation="$1" status="$2" scope="$3" file="$4" reason="${5:-}" line
	printf -v line '   memoria · %s · %s · ambito %q' "$operation" "$status" "$scope"
	if [[ -n "$file" ]]; then printf -v line '%s · file %q' "$line" "$file"; fi
	if [[ -n "$reason" ]]; then line+=" · $reason"; fi
	log_line "$line"
	if $VERBOSE; then MEMORY_DETAILS+=("$line"); fi
	if [[ -n "$file" ]]; then
		local key="$operation/$status"
		MEMORY_COUNTS[$key]=$((${MEMORY_COUNTS[$key]:-0} + 1))
	elif [[ "$status" == bloccati ]]; then
		MEMORY_DIAGNOSTICS+=("$line")
	fi
}

print_memory_inventory() {
	local operation key line count totals shown=false
	local -a operations=("postazione" "ricezione" "salvataggio" "invio")
	local -a statuses=("copiati" "disponibili" "identici" "già collegati" "da copiare" "da collegare" "esclusi" "conflitto" "bloccati" "ricevuti" "da ricevere" "salvati" "da salvare" "inviati" "da inviare" "invio da riprovare" "già sul remoto")
	local -A singular=([copiati]=copiato [disponibili]=disponibile [identici]=identico ["già collegati"]="già collegato"
		[esclusi]=escluso [bloccati]=bloccato [ricevuti]=ricevuto [salvati]=salvato [inviati]=inviato)
	local status label
	for operation in "${operations[@]}"; do
		totals=()
		for status in "${statuses[@]}"; do
			key="$operation/$status"
			count="${MEMORY_COUNTS[$key]:-0}"
			((count)) || continue
			label="$status"
			if ((count == 1)); then label="${singular[$status]:-$status}"
			elif [[ "$status" == conflitto ]]; then label="conflitti"
			fi
			totals+=("$count $label")
		done
		(("${#totals[@]}")) || continue
		if ! $shown; then put " Memoria di Claude · inventario"; shown=true; fi
		printf -v line '%s · ' "${totals[@]}"
		put "   $operation · ${line% · }"
	done
	if $VERBOSE; then
		for line in "${MEMORY_DETAILS[@]}"; do printf '%s\n' "$line"; done
	else
		for line in "${MEMORY_DIAGNOSTICS[@]}"; do printf '%s\n' "$line"; done
	fi
	if $shown || (("${#MEMORY_DIAGNOSTICS[@]}")); then
		[[ -z "$LOG_FILE" ]] || put "   Dettaglio per file: eng log"
		put ""
	fi
	return 0
}

# The status marker keeps find/sort errors detectable even with process
# substitution. NUL delimiters preserve whitespace and control bytes in names.
memory_directory_entries() {
	local directory="$1"
	local -n entries="$2"
	entries=()
	[[ ! -L "$directory" ]] || return 1
	[[ -e "$directory" ]] || return 0
	[[ -d "$directory" ]] || return 1
	mapfile -d '' -t entries < <(
		find -P "$directory" -mindepth 1 ! -type d -printf '%P\0' | LC_ALL=C sort -z
		printf '%s\0' "$?"
	)
	(("${#entries[@]}")) || return 1
	local status="${entries[-1]}"
	unset 'entries[-1]'
	[[ "$status" == 0 ]]
}

# Scan a single workspace or repository. An already managed link points to
# the archive, so read that directory only once and count each file once.
inventory_memory_scope() {
	local target="$1" link="$2" scope="$3" label="$4" file path_state
	local local_entries=() archive_entries=() order=() verified_copies=()
	local -A local_files=() archived_files=() classifications=() verified=()
	local managed=false linked_elsewhere=false scan_failed=false
	if [[ -L "$link" ]]; then
		if [[ "$(readlink "$link")" == "$target" ]]; then managed=true; else linked_elsewhere=true; fi
	else
		memory_directory_entries "$link" local_entries || scan_failed=true
	fi
	memory_directory_entries "$target" archive_entries || scan_failed=true
	for file in "${local_entries[@]}"; do local_files[$file]=1; order+=("$file"); done
	for file in "${archive_entries[@]}"; do
		archived_files[$file]=1
		[[ -v 'local_files[$file]' ]] || order+=("$file")
	done

	local special=false comparison
	for file in "${order[@]}"; do
		if { [[ -v 'local_files[$file]' ]] && [[ ! -f "$link/$file" || -L "$link/$file" ]]; } ||
			{ [[ -v 'archived_files[$file]' ]] && [[ ! -f "$target/$file" || -L "$target/$file" ]]; }; then
			classifications[$file]=special
			special=true
		elif [[ -v 'local_files[$file]' && -v 'archived_files[$file]' ]]; then
			cmp -s -- "$link/$file" "$target/$file"
			comparison=$?
			case "$comparison" in
				0) classifications[$file]=same ;;
				1) classifications[$file]=conflict ;;
				*) classifications[$file]=unreadable; scan_failed=true ;;
			esac
		elif [[ -v 'local_files[$file]' ]]; then
			if [[ -d "$target/$file" ]]; then classifications[$file]=conflict; else classifications[$file]=local; fi
		elif ! $managed && ! $linked_elsewhere && [[ -d "$link/$file" ]]; then
			classifications[$file]=conflict
		else
			classifications[$file]=archive
		fi
	done

	if $scan_failed; then
		path_state="inventario incompleto: cartella illeggibile o di tipo non previsto"
		memory_record postazione bloccati "$scope" "" "$path_state"
		if [[ "$CLAUDE_MEMORY" == on ]]; then problem "$label: $path_state"; fi
	fi

	local before="$PROBLEM_COUNT" now_linked=false issue=""
	if [[ "$CLAUDE_MEMORY" == off ]]; then
		if (("${#order[@]}" == 0)); then memory_record postazione esclusi "$scope" "" "sincronizzazione della memoria disattivata"; fi
	elif $scan_failed; then
		issue="inventario incompleto"
	elif $special; then
		issue="elementi di tipo non supportato"
		problem "$label: $issue"
	elif $linked_elsewhere; then
		issue="cartella collegata altrove"
		problem "$label: $issue"
		memory_record postazione bloccati "$scope" "" "$issue"
	elif [[ -d "$target" || "${#local_entries[@]}" -gt 0 ]]; then
		ensure_link "$target" "$link" "$label" adopt verified_copies
		if [[ -L "$link" && "$(readlink "$link")" == "$target" ]]; then
			now_linked=true
		elif [[ "$MODE" == run ]]; then
			issue="collegamento non riuscito; vedi la diagnosi del workspace"
			if ((PROBLEM_COUNT == before)); then problem "$label: collegamento non creato"; fi
		fi
	else
		memory_record postazione identici "$scope" "" "nessuna memoria trovata"
	fi

	for file in "${verified_copies[@]}"; do
		verified[$file]=1
		if [[ ! -v 'classifications[$file]' ]]; then
			classifications[$file]=local
			order+=("$file")
		fi
	done
	local status reason
	local conflict=false
	for file in "${order[@]}"; do
		if [[ "${classifications[$file]}" == conflict ]]; then conflict=true; fi
	done
	for file in "${order[@]}"; do
		reason=""
		if [[ "$CLAUDE_MEMORY" == off ]]; then
			status=esclusi reason="sincronizzazione della memoria disattivata"
		elif [[ -v 'verified[$file]' ]]; then
			status=copiati reason="$issue"
		elif [[ "${classifications[$file]}" == special ]]; then
			status=esclusi reason="tipo di file non supportato"
		elif [[ "${classifications[$file]}" == unreadable ]]; then
			status=bloccati reason="impossibile confrontare le copie"
		elif [[ "${classifications[$file]}" == conflict ]]; then
			status=conflitto reason="versioni locale e archivio diverse"
		elif [[ "${classifications[$file]}" == same ]]; then
			status=identici
		elif [[ "${classifications[$file]}" == local ]]; then
			if [[ -n "$issue" ]] || $conflict; then
				status=bloccati reason="${issue:-altro file in conflitto nello stesso ambito}"
			elif [[ "$MODE" != run ]]; then
				status="da copiare"
			elif $now_linked && [[ -f "$target/$file" ]]; then
				status=identici reason="già presente al momento del collegamento"
			else
				status=bloccati reason="file cambiato durante l’acquisizione"
			fi
		elif $managed && ! $scan_failed && ! $special; then
			status="già collegati"
		elif $now_linked; then
			status=disponibili
		elif [[ -n "$issue" ]] || $conflict; then
			status=bloccati reason="${issue:-altro file in conflitto nello stesso ambito}"
		else
			status="da collegare"
		fi
		memory_record postazione "$status" "$scope" "$file" "$reason"
	done
}

# Changes to an entire Git archive can include other workspaces. Report net
# changes for the exact refs involved, including deleted files, without diffs
# containing their contents. A failed command yields a scoped diagnostic.
memory_git_changes() {
	local operation="$1" status="$2" reason="$3"
	shift 3
	local -a records=()
	mapfile -d '' -t records < <(
		engramma_git diff --name-status --no-renames -z "$@" -- ':(glob)workspaces/*/memory/**' 2>/dev/null
		printf '%s\0' "$?"
	)
	if [[ "${records[-1]:-1}" != 0 ]]; then
		memory_record "$operation" bloccati archivio "" "impossibile ricostruire i file dai riferimenti Git"
		return 1
	fi
	unset 'records[-1]'
	local i
	for ((i = 0; i + 1 < ${#records[@]}; i += 2)); do
		memory_archive_change "$operation" "$status" "${records[i+1]}" "${records[i]}" "$reason"
	done
}

memory_archive_change() {
	local operation="$1" status="$2" file="$3" change="$4" reason="$5" remainder scope extra
	remainder="${file#workspaces/}"
	scope="${remainder%%/*}"
	remainder="${remainder#*/memory/}"
	if [[ "$remainder" == */* ]]; then
		scope+="/${remainder%%/*}"
		remainder="${remainder#*/}"
	fi
	case "$change" in
		A) extra="aggiunta" ;;
		D) extra="eliminazione" ;;
		T) extra="cambio di tipo" ;;
		*) extra="modifica" ;;
	esac
	memory_record "$operation" "$status" "$scope" "$remainder" "$extra${reason:+ · $reason}"
}

memory_unregistered_scope() {
	local root="$1" scope="$2" file files=()
	if [[ ! -d "$root" || -L "$root" ]]; then
		memory_record postazione esclusi "${scope%/*}" "${root##*/}" "elemento fuori da un ambito dichiarato"
		return 0
	fi
	if ! memory_directory_entries "$root" files; then
		memory_record postazione bloccati "$scope" "" "ambito non dichiarato o percorso illeggibile"
	fi
	for file in "${files[@]}"; do
		memory_record postazione esclusi "$scope" "$file" "ambito non dichiarato nel workspace"
	done
}

commit_archive_with_memory_report() {
	local message="$1" previous spec
	shift
	previous="$(engramma_git rev-parse --verify HEAD 2>/dev/null)" ||
		previous="$(engramma_git hash-object -t tree /dev/null)" || previous=""
	if ! engramma_git add -A -- "$@" || ! engramma_git commit -q -m "$message" -- "$@"; then
		log_line "   Git · salvataggio locale dell’archivio fallito"
		if [[ "$CLAUDE_MEMORY" == on ]]; then
			for spec in "$@"; do
				[[ "$spec" != workspaces/* ]] ||
					memory_worktree_changes "${spec#workspaces/}" bloccati "commit non riuscito"
			done
		fi
		return 1
	fi
	MEMORY_LAST_COMMIT_BASE="$previous"
	if [[ -n "$previous" ]]; then memory_git_changes salvataggio salvati "" "$previous" HEAD || true; fi
	return 0
}

memory_unsent_without_remote() {
	[[ -n "$MEMORY_LAST_COMMIT_BASE" ]] || return 0
	memory_git_changes invio esclusi "branch remoto assente; commit conservati in locale" "$MEMORY_LAST_COMMIT_BASE" HEAD || true
}

memory_worktree_changes() {
	local area="$1" outcome="$2" reason="$3" entry change file
	local -a records=() order=()
	local -A changes=()
	mapfile -d '' -t records < <(
		engramma_git status --porcelain=v1 -z --no-renames --untracked-files=all -- "workspaces/$area/memory" 2>/dev/null
		printf '%s\0' "$?"
	)
	if [[ "${records[-1]:-1}" != 0 ]]; then
		memory_record salvataggio bloccati "$area" "" "impossibile leggere i file modificati nell’archivio"
		return 0
	fi
	unset 'records[-1]'
	for entry in "${records[@]}"; do
		file="${entry:3}"
		[[ -n "$file" ]] || continue
		change="${entry:0:2}"
		if [[ -v 'changes[$file]' ]]; then
			changes[$file]=M
			continue
		fi
		case "$change" in
			'??' | *A*) changes[$file]=A ;;
			*D*) changes[$file]=D ;;
			*T*) changes[$file]=T ;;
			*) changes[$file]=M ;;
		esac
		order+=("$file")
	done
	for file in "${order[@]}"; do
		memory_archive_change salvataggio "$outcome" "$file" "${changes[$file]}" "$reason"
	done
}

preview_memory_transfers() {
	[[ "$(engramma_git rev-parse --show-toplevel 2>/dev/null)" == "$ENGRAMMA_DIR" ]] || return 0
	if has_engramma_remote; then
		memory_git_changes ricezione "da ricevere" "ultimo stato remoto noto; anteprima senza rete" 'HEAD...@{upstream}' || true
		memory_git_changes invio "da inviare" "commit locali rispetto all’ultimo stato remoto noto" '@{upstream}...HEAD' || true
	fi
	local area preview_status="da salvare" preview_reason="anteprima locale"
	if [[ "$CLAUDE_MEMORY" == off ]]; then
		preview_status=esclusi preview_reason="sincronizzazione della memoria disattivata"
	fi
	for area in "$@"; do
		memory_worktree_changes "$area" "$preview_status" "$preview_reason"
	done
}

memory_pending_send() {
	has_engramma_remote || return 0
	memory_git_changes invio "invio da riprovare" "$1" '@{upstream}...HEAD' || true
}

# Use the range Git actually reports, which may differ from the cached remote
# ref (especially for save, which deliberately does not fetch).
push_archive_with_memory_report() {
	local output status ref flag mapping result from to confirmed=false
	ref="$(engramma_git symbolic-ref -q HEAD)" || ref=""
	output="$(GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="ssh -o BatchMode=yes -o ConnectTimeout=10" engramma_git push --porcelain 2>/dev/null)"
	status=$?
	while IFS=$'\t' read -r flag mapping result; do
		[[ -n "$ref" && "${mapping%%:*}" == "$ref" && "$mapping" == *:* ]] || continue
		[[ "$flag" != '!' ]] || continue
		if [[ "$flag" == = ]]; then
			confirmed=true
			memory_git_changes invio "già sul remoto" "Git conferma che il branch è aggiornato" '@{upstream}...HEAD' || true
			continue
		fi
		if [[ "$flag" == '*' ]]; then
			from="$(engramma_git hash-object -t tree /dev/null)" || from=""
			to=HEAD
		elif [[ "$result" =~ ^([[:xdigit:]]+)\.{2,3}([[:xdigit:]]+)([[:space:]]|$) ]]; then
			from="${BASH_REMATCH[1]}" to="${BASH_REMATCH[2]}"
		else
			from=""
		fi
		if [[ -n "$from" ]]; then
			confirmed=true
			memory_git_changes invio inviati "" "$from" "$to" || true
		fi
	done <<<"$output"
	if ((status)); then
		log_line "   Git · push dell’archivio fallito (uscita $status)"
		if ! $confirmed; then memory_pending_send "push fallito; commit conservati in locale"; fi
	elif ! $confirmed; then
		memory_record invio bloccati archivio "" "push riuscito; branch o intervallo non verificabile dal risultato Git"
	fi
	return "$status"
}
