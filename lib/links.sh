# shellcheck shell=bash
# shellcheck disable=SC2153 # FILE, REF, CMD and the other colors come from lib/theme.sh

REPO_NOTE_FILE="CLAUDE.local.md"

# With "adopt" a real folder in place of the link is merged into engramma even
# when it has files engramma lacks: only for folders that belong to engramma,
# like the memory Claude Code writes before the link exists.
ensure_link() {
	local target="$1" link="$2" label="$3" adopt="${4:-}" pending

	for pending in "$link".engramma-*/original; do
		[[ -d "$pending" ]] || continue
		problem "${REF}$label${RESET}: acquisizione interrotta; cartella originale conservata in $(path "$pending")"
		return
	done

	if [[ -L "$link" ]]; then
		if [[ "$(readlink "$link")" == "$target" ]]; then
			fine "${REF}$label${RESET} → symlink ok"
		else
			problem "${REF}$label${RESET}: symlink verso $(path "$(readlink "$link")"), non verso engramma: non lo tocco"
		fi
		return
	fi

	if [[ -d "$link" && -e "$link/.git" ]]; then
		report_repo_in_place_of_link "$link" "$label"
		return
	fi

	if [[ -d "$link" && "$target" == "$ENGRAMMA_DIR"/* && ! -f "$target" ]]; then
		adopt_directory "$target" "$link" "$label" "$adopt"
		return
	fi

	if [[ -f "$link" && -f "$target" ]] && cmp -s "$link" "$target"; then
		case "$MODE" in
			dry) would "${REF}$label${RESET}: copia identica a engramma → la sostituirei con il symlink" ;;
			check) problem "${REF}$label${RESET}: copia identica a engramma al posto del symlink ${DIM}(eng sync la sostituisce)${RESET}" ;;
			*)
				ln -sfn "$target" "$link"
				ok "${REF}$label${RESET}: copia identica sostituita dal symlink"
				;;
		esac
		return
	fi

	if [[ -e "$link" ]]; then
		problem "${REF}$label${RESET}: file locale diverso da engramma, non lo sovrascrivo ${DIM}($(path "$link"))${RESET}"
		fix_with 45 "${CMD}diff $(tilde "$link") $(tilde "$target")${RESET}: porta in engramma quello che serve, poi ${CMD}rm $(tilde "$link")${RESET} e rilancia"
		return
	fi

	case "$MODE" in
		dry) would "${REF}$label${RESET} → symlink a $(path "$target")" ;;
		check) problem "${REF}$label${RESET}: symlink mancante" ;;
		*)
			[[ -e "$target" ]] || mkdir -p "$target"
			mkdir -p "$(dirname "$link")"
			ln -s "$target" "$link"
			ok "${REF}$label${RESET} → symlink creato ${DIM}($(path "$target"))${RESET}"
			;;
	esac
}

# A git clone where engramma wants a link (a repo cloned by hand in the workspace
# folder, with the name of its notes): never touched, with the way out.
report_repo_in_place_of_link() {
	local link="$1" label="$2" origin folder
	origin="$(git -C "$link" remote get-url origin 2>/dev/null)"
	problem "${REF}$label${RESET} è un clone git${origin:+ di $origin}, non gli appunti di engramma: non lo tocco"
	[[ -n "$origin" ]] || return 0
	folder="$(suggested_repo_folder "$origin")"
	next_step 44 "${CMD}mv $(tilde "$link") $(tilde "$(dirname "$link")")/$folder${RESET}, poi in $(path "$WORKSPACE_NOTES_DIR/repos.txt") aggiungi ${CMD}$folder $origin${RESET}"
}

# A real folder where engramma wants a link (a memory written before the link
# existed, a copy left by detach): the files engramma lacks are moved into it,
# the identical ones dropped, then the folder becomes a link. Files that differ
# from engramma stop everything, so nothing is ever overwritten; a backup of the
# whole folder stays in $BACKUP_DIR, outside the archive.
adopt_directory() {
	local target="$1" link="$2" label="$3" adopt="$4" relative new=() different=()
	if [[ -n "$(find "$link" -mindepth 1 ! -type f ! -type d -print -quit)" ]]; then
		problem "${REF}$label${RESET}: la cartella contiene collegamenti o elementi speciali; la lascio intatta"
		return
	fi
	while IFS= read -r -d '' relative; do
		relative="${relative#./}"
		if [[ ! -e "$target/$relative" ]]; then
			new+=("$relative")
		elif ! cmp -s "$link/$relative" "$target/$relative"; then
			different+=("$relative")
		fi
	done < <(cd "$link" && find . -type f -print0)

	if ((${#new[@]})) && [[ "$adopt" != adopt ]]; then
		problem "${REF}$label${RESET}: cartella locale con ${#new[@]} file che engramma non ha, non la tocco ${DIM}($(path "$link"))${RESET}"
		fix_with 45 "$(path "$link"): se è roba tua portala in engramma e rilancia, se è d'altro togli $label da engramma"
		return
	fi

	if ((${#different[@]})); then
		problem "${REF}$label${RESET}: cartella locale con file diversi da engramma: ${REF}${different[*]:0:5}${RESET} ${DIM}($(path "$link"))${RESET}"
		fix_with 45 "${CMD}diff -r $(tilde "$link") $(tilde "$target")${RESET}: porta in engramma quello che serve, poi ${CMD}rm -r $(tilde "$link")${RESET} e rilancia"
		return
	fi

	case "$MODE" in
		dry) would "${REF}$label${RESET}: unirei la cartella locale a engramma (${#new[@]} file nuovi), poi symlink" ;;
		check) problem "${REF}$label${RESET}: cartella locale al posto del symlink ${DIM}(eng sync la unisce a engramma: ${#new[@]} file nuovi)${RESET}" ;;
		*)
			local backup staging
			backup="$BACKUP_DIR/adopted/$BACKUP_STAMP/$(claude_project_key "$link")"
			if [[ -e "$backup" ]] || ! mkdir -p "$(dirname "$backup")" "$target" ||
				! cp -a "$link" "$backup" || ! diff -qr "$link" "$backup" >/dev/null; then
				problem "${REF}$label${RESET}: backup non riuscito o diverso dall'originale; cartella locale intatta"
				return
			fi
			while IFS= read -r -d '' relative; do
				relative="${relative#./}"
				if ! mkdir -p -- "$target/$relative"; then
					problem "${REF}$label${RESET}: impossibile copiare una cartella; cartella locale intatta, backup in $(path "$backup")"
					return
				fi
			done < <(cd "$backup" && find . -mindepth 1 -type d -print0)
			for relative in "${new[@]}"; do
				if ! mkdir -p "$(dirname "$target/$relative")" ||
					! cp -a -n -T -- "$link/$relative" "$target/$relative" ||
					! cmp -s -- "$link/$relative" "$target/$relative"; then
					problem "${REF}$label${RESET}: copia non riuscita o diversa dall'originale; cartella locale intatta, backup in $(path "$backup")"
					return
				fi
			done
			if ! diff -qr "$link" "$backup" >/dev/null; then
				problem "${REF}$label${RESET}: la cartella locale è cambiata durante la copia; la lascio intatta"
				return
			fi
			while IFS= read -r -d '' relative; do
				relative="${relative#./}"
				if ! cmp -s -- "$backup/$relative" "$target/$relative"; then
					problem "${REF}$label${RESET}: verifica dei file non riuscita; cartella locale intatta, backup in $(path "$backup")"
					return
				fi
			done < <(cd "$backup" && find . -type f -print0)
			staging="$(mktemp -d "${link}.engramma-XXXXXXXX")" || {
				problem "${REF}$label${RESET}: impossibile preparare il collegamento; cartella locale intatta"
				return
			}
			if ! mv -- "$link" "$staging/original"; then
				rmdir "$staging"
				problem "${REF}$label${RESET}: impossibile spostare la cartella locale; resta intatta"
				return
			fi
			if ! ln -s "$target" "$link"; then
				if mv -- "$staging/original" "$link"; then
					rmdir "$staging"
					problem "${REF}$label${RESET}: collegamento non creato; cartella locale ripristinata"
				else
					problem "${REF}$label${RESET}: collegamento non creato; cartella originale in $(path "$staging/original"), backup in $(path "$backup")"
				fi
				return
			fi
			rm -rf "$staging"
			ok "${REF}$label${RESET}: ${#new[@]} file nuovi uniti a engramma, ora è symlink ${DIM}(backup in $(path "$backup"))${RESET}"
			;;
	esac
}

ensure_excluded() {
	local repo="$1" pattern="$2" exclude_file
	exclude_file="$(git -C "$repo" rev-parse --path-format=absolute --git-path info/exclude)"

	if [[ -f "$exclude_file" ]] && grep -qxF "$pattern" "$exclude_file"; then
		return
	fi

	case "$MODE" in
		dry) would "${FILE}$pattern${RESET} → .git/info/exclude" ;;
		check) problem "${FILE}$pattern${RESET} non è in .git/info/exclude" ;;
		*)
			mkdir -p "$(dirname "$exclude_file")"
			echo "$pattern" >>"$exclude_file"
			ok "${FILE}$pattern${RESET} → .git/info/exclude"
			;;
	esac
}

ensure_repo_note() {
	local repo="$1" name="$2"
	local note="$WORKSPACE_NOTES_DIR/repo-notes/$name.md"
	local file="$repo/$REPO_NOTE_FILE"
	local expected="@$note"

	[[ -f "$note" ]] || return 0

	if [[ ! -e "$file" ]]; then
		case "$MODE" in
			dry) would "${FILE}$REPO_NOTE_FILE${RESET} → @import della nota personale" ;;
			check) problem "${FILE}$REPO_NOTE_FILE${RESET} mancante: Claude non carica la nota personale" ;;
			*)
				echo "$expected" >"$file"
				ok "${FILE}$REPO_NOTE_FILE${RESET} creato → @$(path "$note")"
				;;
		esac
	elif [[ "$(cat "$file")" == "$expected" ]]; then
		fine "${FILE}$REPO_NOTE_FILE${RESET} → @import ok"
	elif cmp -s "$file" "$note"; then
		case "$MODE" in
			dry) would "${FILE}$REPO_NOTE_FILE${RESET}: copia della nota → la sostituirei con l'@import" ;;
			check) problem "${FILE}$REPO_NOTE_FILE${RESET}: copia della nota al posto dell'@import ${DIM}(eng sync la sostituisce)${RESET}" ;;
			*)
				echo "$expected" >"$file"
				ok "${FILE}$REPO_NOTE_FILE${RESET}: copia sostituita dall'@import"
				;;
		esac
	else
		problem "${FILE}$REPO_NOTE_FILE${RESET} ha un contenuto suo: non lo sovrascrivo ${DIM}(spostalo in repo-notes/$name.md)${RESET}"
	fi

	[[ -e "$file" ]] && ensure_excluded "$repo" "$REPO_NOTE_FILE"
	return 0
}

project_skills() {
	local repo="$1" name="$2" action="$3" target rel link skill
	for target in "$WORKSPACE_NOTES_DIR/skills/$name"/*; do
		[[ -d "$target" && ! -L "$target" && -f "$target/SKILL.md" ]] || continue
		skill="${target##*/}"
		if [[ ! "$skill" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
			problem "Nome skill non valido: $skill"
			continue
		fi
		rel=".agents/skills/$skill"
		link="$repo/$rel"
		if [[ -L "$repo/.agents" || -L "$repo/.agents/skills" ]]; then
			problem "Cartella skill collegata altrove: $rel"
			continue
		fi
		if [[ "$action" == detach ]]; then
			[[ "$(readlink "$link")" != "$target" ]] || detach_link "$link" "$skill"
			continue
		fi
		if [[ -n "$(git -C "$repo" ls-files -- "$rel")" || ( -e "$link" && ! -L "$link" ) ]]; then
			problem "Skill già presente nel progetto: $rel"
			continue
		fi
		if [[ -L "$link" && "$(readlink "$link")" != "$target" ]]; then
			problem "Skill collegata altrove: $rel"
			continue
		fi
		ensure_excluded "$repo" "/$rel"
		ensure_link "$target" "$link" "$skill"
	done
	return 0
}

ensure_repo_files() {
	project_skills "$1" "$2" link
	local repo="$1" name="$2" source
	local files_dir="$WORKSPACE_NOTES_DIR/repo-files/$name"
	[[ -d "$files_dir" ]] || return 0

	local file
	for source in "$files_dir"/* "$files_dir"/.[!.]*; do
		[[ -e "$source" ]] || continue
		file="$(basename "$source")"
		# A file the team versions stays theirs: a link would show up as a change.
		if [[ -n "$(git -C "$repo" ls-files -- ":(literal)$file" 2>/dev/null)" ]]; then
			problem "${FILE}$file${RESET}: versionato nel repo, non lo collego ${DIM}(repo-files/$name/$file)${RESET}"
			continue
		fi
		ensure_link "$source" "$repo/$file" "$file"
		ensure_excluded "$repo" "/$file"
	done
}

required_env_vars() {
	local files_dir="$WORKSPACE_NOTES_DIR/repo-files/$1"
	[[ -d "$files_dir" ]] || return 0
	find "$files_dir" -maxdepth 1 -type f \( -name 'compose*.y*ml' -o -name 'docker-compose*.y*ml' \) -print0 |
		xargs -0 -r grep -hoE '\$\{[A-Za-z_][A-Za-z0-9_]*(:?[-?=+][^}]*)?\}' |
		grep -vE ':?[-=+]' | sed -E 's/^\$\{([A-Za-z0-9_]+).*/\1/' | sort -u
}

check_repo_env_vars() {
	local repo="$1" name="$2" variable missing=()
	while read -r variable; do
		[[ -n "$variable" ]] || continue
		grep -qE "^[[:space:]]*(export[[:space:]]+)?$variable=.+" "$repo/.env" 2>/dev/null || missing+=("$variable")
	done < <(required_env_vars "$name")

	((${#missing[@]})) || return 0
	if [[ -f "$repo/.env" ]]; then
		problem ".env: variabili mancanti o vuote ${REF}${missing[*]}${RESET} ${DIM}(richieste da repo-files/$name)${RESET}"
	else
		problem ".env mancante, servono ${REF}${missing[*]}${RESET} ${DIM}(richieste da repo-files/$name, va ricreato a mano)${RESET}"
	fi
}

ensure_repo_excludes() {
	local repo="$1" name="$2" entry pattern
	while read -r entry pattern; do
		[[ "$entry" == "$name" ]] && ensure_excluded "$repo" "$pattern"
	done < <(read_list_entries "$WORKSPACE_NOTES_DIR/excludes.txt")
}

link_workspace_notes() {
	section "appunti"
	if [[ ! -d "$WORKSPACE_DIR" ]]; then
		case "$MODE" in
			dry) would "mkdir $(path "$WORKSPACE_DIR")" ;;
			check) problem "$(path "$WORKSPACE_DIR") non esiste" ;;
			*) mkdir -p "$WORKSPACE_DIR" && ok "mkdir $(path "$WORKSPACE_DIR")" ;;
		esac
	fi

	local entry
	for entry in .claude docs AGENTS.md mise.toml; do
		[[ -e "$WORKSPACE_NOTES_DIR/$entry" ]] || continue
		ensure_link "$WORKSPACE_NOTES_DIR/$entry" "$WORKSPACE_DIR/$entry" "$entry"
	done
	check_codex_instructions_size "$WORKSPACE_NOTES_DIR/AGENTS.md" "AGENTS.md del workspace"

	if [[ -f "$WORKSPACE_DIR/CLAUDE.md" && -f "$WORKSPACE_NOTES_DIR/.claude/CLAUDE.md" ]]; then
		problem "CLAUDE.md residuo nella cartella del workspace: Claude caricherebbe le regole due volte ${DIM}(da cancellare a mano)${RESET}"
	fi
}

link_memories() {
	section "memoria di Claude"
	link_memory _workspace "$WORKSPACE_DIR" "memoria del workspace"

	local name
	while read -r name _; do
		link_memory "$name" "$WORKSPACE_DIR/$name" "memoria di $name"
	done < <(repo_entries)
}

link_memory() {
	local key="$1" project_dir="$2" label="$3" memory_dir
	memory_dir="$(claude_memory_dir_for "$project_dir")"

	# A memory written on this computer before engramma had one is moved into it.
	if [[ -d "$WORKSPACE_NOTES_DIR/memory/$key" ]] ||
		[[ -d "$memory_dir" && ! -L "$memory_dir" && -n "$(ls -A "$memory_dir")" ]]; then
		ensure_link "$WORKSPACE_NOTES_DIR/memory/$key" "$memory_dir" "$label" adopt
	fi
}

link_skills() {
	local source
	section "skill"
	for source in "$ENGRAMMA_DIR"/skills/*/; do
		[[ -d "$source" ]] || continue
		source="${source%/}"
		ensure_link "$source" "$CLAUDE_HOME/skills/$(basename "$source")" "skill $(basename "$source")"
	done
	remove_orphan_skill_links "$CLAUDE_HOME/skills" ""
	report_unversioned_skills
}

# A link left by a skill removed from engramma: only links that point into
# engramma's skills/ and lead nowhere are removed, everything else is untouched.
remove_orphan_skill_links() {
	local dir="$1" where="$2" link target name
	for link in "$dir"/*; do
		[[ -L "$link" ]] || continue
		target="$(readlink "$link")"
		[[ "$target" == "$ENGRAMMA_DIR/skills/"* && ! -e "$target" ]] || continue
		name="$(basename "$link")"
		case "$MODE" in
			dry) would "${REF}skill $name${RESET}$where: non è più in engramma → toglierei il symlink" ;;
			check) problem "${REF}skill $name${RESET}$where: non è più in engramma, symlink rimasto ${DIM}(eng sync lo toglie)${RESET}" ;;
			*)
				rm "$link"
				ok "${REF}skill $name${RESET}$where: non è più in engramma, symlink tolto"
				;;
		esac
	done
}

report_unversioned_skills() {
	local dir name
	for dir in "$CLAUDE_HOME"/skills/*/; do
		dir="${dir%/}"
		name="$(basename "$dir")"
		[[ -f "$dir/SKILL.md" && ! -L "$dir" ]] || continue
		read_list_file "$ENGRAMMA_DIR/skills-ignore.txt" | awk '{ print $1 }' | grep -qxF "$name" && continue
		info "skill $name non versionata ${DIM}(tua: spostala in skills/; di uno strumento: aggiungila a skills-ignore.txt)${RESET}"
	done
}

# A path without its glob ("/a/b/**" is /a/b) and without the punctuation of the
# sentence it was written in.
path_without_pattern() {
	local found="${1%%[*\{]*}"
	echo "${found%%+([.:/])}"
}

# Absolute paths written by hand in engramma (permissions, imports, notes) break
# when engramma moves to a computer with another user. In notes, imports and the
# file permissions of Claude Code (Read, Edit, Write...) ~/ works everywhere and
# is always proposed; a file permission with a single / is relative to its
# settings file, not absolute. Elsewhere in the settings (Bash rules compare the
# text of the command, additionalDirectories does not document ~) there is no
# portable form: those paths are reported only when they do not exist here.
# Memories (written by Claude) and merged files (rewritten by their programs) are
# left out.
check_absolute_paths() {
	local file found value rest relative absent
	local -A seen=() merged=()
	while read -r file; do
		merged["$GLOBAL_DIR/$file"]=1
	done < <(awk '!/^[[:space:]]*#/ && $3 == "unisci" { print $1 }' "$GLOBAL_DIR/links.txt" 2>/dev/null)
	while IFS=: read -r file value; do
		[[ -z "${merged[$file]:-}" ]] || continue
		relative="${file#"$ENGRAMMA_DIR/"}" value="${value//\"/}"
		if [[ "$value" =~ ^(Read|Edit|Write|Glob|Grep)\((/{1,2})((home|Users)/[^/]+)(/[^\)]*)?\)$ ]]; then
			found="$(path_without_pattern "/${BASH_REMATCH[3]}${BASH_REMATCH[5]}")"
			[[ -z "${seen[$found]:-}" ]] || continue
			seen[$found]=1
			if [[ "${BASH_REMATCH[2]}" == / ]]; then
				warn "permesso ${FILE}$value${RESET} con una sola / iniziale, che Claude Code legge relativa alle impostazioni: scrivi ${CMD}${BASH_REMATCH[1]}(~${BASH_REMATCH[5]})${RESET} ${DIM}in $relative${RESET}"
			else
				warn "permesso ${FILE}$value${RESET} valido solo su questo computer: scrivi ${CMD}${BASH_REMATCH[1]}(~${BASH_REMATCH[5]})${RESET} ${DIM}in $relative${RESET}"
			fi
			continue
		fi
		[[ "$value" =~ (/(home|Users)/[^[:space:]\'\(\)]+) ]] || continue
		found="$(path_without_pattern "${BASH_REMATCH[1]}")"
		[[ "$found" != *'$'* && -z "${seen[$found]:-}" ]] || continue
		seen[$found]=1
		[[ -e "$found" ]] && continue
		if [[ "$value" == Bash\(* ]]; then
			warn "regola ${FILE}$value${RESET}: ${FILE}$found${RESET} non esiste su questo computer ${DIM}(toglila se serviva a un comando una tantum) in $relative${RESET}"
		else
			warn "${FILE}$found${RESET} non esiste su questo computer ${DIM}in $relative${RESET}"
		fi
	done < <(grep -rIoE --exclude-dir=.git --exclude-dir=memory --include='*.json' '"[^"]*(/home|/Users)/[^"]*"' "$@" 2>/dev/null | sort -u)
	while IFS=: read -r file found; do
		[[ -z "${merged[$file]:-}" ]] || continue
		found="$(path_without_pattern "$found")"
		[[ "$found" =~ ^/(home|Users)/[^/]+(/.*)?$ && "$found" != *'$'* && -z "${seen[$found]:-}" ]] || continue
		seen[$found]=1
		rest="${BASH_REMATCH[2]}"
		absent=""
		[[ -e "$found" ]] || absent=" ${DIM}· qui non esiste${RESET}"
		warn "percorso assoluto ${FILE}$found${RESET}: scrivi ${CMD}~$rest${RESET}$absent ${DIM}in ${file#"$ENGRAMMA_DIR/"}${RESET}"
	done < <(grep -rIoE --exclude-dir=.git --exclude-dir=memory --exclude='*.json' '(/home|/Users)/[^][:space:]"'\''`<>()|,;[]+' "$@" 2>/dev/null | sort -u)
}
