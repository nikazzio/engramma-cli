# shellcheck shell=bash
# shellcheck disable=SC2153 # FILE, REF, CMD and the other colors come from lib/theme.sh

is_engramma_link() {
	[[ -L "$1" && "$(readlink "$1")" == "$ENGRAMMA_DIR"/* ]]
}

detach_link() {
	local link="$1" label="$2" target temporary
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

	temporary="$link.engramma-detach.$$"
	if ! cp -a "$target" "$temporary"; then
		rm -rf "$temporary"
		fail "${REF}$label${RESET}: copia fallita, il symlink resta"
		PROBLEM_COUNT=$((PROBLEM_COUNT + 1))
		return
	fi
	rm "$link"
	mv "$temporary" "$link"
	ok "${REF}$label${RESET}: symlink → copia indipendente"
}

detach_repo_note() {
	local repo="$1" name="$2"
	local note="$WORKSPACE_NOTES_DIR/repo-notes/$name.md"
	local file="$repo/$REPO_NOTE_FILE"

	[[ -f "$file" && -f "$note" && "$(cat "$file")" == "@$note" ]] || return 0

	if [[ "$MODE" == dry ]]; then
		would "${FILE}$REPO_NOTE_FILE${RESET}: @import → testo della nota"
		return
	fi

	cp "$note" "$file.engramma-detach.$$" && mv "$file.engramma-detach.$$" "$file"
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
	for entry in .claude docs AGENTS.md; do
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
		detach_repo_files "$WORKSPACE_DIR/$name" "$name"
	done < <(repo_entries)
}

detach_skills() {
	local dir
	section "skill"
	for dir in "$CLAUDE_HOME"/skills/* "$CODEX_SKILLS_DIR"/*; do
		detach_link "$dir" "skill $(basename "$dir")"
	done
}
