# shellcheck shell=bash
# shellcheck disable=SC2153 # FILE, REF, CMD and the other colors come from lib/theme.sh

is_engramma_link() {
	[[ -L "$1" && "$(readlink "$1")" == "$ENGRAMMA_DIR"/* ]]
}

detach_link() {
	local link="$1" label="$2" target staging
	is_engramma_link "$link" || return 0
	target="$(readlink "$link")"

	if [[ ! -e "$target" ]]; then
		problem "${REF}$label${RESET}: symlink rotto verso $(path "$target"), lo lascio"
		return
	fi

	if [[ "$MODE" == dry ]]; then
		would "${REF}$label${RESET}: symlink → copia di $(path "$target")"
		return
	fi

	staging="$(mktemp -d -- "$link.engramma-XXXXXXXX")" || { problem "${REF}$label${RESET}: impossibile preparare la copia"; return; }
	if ! cp -aH -- "$target" "$staging/copy" || ! diff -qr --no-dereference -- "$target" "$staging/copy" >/dev/null; then
		rm -rf -- "$staging"
		problem "${REF}$label${RESET}: copia fallita, il symlink resta"
		return
	fi
	# A directory cannot replace a symlink with rename. Keep the original
	# beside the finished copy until the directory is in place.
	if [[ -d "$staging/copy" ]]; then
		if ! mv -T -- "$link" "$staging/original"; then
			rm -rf -- "$staging"
			problem "${REF}$label${RESET}: impossibile spostare il symlink"
			return
		fi
		if ! mv -Tn -- "$staging/copy" "$link" || [[ -e "$staging/copy" ]]; then
			if ln -sT -- "$target" "$link"; then
				rm -rf -- "$staging"
				problem "${REF}$label${RESET}: sostituzione fallita, symlink ripristinato"
			else
				problem "${REF}$label${RESET}: sostituzione fallita, collegamento originale in $(path "$staging/original")"
			fi
			return
		fi
	elif ! mv -T -- "$staging/copy" "$link"; then
		rm -rf -- "$staging"
		problem "${REF}$label${RESET}: sostituzione fallita, il symlink resta"
		return
	fi
	rm -rf -- "$staging"
	ok "${REF}$label${RESET}: symlink → copia indipendente"
}

detach_repo_note() {
	local repo="$1" name="$2"
	local note="$WORKSPACE_NOTES_DIR/repo-notes/$name.md"
	local file="$repo/$REPO_NOTE_FILE" staging

	[[ -f "$file" && -f "$note" && "$(cat "$file")" == "@$note" ]] || return 0

	if [[ "$MODE" == dry ]]; then
		would "${FILE}$REPO_NOTE_FILE${RESET}: @import → testo della nota"
		return
	fi

	staging="$(mktemp -d -- "$file.engramma-XXXXXXXX")" || { problem "${FILE}$REPO_NOTE_FILE${RESET}: impossibile preparare la nota"; return; }
	if ! cp -- "$note" "$staging/copy" || ! mv -T -- "$staging/copy" "$file"; then
		rm -rf -- "$staging"
		problem "${FILE}$REPO_NOTE_FILE${RESET}: copia della nota fallita, il riferimento originale resta"
		return
	fi
	rmdir -- "$staging"
	ok "${FILE}$REPO_NOTE_FILE${RESET}: @import → testo della nota"
}

detach_repo_files() {
	project_skills "$1" "$2" detach
	local repo="$1" name="$2" source
	local files_dir="$WORKSPACE_NOTES_DIR/repo-files/$name"
	[[ -d "$files_dir" ]] || return 0

	for source in "$files_dir"/* "$files_dir"/.[!.]*; do
		[[ -e "$source" ]] || continue
		detach_link "$repo/$(basename "$source")" "$(basename "$source")"
	done
}

detach_workspace() {
	local entry name

	section "appunti"
	for entry in .claude docs AGENTS.md mise.toml; do
		detach_link "$WORKSPACE_DIR/$entry" "$entry"
	done

	section "memoria di Claude"
	detach_link "$(claude_memory_dir_for "$WORKSPACE_DIR")" "memoria del workspace"
	while read -r name _; do
		detach_link "$(claude_memory_dir_for "$WORKSPACE_DIR/$name")" "memoria di $name"
	done < <(repo_entries)

	while read -r name _; do
		[[ -e "$WORKSPACE_DIR/$name/.git" ]] || continue
		repo_begin "$name"
		detach_repo_note "$WORKSPACE_DIR/$name" "$name"
		detach_link "$WORKSPACE_DIR/$name/$SHARED_REPO_NOTE_FILE" "nota personale per gli agenti"
		detach_link "$WORKSPACE_DIR/$name/$SHARED_WORKSPACE_RULES_FILE" "regole del workspace"
		detach_repo_files "$WORKSPACE_DIR/$name" "$name"
	done < <(repo_entries)
}

detach_skills() {
	local dir
	section "skill"
	for dir in "$CLAUDE_HOME"/skills/* "$CODEX_SKILLS_DIR"/* "$COPILOT_HOME_DIR"/skills/*; do
		detach_link "$dir" "skill $(basename "$dir")"
	done
}

# Scan linked memories on this workstation, including their old locations
# after relocating a repo or workspace.
detach_archive_memories() {
	local entry target
	for entry in "$CLAUDE_HOME"/projects/*/memory; do
		[[ -L "$entry" ]] || continue
		target="$(readlink "$entry")"
		case "$target" in
			"$ENGRAMMA_DIR"/workspaces/*/memory/*)
				detach_link "$entry" "memoria di Claude in $(tilde "$entry")"
				;;
		esac
	done
}

detach_agent_configuration() {
	local agent="$1" source destination entry root
	while read -r source destination _; do
		destination="$(expand_global_destination "$destination")" || continue
		[[ "$(global_link_agent "$source" "$destination")" == "$agent" ]] || continue
		detach_link "$destination" "$source"
	done < <(global_entries)
	case "$agent" in
		claude) root="$CLAUDE_HOME/skills" ;;
		codex) root="$CODEX_SKILLS_DIR" ;;
		copilot) root="$COPILOT_HOME_DIR/skills" ;;
	esac
	for entry in "$root"/*; do
		detach_link "$entry" "skill ${entry##*/} ($agent)"
	done
	detach_workspace_agent_files "$agent"
}

detach_workspace_agent_files() {
	local agent="$1" notes name repo filename
	for notes in "$ENGRAMMA_DIR"/workspaces/*/; do
		[[ -d "$notes" ]] || continue
		load_workspace "$(basename "$notes")"
		case "$agent" in
			claude) detach_link "$WORKSPACE_DIR/.claude" "configurazione Claude del workspace" ;;
			shared) detach_link "$WORKSPACE_DIR/AGENTS.md" "regole del workspace" ;;
		esac
		while read -r name _; do
			repo="$WORKSPACE_DIR/$name"
			[[ -e "$repo/.git" ]] || continue
			case "$agent" in
				claude)
					detach_repo_note "$repo" "$name"
					for filename in .claude CLAUDE.md CLAUDE.local.md; do detach_link "$repo/$filename" "$filename"; done
					;;
				codex) detach_link "$repo/.codex" "configurazione Codex" ;;
				copilot) detach_link "$repo/.copilot" "configurazione Copilot" ;;
				shared)
					project_skills "$repo" "$name" detach
					for filename in .agents AGENTS.md AGENTS.override.md; do detach_link "$repo/$filename" "$filename"; done
					;&
				context)
					detach_link "$repo/$SHARED_REPO_NOTE_FILE" "nota personale per gli agenti"
					detach_link "$repo/$SHARED_WORKSPACE_RULES_FILE" "regole del workspace"
					;;
			esac
		done < <(repo_entries)
	done
}
