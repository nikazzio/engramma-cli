# shellcheck shell=bash
# Completion of eng and engramma for bash: commands, workspaces, options.
# Linked by eng into ~/.local/share/bash-completion/completions, which
# bash-completion loads by itself.

_eng() {
	local current="${COMP_WORDS[COMP_CWORD]}" previous="${COMP_WORDS[COMP_CWORD - 1]}"
	local command dir workspaces words offset=1
	COMPREPLY=()
	local archive_args=()
	command="$(command -v "${COMP_WORDS[0]}")" || return 0
	if [[ "${COMP_WORDS[1]:-}" == --data-dir && $COMP_CWORD -gt 2 ]]; then
		archive_args=(--data-dir "${COMP_WORDS[2]}")
		offset=3
	fi
	dir="$("$command" "${archive_args[@]}" --print-data-dir 2>/dev/null)" || dir=""
	workspaces=""
	if [[ -n "$dir" ]]; then
		workspaces="$(cd "$dir/workspaces" 2>/dev/null && for entry in */; do [[ -d "$entry" ]] && printf '%s ' "${entry%/}"; done)"
	fi
	case "$previous" in
		--path | --data-dir)
			mapfile -t COMPREPLY < <(compgen -d -- "$current")
			return 0
			;;
		-j | --jobs) return 0 ;;
	esac
	if [[ "$current" == -* ]]; then
		words="--version"
		if ((COMP_CWORD == offset)); then
			words+=" -h --help"
			((offset == 1)) && words+=" --data-dir"
		else
			case "${COMP_WORDS[offset]}" in
				sync) words+=" -v --verbose -n --dry-run --path -j --jobs --prune" ;;
				setup | detach) words+=" -v --verbose -n --dry-run" ;;
				init) words+=" -n --dry-run" ;;
				check) words+=" -v --verbose" ;;
			esac
		fi
	elif ((COMP_CWORD == offset)); then
		words="check sync setup init detach list tools integrations save new add log help global $workspaces"
	elif [[ "${COMP_WORDS[offset]}" == detach ]]; then
		words="all global $workspaces"
	elif [[ "${COMP_WORDS[offset]}" == tools ]]; then
		words="global $workspaces"
		((COMP_CWORD == offset + 1)) && words="install $words"
	elif [[ "${COMP_WORDS[offset]}" =~ ^(save|sync|check)$ ]]; then
		words="global $workspaces"
	elif [[ "${COMP_WORDS[offset]}" =~ ^(init|setup)$ ]]; then
		mapfile -t COMPREPLY < <(compgen -d -- "$current")
		return 0
	elif [[ "${COMP_WORDS[offset]}" =~ ^(new|log|integrations|help)$ ]] || { [[ "${COMP_WORDS[offset]}" == add ]] && ((COMP_CWORD > offset + 1)); }; then
		return 0
	else
		words="$workspaces"
	fi
	mapfile -t COMPREPLY < <(compgen -W "$words" -- "$current")
}

complete -F _eng eng engramma
