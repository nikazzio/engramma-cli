# shellcheck shell=bash

KNOWN_AGENTS=(claude codex copilot)
COPILOT_HOME_DIR="${COPILOT_HOME:-$HOME/.copilot}"
ACTIVE_AGENTS=claude
CLAUDE_MEMORY=on
EXPLICIT_AGENTS=false
AGENT_PROFILE=""

valid_agent_list() {
	local agent seen=, members=()
	[[ "$1" == none ]] && return 0
	[[ "$1" =~ ^(claude|codex|copilot)(,(claude|codex|copilot))*$ ]] || return 1
	IFS=, read -ra members <<<"$1"
	for agent in "${members[@]}"; do
		[[ "$seen" != *",$agent,"* ]] || return 1
		seen+="$agent,"
	done
}

agent_in_list() {
	[[ ",$1," == *",$2,"* ]]
}

agent_enabled() {
	if $EXPLICIT_AGENTS; then
		agent_in_list "$ACTIVE_AGENTS" "$1"
		return
	fi
	case "$1" in
		claude) return 0 ;;
		codex) is_global_requirement codex && command -v codex >/dev/null ;;
		*) return 1 ;;
	esac
}

agent_requirement_enabled() {
	$EXPLICIT_AGENTS || return 0
	case "$1" in
		claude | codex | copilot) agent_enabled "$1" ;;
		*) return 0 ;;
	esac
}

agent_profile_path() {
	local key
	key="$(printf '%s' "$1" | sha256sum)" || return 1
	printf '%s/%s\n' "${XDG_CONFIG_HOME:-$HOME/.config}/engramma/agent-profiles" "${key%% *}"
}

load_agent_profile() {
	local source entries=() extra=""
	AGENT_PROFILE="$(agent_profile_path "$ENGRAMMA_DIR")" || return 1
	source="$AGENT_PROFILE"
	if [[ ! -e "$source" ]]; then
		source="$GLOBAL_DIR/agents-defaults.txt"
		[[ -e "$source" ]] || return 0
	fi
	if ! mapfile -t entries <"$source" || ((${#entries[@]} != 1)); then
		say_fail "impossibile leggere la scelta degli agenti in $source"
		return 1
	fi
	read -r ACTIVE_AGENTS CLAUDE_MEMORY extra <<<"${entries[0]}"
	if ! valid_agent_list "$ACTIVE_AGENTS" ||
		[[ -n "$extra" || ! "$CLAUDE_MEMORY" =~ ^(on|off)$ ]] ||
		{ [[ "$CLAUDE_MEMORY" == on ]] && ! agent_in_list "$ACTIVE_AGENTS" claude; }; then
		say_fail "scelta degli agenti non valida in $source"
		return 1
	fi
	EXPLICIT_AGENTS=true
}

save_agent_profile() (
	local staging
	lock_config || return 1
	mkdir -p -- "${AGENT_PROFILE%/*}" || return 1
	staging="$(mktemp -- "$AGENT_PROFILE.XXXXXXXX")" || return 1
	trap 'rm -f -- "$staging"' EXIT
	printf '%s %s\n' "$1" "$2" >"$staging" &&
		mv -T -- "$staging" "$AGENT_PROFILE"
)

resolve_agent_request() {
	NEXT_AGENTS="$ACTIVE_AGENTS"
	if [[ -n "$REQUESTED_AGENTS" ]]; then
		NEXT_AGENTS="$REQUESTED_AGENTS"
	elif ! $EXPLICIT_AGENTS && agent_enabled codex; then
		NEXT_AGENTS+=,codex
	fi
	NEXT_CLAUDE_MEMORY="${REQUESTED_CLAUDE_MEMORY:-$CLAUDE_MEMORY}"
	if ! agent_in_list "$NEXT_AGENTS" claude; then
		[[ "$REQUESTED_CLAUDE_MEMORY" != on ]] || fail_usage "Per sincronizzare la memoria seleziona anche Claude"
		NEXT_CLAUDE_MEMORY=off
	fi
}

apply_agent_request() {
	local agent before="$PROBLEM_COUNT"
	block "scelta degli agenti" "questa postazione"
	for agent in "${KNOWN_AGENTS[@]}"; do
		if agent_enabled "$agent" && ! agent_in_list "$NEXT_AGENTS" "$agent"; then
			detach_agent_configuration "$agent"
		fi
	done
	if [[ "$NEXT_AGENTS" == none && "$ACTIVE_AGENTS" != none ]]; then
		detach_workspace_agent_files shared
	elif [[ "$NEXT_AGENTS" == claude ]] && { agent_enabled codex || agent_enabled copilot; }; then
		detach_workspace_agent_files context
	fi
	if [[ "$CLAUDE_MEMORY" == on && "$NEXT_CLAUDE_MEMORY" == off ]]; then
		detach_archive_memories
	fi
	((PROBLEM_COUNT == before)) || return 1
	if [[ "$MODE" == dry ]]; then
		would "salverei la scelta per questa postazione"
	elif ! save_agent_profile "$NEXT_AGENTS" "$NEXT_CLAUDE_MEMORY"; then
		problem "impossibile salvare la scelta degli agenti"
		return 1
	else
		ok "scelta salvata per questa postazione"
	fi
	ACTIVE_AGENTS="$NEXT_AGENTS"
	CLAUDE_MEMORY="$NEXT_CLAUDE_MEMORY"
	EXPLICIT_AGENTS=true
}

agents_command() {
	local agent status
	for agent in "${KNOWN_AGENTS[@]}"; do
		if agent_enabled "$agent"; then
			status="attivo"
			command -v "$agent" >/dev/null || status+=" · programma da installare"
		else
			status="disattivato"
		fi
		printf '  %-8s %s\n' "$agent" "$status"
	done
	if [[ "$CLAUDE_MEMORY" == on ]]; then
		echo "  Memoria di Claude: sincronizzata per i workspace gestiti"
	else
		echo "  Memoria di Claude: sincronizzazione disattivata"
	fi
	echo "  Memoria di Codex: fuori dalla sincronizzazione"
	echo "  Memoria di Copilot: gestita da GitHub"
	echo "  Cambia la scelta con eng setup --agents claude,codex,copilot --claude-memory off"
}

# Recognize explicit placeholders, private configuration directories and the
# agent-specific source namespaces in older archives.
global_link_agent() {
	local source="$1" destination="$2"
	case "$destination" in
		"$CLAUDE_HOME" | "$CLAUDE_HOME/"* | "$HOME/.claude.json") echo claude ;;
		"$CODEX_HOME_DIR" | "$CODEX_HOME_DIR/"* | "$CODEX_SKILLS_DIR/"*) echo codex ;;
		"$COPILOT_HOME_DIR" | "$COPILOT_HOME_DIR/"*) echo copilot ;;
		*)
			case "$source" in
				claude/* | codex/* | copilot/*) echo "${source%%/*}" ;;
			esac
			;;
	esac
}

global_link_enabled() {
	local agent
	$EXPLICIT_AGENTS || return 0
	agent="$(global_link_agent "$1" "$2")"
	[[ -z "$agent" ]] || agent_enabled "$agent"
}

check_selected_agent() {
	$EXPLICIT_AGENTS || return 0
	local agent="$1" help
	command -v "$agent" >/dev/null && return 0
	case "$agent" in
		claude) help=https://code.claude.com/docs/en/setup ;;
		codex) help=https://github.com/openai/codex ;;
		copilot) help=https://docs.github.com/copilot/how-tos/copilot-cli/install-copilot-cli ;;
	esac
	problem "$agent selezionato, programma assente"
	fix_with 10 "Installa $agent: $help"
}

print_managed_context_instructions() {
	echo 'Prima di lavorare in un repository, rispetta le istruzioni del team del repository. Leggi anche .engramma-workspace.md e .engramma-notes.md se sono presenti nella sua radice. Contengono rispettivamente le regole del workspace e le note personali.'
}

shared_agent_rules() {
	if [[ -f "$GLOBAL_DIR/AGENTS.md" ]]; then
		echo "$GLOBAL_DIR/AGENTS.md"
	else
		# shellcheck disable=SC2016 # Compare the literal placeholder in links.txt.
		global_source_for '${CLAUDE_HOME}/CLAUDE.md'
	fi
}
