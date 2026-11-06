# shellcheck shell=bash
# Completion of eng and engramma for bash: commands, workspaces, options.
# Linked by eng into ~/.local/share/bash-completion/completions, which
# bash-completion loads by itself.

_eng() {
	local current="${COMP_WORDS[COMP_CWORD]}" previous="${COMP_WORDS[COMP_CWORD - 1]}"
	local command dir workspaces words offset=1
	local archive_args=()
	command="$(command -v "${COMP_WORDS[0]}")" || return 0
	if [[ "${COMP_WORDS[1]:-}" == --data-dir && $COMP_CWORD -gt 2 ]]; then
		archive_args=(--data-dir "${COMP_WORDS[2]}")
		offset=3
	fi
	dir="$("$command" "${archive_args[@]}" --print-data-dir 2>/dev/null)" || dir=""
	workspaces=""
	if [[ -n "$dir" ]]; then
		workspaces="$(cd "$dir/workspaces" 2>/dev/null && printf '%s ' */ | tr -d /)"
	fi
	case "$previous" in
		--path | --data-dir)
			mapfile -t COMPREPLY < <(compgen -d -- "$current")
			return 0
			;;
		-j | --jobs) return 0 ;;
	esac
	if [[ "$current" == -* ]]; then
		words="--data-dir -n --dry-run -v --verbose --path -j --jobs --prune -h --help"
	elif ((COMP_CWORD == offset)); then
		words="sync setup detach list save new add log help $workspaces"
	elif [[ "${COMP_WORDS[offset]}" == detach ]]; then
		words="all $workspaces"
	elif [[ "${COMP_WORDS[offset]}" == save ]]; then
		words="global $workspaces"
	elif [[ "${COMP_WORDS[offset]}" =~ ^(new|log)$ ]] || { [[ "${COMP_WORDS[offset]}" == add ]] && ((COMP_CWORD > offset + 1)); }; then
		return 0
	else
		words="$workspaces"
	fi
	mapfile -t COMPREPLY < <(compgen -W "$words" -- "$current")
}

complete -F _eng eng engramma
